#!/usr/bin/env python3
#
# sandbox-option-q17.py - the QM4 gaps tab, bundle Q-17 (OPTION names), first sitting, 15 Oct 2026: GIT, DIR.DTM, KEEP.OLD.OBJECT,
#                         NO.PHANTOM.NOTIFY, SPOOL.COMMAND and ASSOC.ALL, each run before and after OPTION.  No install, no sudo.
#
#   python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/sandbox-option-q17.py <dir> [--build]
#
# <dir> is a sandbox made by sandbox-fromtree.py (needs a `make`d bin/sd).  With --build it is built first from
# THIS tree (it must be empty or absent).  Exit 0 every row passed, 1 a row failed, 2 it could not run.
#
# START-HISTORY:
# 27 Oct 26 dm  S.87 batch 8: the CORRELATIVE.NOCASE option legs are retired (the A;NOCASE; flag rows stay).
# 27 Oct 26 dm  S.87 batch 7: the KEEP.OLD.OBJECT and ASSOC.ALL legs are retired with the options.
# 15 Oct 26 dm  Written.
# END-HISTORY
#
# THE INSTRUMENT.  Each option has its off state run first, as the control, and its on state after: a row that only passes on one side
# shows nothing.  GIT and DIR.DTM are judged on the DISK (the file names in the directory file's folder, and the folder's modification
# time, which the harness first sets to 2020 so that "now" cannot be what it already was).  SPOOL.COMMAND needs a print that runs a
# harmless spooler: the sandbox's sd.conf gets SPOOLER=true for it and is put back.  NO.PHANTOM.NOTIFY starts a real phantom, which the
# sandbox user (who plays the administrator) can do.

import os
import re
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.path.join(HERE, "sandbox-fromtree.py")
ANSI = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]")
MARK = "# --- sandbox-option-q17 below ---"
passed = failed = 0
made = []


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
    say("sandbox-option-q17: CANNOT RUN - " + msg)
    sys.exit(2)


def sess(box, *cmds):
    say("    > %s" % " | ".join(c if len(c) < 60 else c[:57] + "..." for c in cmds))
    p = subprocess.run([sys.executable, TOOL, box, "sess", os.path.join(box, "user_accounts")] + list(cmds),
                       capture_output=True, text=True, errors="replace", timeout=900)
    return ANSI.sub("", p.stdout + p.stderr).split(":TERM 200,9999", 1)[-1]


def tool(box, *args):
    return subprocess.run([sys.executable, TOOL, box] + list(args), capture_output=True, text=True, errors="replace", timeout=900)


def put(sysd, name, text):
    with open(os.path.join(sysd, "bp", name), "w") as f:
        f.write(text)
    made.append(name)


def tag(out, name):
    m = re.search(r"(?m)^%s\[(.*)\]\s*$" % name, out)
    return None if m is None else m.group(1)


def restart(box, *extra):
    conf = os.path.join(box, "sd.conf")
    tool(box, "stop")
    with open(conf) as f:
        base = f.read().split(MARK)[0].rstrip("\n") + "\n"
    with open(conf, "w") as f:
        f.write(base + ((MARK + "\n" + "".join(l + "\n" for l in extra)) if extra else ""))
    r = tool(box, "start")
    return r.returncode == 0


GITP = ("   execute 'DELETE.FILE zzqgit' capturing j\n   execute 'CREATE.FILE zzqgit DIRECTORY' capturing j\n"
        "   open 'zzqgit' to f else stop 'no f'\n"
        "   write 'ignore me' on f, '.gitignore'\n   write 'attrs' on f, '.gitattributes'\n   write 'other' on f, '.hidden'\n   write 'plain' on f, 'plain'\n"
        "   read a from f, '.gitignore' else a = '?'\n   read b from f, '.gitattributes' else b = '?'\n   read c from f, '.hidden' else c = '?'\n"
        "   crt 'READ[':a:'|':b:'|':c:']'\n"
        "   crt 'PATH[':fileinfo(f, 2):']'\n   crt 'END'\nend\n")

