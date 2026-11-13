#!/usr/bin/env python3
#
# sandbox-file-b8.py - 1.2-0 bundle B-8 (openQM file handling): the mode letters R and N in field 6 of a file's VOC
#                      entry (197, 380), an update lock on the $HOLD record of a mode 3 print unit (53), OPENSEQ on a
#                      block device (112) and the message that names who holds a file (107).  No install, no sudo.
#
#   python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/sandbox-file-b8.py <dir> [--build]
#
# <dir> is a sandbox made by sandbox-fromtree.py (needs a `make`d bin/sd).  With --build it is built first from
# THIS tree (it must be empty or absent).  Exit 0 every row passed, 1 a row failed, 2 it could not run.
#
# START-HISTORY:
# 12 Oct 26 dm  Written for 1.2-0 bundle B-8: sheet 53, 107, 112, 197 and 380.
# END-HISTORY
#
# THE INSTRUMENT.  What a program prints is read back from the session's output, every pattern anchored to the start
# of a line (a session echoes the command it was given).  The lock on a hold record is seen from a SECOND live
# session - bin/sd started on a pipe this script keeps open - that asks for the record while the first is still
# printing.  Sheet 34 (record ids above byte 126) is the owner's to decide and is not tested; the mode letters B C L M
# S X of the manual are not acted on and are not tested.
#
# WHAT THIS CANNOT SAY.  No block device here is readable by an ordinary user, so OPENSEQ on one can only be shown
# not to answer "not a sequential file"; reading a real device is untried, and the row is SKIPPED, not passed, when
# the machine has no block device at all.

import getpass
import os
import re
import stat
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.path.join(HERE, "sandbox-fromtree.py")
ANSI = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]")
passed = failed = skipped = 0
made = []
lives = []

ER_NSEQ = 3013

