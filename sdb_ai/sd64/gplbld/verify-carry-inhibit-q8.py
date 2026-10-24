#!/usr/bin/env python3
#
# sandbox-inhibit-q8.py - QM4 gaps bundle Q-8 (commands): INHIBIT.LOGIN.  No install, no sudo.
#
#   python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/sandbox-inhibit-q8.py <dir> [--build]
#
# <dir> is a sandbox made by sandbox-fromtree.py.  With --build it is built first from THIS tree (it must be empty or
# absent).  Exit 0 every row passed, 1 a row failed, 2 it could not run.
#
# START-HISTORY:
# 15 Oct 26 dm  Written for QM4 gaps bundle Q-8: INHIBIT.LOGIN (!login_inhibit, the verb, LOGIN and APISRVR).
# END-HISTORY
#
# THE INSTRUMENT.  Sessions are real: bin/sd with a pipe on stdin, ordinary ones in a fixture account (no -internal,
# SDTEST_ADMIN unset: CPROC is patched, as sandbox-gates.py and sandbox-listu-a5.py patch it, so that the sandbox user is
# the administrator only when asked) and administrator ones (SDTEST_ADMIN=1).  A login is judged by what the session did:
# a probe prints IN[who] if it ran, and the refusal's own words are matched, so a session that never started cannot pass
# as "refused" and a refusal cannot pass as "ran".  The hold is also read from the disk (the record login.inhibit in the
# SDSYS directory) and the audit trail (sys/audit) is read.
#
#   A  the verb: state, ON, OFF, lower case, bad words, a non-administrator
#   B  the refusal: an ordinary session is refused, an administrator one runs, a second ON is refused, a session that was
#      already running is untouched, the setter's phantom starts, an administrator turns it off from another session
#   C  a setter that has gone (killed, no OFF) does not lock everybody out
#   D  the source order in LOGIN and the API server (a sandbox cannot host an API session: the refusal there is source only)
#
# NOT TESTED HERE: an API session, and the refusal of a phantom that is NOT the setter's (a phantom cannot start in an
# ordinary fixture account of a sandbox).

import getpass
import os
import re
import shutil
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.path.join(HERE, "sandbox-fromtree.py")
TREE = os.path.dirname(HERE)
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
    say("sandbox-inhibit-q8: CANNOT RUN - " + msg)
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
    """A session on a pipe kept open.  admin=True: the administrator's, in the SDSYS account; otherwise an ordinary one in
    the fixture account.  It ends with OFF unless hold=True; send() types a further line into a held one."""

    def __init__(self, tag, cmds, account=None, admin=False, hold=False):
        self.out = os.path.join(BOX, "live-%s.out" % tag)
        self.fh = open(self.out, "w")
        argv = [SD] + (["-a" + account] if account else [])
        cwd = SYS if admin else os.path.join(BOX, "user_accounts", account)
        self.p = subprocess.Popen(argv, stdin=subprocess.PIPE, stdout=self.fh, stderr=subprocess.STDOUT, cwd=cwd,
                                  env=env(admin), text=True)
        self.p.stdin.write("\nTERM 200,9999\n" + "".join(c + "\n" for c in cmds) + ("" if hold else "OFF\n"))
        self.p.stdin.flush()
        say("    > live %s%s in %s: %s" % (tag, " [admin]" if admin else "", account or "sdsys", " | ".join(cmds)))
        lives.append(self)

    def send(self, line):
        say("    > live send: " + line)
        self.p.stdin.write(line + "\n")
        self.p.stdin.flush()

    def text(self):
        self.fh.flush()
        return ANSI.sub("", open(self.out, errors="replace").read())

    def wait_for(self, pattern, seconds=30):
        end = time.time() + seconds
        while time.time() < end:
            if re.search(pattern, self.text()):
                return True
            time.sleep(0.3)
        return False

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


def hold_file():
    p = os.path.join(SYS, "login.inhibit")
    if not os.path.isfile(p):
        return None
    with open(p, errors="replace") as f:
        return f.read().split("\n")


def audit_text():
    try:
        with open(os.path.join(SYS, "audit"), errors="replace") as f:
            return f.read()
    except OSError:
        return ""


# ---------------------------------------------------------------------------------------------------------------------
# The probes.  The same user probes go in the fixture account's bp and in SDSYS's.