DTMP = ("   open 'zzqdtm' to f else stop 'no f'\n   write 'again' on f, 'r1'\n   crt 'WROTE'\nend\n")
DTMMK = ("   execute 'DELETE.FILE zzqdtm' capturing j\n   execute 'CREATE.FILE zzqdtm DIRECTORY' capturing j\n"
         "   open 'zzqdtm' to f else stop 'no f'\n   write 'first' on f, 'r1'\n   crt 'PATH[':fileinfo(f, 2):']'\nend\n")


PHP_NOTIFY = "   crt 'a phantom'\nend\n"
PHP_QUIET = "   execute 'OPTION NO.PHANTOM.NOTIFY ON'\n   crt 'a phantom'\nend\n"
PHDRIVER = ("   execute 'PHANTOM RUN bp zzqphn' capturing j\n   sleep 3\n   m = get.messages()\n   crt 'MSGS1[':convert(@fm, '|', m):']'\n"
            "   execute 'PHANTOM RUN bp zzqphq' capturing j\n   sleep 3\n   m = get.messages()\n   crt 'MSGS2[':convert(@fm, '|', m):']'\n"
            "   crt 'END'\nend\n")

SPOOLP = ("   execute 'SETPTR 0,80,60,0,1' capturing j\n   printer on\n   print 'hello'\n   printer close\n   crt 'END'\nend\n")