PROGS = {
    # a file and, in the VOC, copies of its entry with field 6 set; Q-pointers to two of them
    "zzb8mk": ("   execute 'DELETE.FILE zzb8f' capturing j\n   execute 'CREATE.FILE zzb8f' capturing j\n"
               "   open 'voc' to v else stop 'no voc'\n   read r from v, 'zzb8f' else stop 'no entry'\n"
               "   ids = 'zzb8ro':@fm:'zzb8nt':@fm:'zzb8nr':@fm:'zzb8lc':@fm:'zzb8pl'\n"
               "   fl = 'R':@fm:'N':@fm:'NR':@fm:'r':@fm:''\n"
               "   for i = 1 to 5\n      rr = r\n      rr<6> = fl<i>\n      write rr on v, ids<i>\n   next i\n"
               "   write 'Q':@fm:'':@fm:'zzb8ro' on v, 'zzb8qp'\n   write 'Q':@fm:'':@fm:'zzb8nt' on v, 'zzb8qn'\n"
               "   crt 'MK DONE'\nend\n"),
    "zzb8rd": ("$include keys.h\n   ids = 'zzb8f':@fm:'zzb8pl':@fm:'zzb8ro':@fm:'zzb8nt':@fm:'zzb8nr':@fm:'zzb8lc'"
               ":@fm:'zzb8qp':@fm:'zzb8qn'\n"
               "   for i = 1 to 8\n      open ids<i> to f then\n"
               "         crt 'FI ':ids<i>:' RO=':fileinfo(f, FL$READONLY):' NT=':fileinfo(f, FL$NON.TXN)\n"
               "         close f\n      end else crt 'FI ':ids<i>:' OPEN FAILED ':status()\n   next i\n"
               "   crt 'RDDONE'\nend\n"),
    "zzb8wr": ("   open 'zzb8ro' to f else stop 'no ro'\n   open 'zzb8f' to g else stop 'no g'\n"
               "   err = 0\n   readu x from f, 'rec1' else null\n   write 'x' on f, 'rec1' on error err = status()\n"
               "   crt 'WRO[':err:']'\n   release f\n"
               "   read z from g, 'rec1' then crt 'RECRO[present]' else crt 'RECRO[absent]'\n"
               "   err = 0\n   readu x from g, 'rec2' else null\n   write 'y' on g, 'rec2' on error err = status()\n"
               "   crt 'WPL[':err:']'\n   release g\n"
               "   read z from g, 'rec2' then crt 'RECPL[present]' else crt 'RECPL[absent]'\n"
               "   crt 'WRDONE'\nend\n"),
    "zzb8tx": ("$include keys.h\n   open 'zzb8nt' to n else stop 'no n'\n   open 'zzb8pl' to p else stop 'no p'\n"
               "   begin transaction\n      open 'zzb8nt' to n2 else stop 'no n2'\n"
               "      open 'zzb8nr' to n3 else stop 'no n3'\n"
               "      crt 'TXOPEN NT2=':fileinfo(n2, FL$NON.TXN):' NT3=':fileinfo(n3, FL$NON.TXN):' RO3=':fileinfo(n3, FL$READONLY)\n"
               "      write 'n' on n, 'n1'\n      readu x from p, 'p1' else null\n      write 'p' on p, 'p1'\n"
               "   rollback\n   end transaction\n"
               "   read z from n, 'n1' then crt 'N1[present]' else crt 'N1[absent]'\n"
               "   read z from p, 'p1' then crt 'P1[present]' else crt 'P1[absent]'\n   crt 'TXDONE'\nend\n"),
    # 53: A prints in mode 3 to a record of $HOLD and keeps the unit open; B asks for the record
    "zzb8pa": ("   execute 'SETPTR 0,80,60,0,0,3,AS zzb8p,BRIEF'\n   printer on\n"
               "   print 'a line of output'\n   print 'and another'\n   crt 'PA[':@userno:']'\n"
               "   sleep 12\n   printer close\n   crt 'PA CLOSED'\nend\n"),
    "zzb8pb": ("   open '$hold' to h else stop 'no hold'\n   t0 = time()\n"
               "   readu x from h, 'zzb8p' locked crt 'PBL[':status():']' else null\n"
               "   release h\n   crt 'PB TRIED'\n"
               "   readu x from h, 'zzb8p' else null\n   crt 'PBW[':(time() - t0):']'\n   release h\nend\n"),
    "zzb8pc": ("   open '$hold' to h else stop 'no hold'\n"
               "   readu x from h, 'zzb8p' locked crt 'PCL[':status():']' then crt 'PCL[free]'\n   release h\nend\n"),
    # 34: record ids of a directory file with bytes above 126 (owner's yes, 12 Oct 26); control characters and DEL stay refused
    "zzb8id": ("   execute 'DELETE.FILE zzb8d' capturing j\n   execute 'CREATE.FILE zzb8d DIRECTORY' capturing j\n"
               "   open 'zzb8d' to f else stop 'no f'\n"
               "   ids = 'caf':char(233):@fm:'caf':char(195):char(169):@fm:'top':char(247):@fm:'plain'\n"
               "   ids := @fm:'ctl':char(7):@fm:'del':char(127):@fm:'low':char(31)\n"
               "   for i = 1 to dcount(ids, @fm)\n      err = 0\n      ok = 0\n      if i <= 4 then readu x from f, ids<i> else null\n"
               "      write 'rec ':i on f, ids<i> on error err = status()\n      if i <= 4 then release f\n"
               "      if i <= 4 then\n         read back from f, ids<i> then ok = (back = 'rec ':i) else ok = 0\n      end\n"
               "      crt 'ID':i:'[err=':err:' ok=':ok:']'\n   next i\n"
               "   select f to 1\n   n = 0\n   loop\n      readnext k from 1 else exit\n      n += 1\n      if k = ids<1> then seen1 = 1\n"
               "      if k = ids<2> then seen2 = 1\n   repeat\n"
               "   crt 'LISTED[':n:' ':seen1:' ':seen2:']'\n"
               "   crt 'IDDONE'\nend\n"),
    # 107: holds the file open so that another session's CNAME must name the holder
    "zzb8ho": ("   execute 'DELETE.FILE zzb8hf' capturing j\n   execute 'CREATE.FILE zzb8hf' capturing j\n"
               "   open 'zzb8hf' to f else stop 'no f'\n   crt 'HO[':@userno:']'\n   sleep 25\n   crt 'HO DONE'\nend\n"),
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


def skip(name, why):
    global skipped
    skipped += 1
    say("  [SKIP] " + name + "   <- " + why)


def bail(msg):
    for lv in lives:
        lv.kill()
    say("sandbox-file-b8: CANNOT RUN - " + msg)
    sys.exit(2)


def tool(box, *args, **kw):
    return subprocess.run([sys.executable, TOOL, box] + list(args), capture_output=True, text=True, errors="replace",
                          timeout=kw.pop("timeout", 900), **kw)


def sess(box, *cmds):
    say("    > %s" % " | ".join(c if len(c) < 60 else c[:57] + "..." for c in cmds))
    p = subprocess.run([sys.executable, TOOL, box, "sess", os.path.join(box, "user_accounts")] + list(cmds),
                       capture_output=True, text=True, errors="replace", timeout=900)
    return ANSI.sub("", p.stdout + p.stderr).split(":TERM 200,9999", 1)[-1]


class Live:
    """A session on a pipe kept open, so that what it holds stays held while another session looks."""

    def __init__(self, box, tag, cmds):
        self.out = os.path.join(box, "live-%s.out" % tag)
        env = dict(os.environ, SD_CONFIG=os.path.join(box, "sd.conf"))
        self.fh = open(self.out, "w")
        self.p = subprocess.Popen([os.path.join(box, "sys", "bin", "sd")], stdin=subprocess.PIPE, stdout=self.fh,
                                  stderr=subprocess.STDOUT, cwd=os.path.join(box, "user_accounts"), env=env, text=True)
        self.p.stdin.write("\nTERM 200,9999\n" + "".join(c + "\n" for c in cmds) + "OFF\n")
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


def compile_all(box, sysd, progs):
    cmds = []
    for nm, text in progs.items():
        with open(os.path.join(sysd, "bp", nm), "w") as f:
            f.write(text)
        made.append(nm)
        cmds.append("BASIC bp %s" % nm)
    out = sess(box, *cmds)
    n = len(re.findall(r"(?m)^Compiled 1 program\(s\) with no errors", out))
    if n != len(progs):
        bail("%d of %d programs compiled:\n%s" % (n, len(progs), out[-1500:]))


def find_block_device():
    """A block device (readable one first) under /dev, or None."""
    best = None
    for dirpath, dirs, files in os.walk("/dev"):
        for nm in files:
            p = os.path.join(dirpath, nm)
            try:
                if stat.S_ISBLK(os.stat(p).st_mode):
                    if os.access(p, os.R_OK):
                        return p, True
                    best = best or p
            except OSError:
                pass
        dirs[:] = [d for d in dirs if d in ("disk", "mapper")]
    return (best, False) if best else (None, False)


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) != 1:
        bail("usage: sandbox-file-b8.py <dir> [--build]")
    box = os.path.abspath(args[0])
    sysd = os.path.join(box, "sys")
    say("sandbox-file-b8: sandbox %s" % box)
    if "--build" in sys.argv:
        if os.path.exists(box) and os.listdir(box):
            bail("%s is not empty" % box)
        r = tool(box, "all")
        if "[FAIL]" in r.stdout or r.returncode != 0 or "[PASS] THIRD.COMPILE" not in r.stdout:
            bail("the sandbox build did not pass:\n" + r.stdout[-800:])
        say("sandbox-file-b8: built, bootstrap passed")
    elif not os.path.isfile(os.path.join(sysd, "bin", "sd")):
        bail("%s holds no built sandbox (use --build, or point it at one)" % box)

    # 112: the OPENSEQ programs are made here, one per path, because the path is part of the source
    dev, readable = find_block_device()
    progs = dict(PROGS)
    seq = {"zzb8s1": "/dev", "zzb8s2": "/dev/null"}
    if dev:
        seq["zzb8s3"] = dev
    for nm, path in seq.items():
        progs[nm] = ("$include keys.h\n   openseq '%s' to f then\n      crt 'OS[ok][':fileinfo(f, FL$SEQTYPE):']'\n"
                     "      close f\n   end else crt 'OS[':status():']'\nend\n" % path)

    try:
        tool(box, "start", timeout=180)
        compile_all(box, sysd, progs)

        say("\n--- 197 and 380 the mode letters in field 6 of a VOC entry -------------------------")
        out = sess(box, "RUN bp zzb8mk")
        row("the fixture: a file and VOC entries with field 6 R, N, NR, r, nothing, and two Q-pointers",
            re.search(r"(?m)^MK DONE\s*$", out) is not None, out[-300:])
        out = sess(box, "RUN bp zzb8rd")
        fi = dict((m.group(1), (m.group(2), m.group(3))) for m in
                  re.finditer(r"(?m)^FI (\w+) RO=(\d+) NT=(\d+)\s*$", out))
        say("    opened: %s" % fi)
        want = [("zzb8f", "0", "0", "the file by its own entry"), ("zzb8pl", "0", "0", "CONTROL: a copy of the entry with field 6 empty"),
                ("zzb8ro", "1", "0", "197: field 6 R opens read-only"), ("zzb8nt", "0", "1", "380: field 6 N opens non-transactional"),
                ("zzb8nr", "1", "1", "field 6 NR does both"), ("zzb8lc", "1", "0", "a lower case r is taken as R"),
                ("zzb8qp", "1", "0", "a Q-pointer to the R entry opens read-only"),
                ("zzb8qn", "0", "1", "a Q-pointer to the N entry opens non-transactional")]
        for nm, ro, nt, why in want:
            row("%s (%s: READONLY=%s NON.TXN=%s)" % (why, nm, ro, nt), fi.get(nm) == (ro, nt), "got %s" % (fi.get(nm),))
        out = sess(box, "RUN bp zzb8wr")
        err = tagged(out, "WRO")
        row("197: a write through the R open fails (status %s, not 0)" % err, err not in (None, "0", ""), "got %r" % err)
        row("197: ... and the record is not there when read through the plain open",
            re.search(r"(?m)^RECRO\[absent\]\s*$", out) is not None, out[-300:])
        row("197: CONTROL: the same write through a plain open succeeds and the record is there",
            tagged(out, "WPL") == "0" and re.search(r"(?m)^RECPL\[present\]\s*$", out) is not None, out[-300:])
        out = sess(box, "RUN bp zzb8tx")
        row("380: opened again inside a transaction the N letter is still honoured, and so is NR's R",
            re.search(r"(?m)^TXOPEN NT2=1 NT3=1 RO3=1\s*$", out) is not None, out[-300:])
        row("380: after ROLLBACK a write to the N file survives", re.search(r"(?m)^N1\[present\]\s*$", out) is not None, out[-300:])
        row("380: CONTROL: ... and a write to the plain file does not",
            re.search(r"(?m)^P1\[absent\]\s*$", out) is not None, out[-300:])

        say("\n--- 53 a mode 3 print unit locks its record in $HOLD -------------------------------")
        a = Live(box, "a", ["RUN bp zzb8pa"])
        time.sleep(5)
        b = Live(box, "b", ["RUN bp zzb8pb"])
        b.wait(40)
        a.wait(40)
        at, bt = a.text(), b.text()
        ua = tagged(at, "PA")
        locked = tagged(bt, "PBL")
        say("    A is user %s; B was told the lock is held by %r and waited %r s" % (ua, locked, tagged(bt, "PBW")))
        row("53: A printed to $HOLD and closed the unit", ua is not None and re.search(r"(?m)^PA CLOSED\s*$", at), at[-200:])
        row("53: while A was printing, B's READU ... LOCKED found the record locked, by A", ua is not None and locked == ua,
            "got %r, A is %r" % (locked, ua))
        waited = tagged(bt, "PBW")
        row("53: B's plain READU waited until A closed the unit (at least 3 seconds)",
            waited is not None and waited.isdigit() and int(waited) >= 3, "waited %r" % waited)
        out = sess(box, "RUN bp zzb8pc")
        row("53: CONTROL: once the unit is closed the record is free", tagged(out, "PCL") == "free", out[-200:])

        say("\n--- 112 OPENSEQ on a block device -------------------------------------------------")
        out = sess(box, "RUN bp zzb8s1")
        row("112: CONTROL: OPENSEQ of a directory (/dev) still answers 'not a sequential file' (%d)" % ER_NSEQ,
            tagged(out, "OS") == str(ER_NSEQ), "got %r" % tagged(out, "OS"))
        out = sess(box, "RUN bp zzb8s2")
        row("112: CONTROL: OPENSEQ of a character device (/dev/null) opens", re.search(r"(?m)^OS\[ok\]\[2\]\s*$", out) is not None,
            out[-200:])
        if dev:
            out = sess(box, "RUN bp zzb8s3")
            if readable:
                row("112: OPENSEQ of the block device %s opens, FILEINFO(FL$SEQTYPE) is 4" % dev,
                    re.search(r"(?m)^OS\[ok\]\[4\]\s*$", out) is not None, out[-200:])
            else:
                row("112: OPENSEQ of %s (not readable by this user) is not answered with 'not a sequential file'" % dev,
                    tagged(out, "OS") not in (None, str(ER_NSEQ)), "got %r" % tagged(out, "OS"))
                say("    (reading a real block device stays untried on this machine)")
        else:
            skip("112: OPENSEQ of a block device", "this machine has no block device under /dev")

        say("\n--- 34 bytes above 126 in a directory file's record ids (the owner's yes) -----------")
        out = sess(box, "RUN bp zzb8id")
        m = dict((int(a), (b, c)) for a, b, c in re.findall(r"(?m)^ID(\d+)\[err=(\w+) ok=(\w+)\]\s*$", out))
        say("    results: %s" % m)
        row("34: an id with byte 233 is written and read back", m.get(1) == ("0", "1"), "got %s" % (m.get(1),))
        row("34: ... so is one with the two bytes of UTF-8 e-acute (195 169)", m.get(2) == ("0", "1"), "got %s" % (m.get(2),))
        row("34: ... and one ending in byte 247 (the marks, 248 to 255, are not ordinary characters)", m.get(3) == ("0", "1"), "got %s" % (m.get(3),))
        row("34: CONTROL: a plain id still works", m.get(4) == ("0", "1"), "got %s" % (m.get(4),))
        row("34: CONTROL: ids holding byte 7, 127 or 31 are still refused and not stored",
            all(m.get(i, ("0", "1"))[0] != "0" and m.get(i, ("0", "1"))[1] != "1" for i in (5, 6, 7)) and all(i in m for i in (5, 6, 7)),
            "got %s" % ([m.get(i) for i in (5, 6, 7)],))
        row("34: the file lists the extended ids back (4 stored, both spellings seen)",
            re.search(r"(?m)^LISTED\[4 1 1\]\s*$", out) is not None, out[-200:])

        say("\n--- 107 a command that needs exclusive access names who holds the file --------------")
        h = Live(box, "ho", ["RUN bp zzb8ho"])
        time.sleep(4)
        who = tagged(h.text(), "HO")
        out = sess(box, "CNAME zzb8hf TO zzb8hg")
        say("    holder is user %s" % who)
        reply = out.split(":CNAME zzb8hf TO zzb8hg\n", 1)[-1]       # after the echo of the command
        say("    reply: %r" % reply[:300])
        row("107: CNAME of a file another session holds open stops, and says the holder's user number",
            who is not None and "renamed to" not in reply and re.search(r"(?m)^(?!:).*\b%s\b" % re.escape(who), reply) is not None,
            reply[:300])
        h.wait(40)
        out = sess(box, "CNAME zzb8hf TO zzb8hg")
        row("107: CONTROL: once the holder has gone the same CNAME goes through",
            re.search(r"(?m)^'zzb8hf' renamed to 'zzb8hg'\s*$", out) is not None, out[-300:])
    finally:
        for lv in lives:
            lv.kill()
        tool(box, "stop", timeout=120)
        for nm in made:
            for d in ("bp", "bp.out"):
                pth = os.path.join(sysd, d, nm)
                if os.path.exists(pth):
                    os.remove(pth)

    say("\nsandbox-file-b8: %d passed, %d failed%s" % (passed, failed, (", %d skipped" % skipped) if skipped else ""))
    sys.exit(0 if failed == 0 else 1)


if __name__ == "__main__":
    main()