USER_PROGS = {
    "zzin": "   crt 'IN[':@who:']'\nend\n",
    "zzin2": "   crt 'IN2[':@who:']'\nend\n",
    # the verb, run from a program: what it printed is the screen, and the return code it set is shown after
    "zzst": "   execute 'INHIBIT.LOGIN'\n   crt 'RC[':@system.return.code:']'\nend\n",
    "zzon": "   execute 'INHIBIT.LOGIN ON'\n   crt 'RC[':@system.return.code:'][':@userno:']'\nend\n",
    "zzoff": "   execute 'INHIBIT.LOGIN OFF'\n   crt 'RC[':@system.return.code:']'\nend\n",
    "zzlow": ("   execute 'inhibit.login on'\n   crt 'RC1[':@system.return.code:'][':@userno:']'\n"
              "   execute 'inhibit.login off'\n   crt 'RC2[':@system.return.code:']'\nend\n"),
    "zzbad": ("   execute 'INHIBIT.LOGIN MAYBE'\n   crt 'RC1[':@system.return.code:']'\n"
              "   execute 'INHIBIT.LOGIN ON OFF'\n   crt 'RC2[':@system.return.code:']'\nend\n"),
    # a phantom the setter starts: it leaves a record in the bp directory
    # this session's own user number and process id, from the user table, for the backup login hold rows
    "zzme": ("   call !listu(d)\n   for i = 1 to dcount(d, @fm)\n      if d<i,1> = @userno then crt 'ME[':d<i,1>:'][':d<i,2>:']'\n   next i\n"
             "end\n"),
    "zzph": "   open 'bp' to f else stop 'no bp'\n   write 'phantom ran' to f, 'zzphdone'\nend\n",
    "zzphs": ("   open 'bp' to f else stop 'no bp'\n   delete f, 'zzphdone'\n   execute 'PHANTOM NO.MSG RUN bp zzph' capturing j\n"
              "   t = 0\n   loop\n      read r from f, 'zzphdone' then exit\n      t += 1\n   until t >= 150\n      nap 100\n   repeat\n"
              "   crt 'PH[':r:'][':(t < 150):']'\nend\n"),
}


def prepare():
    """A CPROC that is not the install build, so the sandbox user is the administrator only when SDTEST_ADMIN=1."""
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


def build_account(name):
    """A directory with a VOC made from NEWVOC plus INHIBIT.LOGIN (an administrator's verb: NEWVOC does not carry it, and
    this account is given it as an administrator could give it, to see the verb's own refusal), a bp directory with the
    user probes, and a register record whose group is the sandbox user's own."""
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
        "   write 'V':@fm:'CA':@fm:'$inhibit' to v, 'inhibit.login'",
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


def clear_hold():
    for nm in ("login.inhibit", "login.hold"):
        p = os.path.join(SYS, nm)
        if os.path.exists(p):
            os.remove(p)


def tag(lines, name):
    m = [re.match(r"^%s\[(.*)\]\s*$" % name, ln) for ln in lines]
    return [x.group(1) for x in m if x]