# second sitting, 15 Oct 26: CORRELATIVE.NOCASE and CORRELATIVE.REUSE.  An I-type that compares F3 with "abc" over the record
# whose F3 is ABC, and an I-type F1 + F2 over a record whose F1 has three values and F2 two (10, 20): without REUSE the missing third value of F2
# counts as zero (3), with it the last value is used again (23)
CORMK = ("   execute 'DELETE.FILE zzqcc' capturing j\n   execute 'CREATE.FILE zzqcc' capturing j\n"
         "   open 'dict','zzqcc' to d else stop 'no dict'\n"
         "   write 'D':@fm:1:@fm:'':@fm:'F1':@fm:'10L':@fm:'M' on d, 'f1'\n"
         "   write 'D':@fm:2:@fm:'':@fm:'F2':@fm:'10L':@fm:'M' on d, 'f2'\n"
         "   write 'D':@fm:3:@fm:'':@fm:'F3':@fm:'10L':@fm:'S' on d, 'f3'\n"
         "   write 'I':@fm:'IF F3 = \"abc\" THEN \"same\" ELSE \"diff\"':@fm:'':@fm:'CASEX':@fm:'8L':@fm:'S' on d, 'casex'\n"
         "   write 'I':@fm:'F1 + F2':@fm:'':@fm:'SUMX':@fm:'8R':@fm:'M' on d, 'sumx'\n"
         "   write 'A':@fm:3:@fm:'':@fm:'CASEA':@fm:'8L':@fm:'S':@fm:'':@fm:'A;NOCASE;IF 3 = \"abc\" THEN \"same\" ELSE \"diff\"' on d, 'casea'\n"
         "   write 'A':@fm:3:@fm:'':@fm:'CASEB':@fm:'8L':@fm:'S':@fm:'':@fm:'A;IF 3 = \"abc\" THEN \"same\" ELSE \"diff\"' on d, 'caseb'\n"
         "   open 'zzqcc' to f else stop 'no f'\n"
         "   write '1':@vm:'2':@vm:'3':@fm:'10':@vm:'20':@fm:'ABC' on f, 'r1'\n   crt 'MADE'\nend\n")


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) != 1:
        bail("usage: sandbox-option-q17.py <dir> [--build]")
    box = os.path.abspath(args[0])
    sysd = os.path.join(box, "sys")
    say("sandbox-option-q17: sandbox %s" % box)
    if "--build" in sys.argv:
        if os.path.exists(box) and os.listdir(box):
            bail("%s is not empty" % box)
        r = tool(box, "all")
        if "[FAIL]" in r.stdout or r.returncode != 0 or "[PASS] THIRD.COMPILE" not in r.stdout:
            bail("the sandbox build did not pass:\n" + r.stdout[-800:])
        say("sandbox-option-q17: built, bootstrap passed")
    elif not os.path.isfile(os.path.join(sysd, "bin", "sd")):
        bail("%s holds no built sandbox (use --build, or point it at one)" % box)
    tool(box, "start")

    try:
        progs = (("zzqgit", GITP), ("zzqdtmp", DTMP), ("zzqdtmk", DTMMK), ("zzqphn", PHP_NOTIFY),
                 ("zzqphq", PHP_QUIET), ("zzqphd", PHDRIVER), ("zzqspl", SPOOLP), ("zzqcmk", CORMK))
        for nm, text in progs:
            put(sysd, nm, text)
        good = ("zzqgit", "zzqdtmp", "zzqdtmk", "zzqphn", "zzqphq", "zzqphd", "zzqspl", "zzqcmk")
        out = sess(box, "BASIC bp " + " ".join(good))
        row("setup: the probes compile with no errors", "Compiled %d program(s) with no errors" % len(good) in out, out[-600:])

        say("\n--- GIT ---------------------------------------------------------------------------------")
        for state in ("OFF", "ON"):
            out = sess(box, "OPTION GIT " + state, "RUN bp zzqgit")
            path = tag(out, "PATH") or ""
            names = sorted(os.listdir(path)) if path and os.path.isdir(path) else None
            say("    GIT %s: disk %s" % (state, names))
            row("GIT %s: the run reached its end" % state, re.search(r"(?m)^END\s*$", out) is not None, out[-400:])
            if names is None:
                row("GIT %s: the directory file's folder is there" % state, False, repr(path))
                continue
            if state == "OFF":
                row("CONTROL (GIT off): .gitignore and .gitattributes are mapped (%D)", "%Dgitignore" in names and "%Dgitattributes" in names
                    and ".gitignore" not in names, repr(names))
            else:
                row("GIT on: the two git names are on the disk as they are", ".gitignore" in names and ".gitattributes" in names and
                    "%Dgitignore" not in names, repr(names))
            row("GIT %s: any other name with a leading dot is still mapped" % state, "%Dhidden" in names and ".hidden" not in names, repr(names))
            row("GIT %s: all the records read back" % state, tag(out, "READ") == "ignore me|attrs|other", repr(tag(out, "READ")))

        say("\n--- DIR.DTM -----------------------------------------------------------------------------")
        for state in ("OFF", "ON"):
            out = sess(box, "RUN bp zzqdtmk")
            path = tag(out, "PATH") or ""
            if not path or not os.path.isdir(path):
                row("DIR.DTM %s: the directory file's folder is there" % state, False, repr(path))
                continue
            old = time.mktime((2020, 1, 1, 12, 0, 0, 0, 0, -1))
            os.utime(path, (old, old))
            before = os.stat(path).st_mtime
            out = sess(box, "OPTION DIR.DTM " + state, "RUN bp zzqdtmp")
            after = os.stat(path).st_mtime
            say("    DIR.DTM %s: folder mtime %s -> %s" % (state, time.strftime("%Y-%m-%d", time.localtime(before)),
                                                       time.strftime("%Y-%m-%d %H:%M", time.localtime(after))))
            row("DIR.DTM %s: the record was replaced" % state, "WROTE" in out, out[-300:])
            if state == "OFF":
                row("CONTROL (DIR.DTM off): replacing a record does not move the folder's time", after == before, "%s -> %s" % (before, after))
            else:
                row("DIR.DTM on: replacing a record moves the folder's time to now", after > before and abs(after - time.time()) < 300,
                    "%s -> %s" % (before, after))

        say("\n--- NO.PHANTOM.NOTIFY -------------------------------------------------------------------")
        out = sess(box, "RUN bp zzqphd")
        row("the run reached its end", re.search(r"(?m)^END\s*$", out) is not None, out[-400:])
        m1, m2 = tag(out, "MSGS1"), tag(out, "MSGS2")
        say("    messages: ordinary phantom %r; with the option %r" % (m1, m2))
        row("CONTROL: an ordinary phantom tells its parent when it ends", m1 is not None and "Normal termination" in m1, repr(m1))
        row("NO.PHANTOM.NOTIFY: a phantom that sets it sends no message", m2 == "", repr(m2))

        say("\n--- SPOOL.COMMAND -----------------------------------------------------------------------")
        if not restart(box, "SPOOLER=true"):
            row("SPOOL.COMMAND: SD starts with SPOOLER=true", False, "did not start")
        else:
            for state in ("OFF", "ON"):
                out = sess(box, "OPTION SPOOL.COMMAND " + state, "RUN bp zzqspl")
                shown = re.search(r"(?m)^true .*> /dev/null\s*$", out) is not None
                row("SPOOL.COMMAND %s: the run reached its end" % state, re.search(r"(?m)^END\s*$", out) is not None, out[-400:])
                if state == "OFF":
                    row("CONTROL (off): the print command is not shown", not shown, out[-300:])
                else:
                    row("SPOOL.COMMAND on: the command that prints is shown before it runs", shown, out[-400:])
        restart(box)

        say("\n--- the A;NOCASE; flag and CORRELATIVE.REUSE (second sitting; OPTION CORRELATIVE.NOCASE was removed 27 Oct 26) ---------")
        out = sess(box, "RUN bp zzqcmk")
        row("the fixture file was made", "MADE" in out, out[-300:])
        out = sess(box, "LIST zzqcc CASEX NO.PAGE")
        m = re.search(r"(?m)^r1\s+(\S+)\s*$", out)
        got = m.group(1) if m else None
        row("CONTROL: the I-type finds ABC is not abc", got == "diff", repr(out[-300:]))
        out = sess(box, "LIST zzqcc CASEA CASEB NO.PAGE")
        m = re.search(r"(?m)^r1\s+(\S+)\s+(\S+)\s*$", out)
        got = m.groups() if m else None
        say("    A;NOCASE; and A; correlatives: %r" % (got,))
        row("QM4 Fixes 103: a correlative that begins A;NOCASE; finds ABC is abc", got is not None and got[0] == "same", repr(out[-300:]))
        row("CONTROL: the same correlative without NOCASE; finds them different", got is not None and got[1] == "diff", repr(out[-300:]))
        for state in ("OFF", "ON"):
            out = sess(box, "OPTION CORRELATIVE.REUSE " + state, "LIST zzqcc SUMX NO.PAGE")
            nums = [t for ln in out.splitlines() if re.match(r"^(r1\s|\s{8,}\S)", ln) for t in ln.split() if t != "r1"]
            say("    CORRELATIVE.REUSE %s: %r" % (state, nums))
            if state == "OFF":
                row("CONTROL (off): F1 + F2 takes the missing third value of F2 as zero: 11 22 3", nums == ["11", "22", "3"], repr(nums))
            else:
                row("CORRELATIVE.REUSE on: the last value of F2 is used again: 11 22 23", nums == ["11", "22", "23"], repr(nums))
    finally:
        restart(box)
        for nm in set(made):
            for d in ("bp", "bp.out"):
                p = os.path.join(sysd, d, nm)
                if os.path.exists(p):
                    os.remove(p)
        sess(box, "DELETE.CATALOG zzqk", "DELETE.FILE zzqgit", "DELETE.FILE zzqdtm", "DELETE.FILE zzqaa", "DELETE.FILE zzqcc")

    say("\nsandbox-option-q17: %d passed, %d failed" % (passed, failed))
    if passed + failed == 0:
        bail("no row ran - a broken test, not a pass")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