def main():
    global BOX, SYS, SD
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) != 1:
        bail("usage: sandbox-inhibit-q8.py <dir> [--build]")
    BOX = os.path.abspath(args[0])
    SYS = os.path.join(BOX, "sys")
    SD = os.path.join(SYS, "bin", "sd")
    say("sandbox-inhibit-q8: sandbox  %s" % BOX)
    say("sandbox-inhibit-q8: user %s, group %s" % (USER, GROUP))
    if "--build" in sys.argv:
        if os.path.exists(BOX) and os.listdir(BOX):
            bail("%s is not empty" % BOX)
        r = subprocess.run([sys.executable, TOOL, BOX, "all"], capture_output=True, text=True, errors="replace", timeout=900)
        if "[FAIL]" in r.stdout or r.returncode != 0 or "[PASS] THIRD.COMPILE" not in r.stdout:
            bail("the sandbox build did not pass:\n" + r.stdout[-800:])
        say("sandbox-inhibit-q8: built, bootstrap passed")
    elif not os.path.isfile(SD):
        bail("%s holds no built sandbox (use --build, or point it at one)" % BOX)
    subprocess.run([sys.executable, TOOL, BOX, "start"], capture_output=True, text=True, errors="replace", timeout=120)

    say("\n--- preparation: a CPROC that is not the install build, one fixture account, the probes ------------------------")
    prepare()
    build_account("zzaa")
    for nm, text in USER_PROGS.items():
        put(os.path.join(SYS, "bp", nm), text)
    out = adm(["BASIC bp " + " ".join(USER_PROGS)])
    if not has(out, r"^Compiled %d program\(s\) with no errors" % len(USER_PROGS)):
        bail("the probes did not compile in the SDSYS account:\n" + "\n".join(out[-8:]))
    out = plain("zzaa", ["RUN bp zzin"])
    if tag(out, "IN") != ["zzaa"]:
        bail("the fixture account does not run its probe, so no row below can mean anything:\n" + "\n".join(out[-8:]))
    clear_hold()
    # the audit trail is appended to, never created, by the kernel (k_error.c): a sandbox has none until it is made, as the
    # installer makes the real one
    audit = os.path.join(SYS, "audit")
    if not os.path.exists(audit):
        put(audit, "")
    say("  [done] account zzaa, the probes in it and in SDSYS; no hold on disk; an empty audit trail")

    try:
        say("\n--- A. the verb ------------------------------------------------------------------------------------------")
        out = adm(["RUN bp zzst"])
        row("A1: with nothing set it says so, and @SYSTEM.RETURN.CODE is zero", has(out, r"^Logins are allowed$") and tag(out, "RC") == ["0"],
            repr(out[-5:]))
        row("A1: ... and there is no record on disk", hold_file() is None)

        out = adm(["RUN bp zzon", "RUN bp zzst", "RUN bp zzoff", "RUN bp zzst"])
        say("      (the lines: %r)" % [ln for ln in out if "Logins" in ln or ln.startswith("RC")])
        m = re.findall(r"(?m)^Logins are inhibited by (\S+) \(user (\d+)\)$", "\n".join(out))
        row("A2: ON shows 'Logins are inhibited by <user> (user N)'", len(m) >= 1 and m[0][0] == USER, repr(out[-12:]))
        # zzon prints RC[code][@userno]: the return code and the user number side by side
        mon = re.search(r"(?m)^RC\[(\d+)\]\[(\d+)\]$", "\n".join(out))
        row("A2: ... @SYSTEM.RETURN.CODE after ON equals @USERNO (openQM's rule for success), and it is the number shown",
            mon is not None and mon.group(1) == mon.group(2) and len(m) >= 1 and m[0][1] == mon.group(1), repr(out[-12:]))
        row("A2: ... the plain state shows the same inhibit, then OFF says logins are allowed with return code 0, and the state after it too",
            len(m) >= 2 and m[0] == m[1] and tag(out, "RC")[-2:] == ["0", "0"] and has(out, r"^Logins are allowed$"), repr(out[-12:]))
        row("A2: ... and the record is gone from the disk after OFF", hold_file() is None)

        out = adm(["RUN bp zzon"])
        rec = hold_file()
        row("A3: ON writes the record login.inhibit in SDSYS: user number, process id, login name, date, time",
            rec is not None and len(rec) >= 5 and re.match(r"^\d+$", rec[0]) and re.match(r"^\d+$", rec[1]) and rec[2] == USER
            and re.match(r"^\d{4}-\d\d-\d\d$", rec[3]) and re.match(r"^\d\d:\d\d:\d\d$", rec[4]), repr(rec))
        adm(["RUN bp zzoff"])
        # the session that set it has ended (OFF at the end of sd()); a record left by it would be stale.  clear it so
        # the next rows start from nothing
        clear_hold()

        out = adm(["RUN bp zzlow"])
        row("A4: the command word in lower case is the same command: ON, then OFF (return codes @USERNO and 0)",
            re.search(r"(?m)^RC1\[(\d+)\]\[\1\]$", "\n".join(out)) is not None and tag(out, "RC2") == ["0"], repr(out[-8:]))

        out = adm(["RUN bp zzbad"])
        row("A5: INHIBIT.LOGIN MAYBE is refused (Unexpected token (MAYBE)) and so is ON OFF (Unexpected token (OFF))",
            has(out, r"Unexpected token \(MAYBE\)") and has(out, r"Unexpected token \(OFF\)"), repr(out[-8:]))
        row("A5: ... and neither set anything", hold_file() is None)

        out = plain("zzaa", ["INHIBIT.LOGIN ON"])
        row("A6: a user who is not the administrator is refused (Command requires administrator privileges) even with the verb in "
            "the account's VOC", has(out, r"Command requires administrator privileges"), repr(out[-4:]))
        row("A6: ... and nothing is set", hold_file() is None)

        # -------------------------------------------------------------------------------------------------------
        say("\n--- B. the refusal ----------------------------------------------------------------------------------------")
        out = plain("zzaa", ["RUN bp zzin"])
        row("B1: CONTROL: an ordinary session logs in and runs its probe when nothing is set", tag(out, "IN") == ["zzaa"], repr(out[-4:]))

        s = Live("running", ["RUN bp zzin"], account="zzaa", hold=True)
        row("B1: ... and one is left running before the inhibit (it is the session B6 tests)", s.wait_for(r"(?m)^IN\[zzaa\]"), s.text()[-200:])

        h = Live("setter", ["RUN bp zzon"], admin=True, hold=True)
        row("B2: the administrator sets it from a session that stays open", h.wait_for(r"(?m)^Logins are inhibited by "), h.text()[-300:])
        hold = hold_file()
        row("B2: ... and the record is on the disk", hold is not None and len(hold) >= 3 and hold[2] == USER, repr(hold))
        setter_no = hold[0] if hold else None

        out = plain("zzaa", ["RUN bp zzin"])
        row("B3: an ordinary session is REFUSED, in words: 'logins have been inhibited by %s'" % USER,
            has(out, r"SD is not accepting new sessions: logins have been inhibited by %s \(inhibit\.login\)" % re.escape(USER)), repr(out[-6:]))
        row("B3: ... and its program never ran (no IN[...] line)", tag(out, "IN") == [], repr(out[-6:]))
        au = audit_text()
        row("B3: ... and the audit trail has the refused login with its reason, in lower case",
            re.search(r"login refused account=\S* reason=logins are inhibited \(inhibit\.login\)", au) is not None, repr(au[-300:]))
        row("B3: ... and the audit trail has the setting: 'inhibit.login on'", "inhibit.login on" in au, repr(au[-300:]))

        out = adm(["RUN bp zzin", "RUN bp zzst"])
        row("B4: the administrator can still sign in - a second administrator session runs its probe", len(tag(out, "IN")) == 1, repr(out[-6:]))
        row("B4: ... and sees who has it: 'Logins are inhibited by %s (user %s)'" % (USER, setter_no),
            has(out, r"^Logins are inhibited by %s \(user %s\)$" % (re.escape(USER), setter_no)) and tag(out, "RC") == [setter_no or "?"],
            repr(out[-6:]))

        out = adm(["RUN bp zzon"])
        row("B5: a second administrator session cannot set it while a live one holds it (Logins are already inhibited by %s)" % USER,
            has(out, r"Logins are already inhibited by %s" % re.escape(USER)), repr(out[-6:]))
        hold = hold_file()
        row("B5: ... and the record is still the first session's (user number %s)" % setter_no, hold is not None and hold[0] == setter_no, repr(hold))

        s.send("RUN bp zzin2")
        row("B6: a session that was ALREADY running is not touched: it runs a second probe while the inhibit is set",
            s.wait_for(r"(?m)^IN2\[zzaa\]", 20), s.text()[-300:])

        h.send("RUN bp zzphs")
        row("B7: the setter's phantom starts under the inhibit (it leaves its record; the setter's session waits for it)",
            h.wait_for(r"(?m)^PH\[phantom ran\]\[1\]", 40), h.text()[-300:])

        out = adm(["RUN bp zzoff", "RUN bp zzst"])
        row("B8: another administrator session switches it off (the setter's session is still open): logins are allowed, return code 0",
            has(out, r"^Logins are allowed$") and tag(out, "RC") == ["0", "0"], repr(out[-8:]))
        row("B8: ... and the record is gone", hold_file() is None)
        out = plain("zzaa", ["RUN bp zzin"])
        row("B8: ... and an ordinary session logs in again", tag(out, "IN") == ["zzaa"], repr(out[-4:]))
        row("B8: ... and the audit trail has 'inhibit.login off'", "inhibit.login off" in audit_text())
        h.send("OFF")
        s.send("OFF")
        h.wait(30)
        s.wait(30)

        # -------------------------------------------------------------------------------------------------------
        say("\n--- C. a setter that has gone ------------------------------------------------------------------------------")
        h2 = Live("gone", ["RUN bp zzon"], admin=True, hold=True)
        row("C1: a session sets it and stays open", h2.wait_for(r"(?m)^Logins are inhibited by "), h2.text()[-300:])
        row("C1: CONTROL: it is in force - an ordinary session is refused",
            has(plain("zzaa", ["RUN bp zzin"]), r"logins have been inhibited by"))
        h2.kill()                       # SIGKILL: no OFF, no cleanup of its own
        time.sleep(1)
        row("C1: the killed setter left the record on the disk (this is what a crash leaves)", hold_file() is not None)
        out = plain("zzaa", ["RUN bp zzin"])
        row("C2: an ordinary session now logs in: a hold whose holder has gone (no user-table entry with its number and process id) is ignored",
            tag(out, "IN") == ["zzaa"], repr(out[-6:]))
        out = adm(["RUN bp zzst"])
        row("C2: ... and the state says logins are allowed", has(out, r"^Logins are allowed$") and tag(out, "RC") == ["0"], repr(out[-4:]))
        out = adm(["RUN bp zzon"])
        row("C2: ... and a new ON replaces the stale record (it is not refused as 'already inhibited')",
            not has(out, r"already inhibited") and has(out, r"^Logins are inhibited by "), repr(out[-6:]))
        clear_hold()

        # -------------------------------------------------------------------------------------------------------
        say("\n--- E. the backup login hold (S.50) and a killed holder -----------------------------------------------------------")
        h3 = Live("bakholder", ["RUN bp zzme"], admin=True, hold=True)
        ok = h3.wait_for(r"(?m)^ME\[\d+\]\[\d+\]", 30)
        mm = re.search(r"(?m)^ME\[(\d+)\]\[(\d+)\]", h3.text())
        row("E0: setup: an administrator session is open and says its own user number and process id", ok and mm is not None, h3.text()[-200:])
        if mm:
            uid, pid = mm.groups()
            # the record BACKUP.ACCOUNT writes: userno, pid, login name, verb, date, time - one field per line
            hold_path = os.path.join(SYS, "login.hold")
            put(hold_path, "\n".join([uid, pid, USER, "BACKUP.ACCOUNT", "2026-10-15", "12:00:00"]) + "\n")
            out = plain("zzaa", ["RUN bp zzin"])
            row("E1: CONTROL: with the hold set by a live session, an ordinary login is refused (SD is not accepting new sessions while "
                "%s runs BACKUP.ACCOUNT)" % USER,
                has(out, r"not accepting new sessions while %s runs BACKUP\.ACCOUNT" % re.escape(USER)) and tag(out, "IN") == [], repr(out[-5:]))
            h3.kill()                    # SIGKILL: the user table keeps its row until "sd -cleanup"
            time.sleep(1)
            out = plain("zzaa", ["RUN bp zzin"])
            row("E2: the holder was killed (its user table row is still there, its process is not): an ordinary login now goes in",
                tag(out, "IN") == ["zzaa"], repr(out[-5:]))
            os.remove(hold_path)

        # -------------------------------------------------------------------------------------------------------
        say("\n--- D. source order (the API server cannot be run in a sandbox) -----------------------------------------------")
        def src(name):
            with open(os.path.join(TREE, "sdsys", "gpl.bp", name), encoding="latin-1") as f:
                return f.read()
        lg = src("login")
        a = lg.find("call !acc_hold('TEST'")
        b = lg.find("call !login_inhibit('TEST'")
        t = lg.find("terminate.connection:")
        row("D1: LOGIN asks !login_inhibit after the backup hold and before it sets anything up, and refuses through terminate.connection",
            0 < a < b < t and "audit.reason = 'logins are inhibited (inhibit.login)'" in lg, "%d %d %d" % (a, b, t))
        ap = src("apisrvr")
        holds = [m.start() for m in re.finditer(r"call !acc_hold\('TEST'", ap)]
        inh = [m.start() for m in re.finditer(r"call !login_inhibit\('TEST'", ap)]
        row("D2: APISRVR asks !login_inhibit at both of its login paths, each straight after !acc_hold",
            len(holds) == 2 and len(inh) == 2 and all(0 < i - h < 1200 for h, i in zip(holds, inh)), "%r %r" % (holds, inh))
        row("D3: the bootstrap list in BBPROC compiles login_inhibit before LOGIN first runs", "src.list<-1> = 'login_inhibit'" in src("bbproc"))
        row("D4: the verb is an administrator's: in voc_template (SDSYS's VOC), not in newvoc",
            os.path.isfile(os.path.join(TREE, "sdsys", "voc_template", "inhibit.login"))
            and not os.path.exists(os.path.join(TREE, "sdsys", "newvoc", "inhibit.login")))
    finally:
        for lv in lives:
            lv.kill()
        clear_hold()
        for d in ("bp", "bp.out"):
            for nm in list(USER_PROGS) + ["zzfix", "zzphdone"]:
                p = os.path.join(SYS, d, nm)
                if os.path.exists(p):
                    os.remove(p)

    say("\nsandbox-inhibit-q8: %d passed, %d failed" % (passed, failed))
    if passed + failed == 0:
        bail("no row ran - a broken test, not a pass")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
