#!/usr/bin/env python3
#
# sandbox-tools.py - the stand-alone file tools sdidx and sdfix, run on scratch copies of a real indexed hashed file.
#                    No install, no sudo.
#
#   python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/sandbox-tools.py <dir> [--build]
#
# <dir> is a sandbox made by sandbox-fromtree.py.  With --build it is built first from THIS tree (it must be empty or
# absent); without it <dir> must already be built, which is how the same script is run against an OLD tree to prove it
# can fail.  The tools run are the sandbox's own (<dir>/sys/bin/sdidx and sdfix): they carry the sandbox's shared memory
# keys, which the open-file rows need.  Exit 0 every row passed, 1 a row failed, 2 it could not run.
#
# START-HISTORY:
# 18 Oct 26 dm  Written for the defects the docs workflow (wf_ad1ef05f-db5) found by running the tools (open-defects-18oct
#               items 7 and 8; Administrator pages 14, 14a, 15): sdidx -m / -d deleted the old local index files through a
#               33-byte buffer, answering n to -d still cleared the header, -m deleted the whole old directory, -p
#               said nothing; sdfix -F could not delete a local index subfile, repaired the split and merge loads to
#               values its own check rejects, -Q looped for ever when its input ended, the interactive W command read
#               decimal against its hex help, -R with -F or -Q fixed nothing, and it did not look for a file open in SD.
# 18 Oct 26 dm  Rows V1-V13 (verifier_rows): a data path of 252 characters (-F deleted the overflow subfile and the index),
#               interactive mode whose input fails rather than ends, junk after the W address, an unreadable index file
#               repaired twice, the exit status over several files, and a relative index path stored as typed.  Each was
#               red on the tree before (10 of the 13; V1, V6 and V7 are controls).
# END-HISTORY
#
# WHAT IT MEASURES.  A hashed file with 40 records and one D-type index (CITY) is made INSIDE the sandbox by SD itself,
# so the header, the index and the free chain are the real thing.  Every row copies that file's directory (cp -a) to a
# scratch place under <dir>/work and runs a tool on the COPY; the original is touched only by the rows about a file that
# a live session holds open, and those only read.  The disk is the evidence: each row lists the directory it judged, and
# the header fields are read from the %0 bytes at the offsets sdfix's own H command prints, not from what a tool said.
#
# THE NULL CASES.  The copies sit under a path longer than 32 characters (the fault needs it) and the suite refuses to
# run if they do not; a CONTROL row repeats the move on a short path, where the old code was right.  Every prompt row
# gives the tool a stdin that ends, or an answer, never the harness's own stdin.

import hashlib
import os
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.path.join(HERE, "sandbox-fromtree.py")
ANSI = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]")
RUN = "%05d" % (os.getpid() % 100000)
F = "zzt" + RUN
HOLD = "zzth" + RUN
passed = failed = 0
BOX = SYSD = BIN = WORK = CONF = FIX = ""
shorts = []


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
    say("sandbox-tools: CANNOT RUN - " + msg)
    sys.exit(2)


def sess(*cmds):
    say("    > " + " | ".join(cmds))
    p = subprocess.run([sys.executable, TOOL, BOX, "sess", os.path.join(BOX, "user_accounts")] + list(cmds),
                       capture_output=True, text=True, errors="replace", timeout=900)
    return ANSI.sub("", p.stdout + p.stderr).split(":TERM 200,9999", 1)[-1]


def tool(name, *args, stdin="", timeout=20, stdin_dir=False):
    """Run the sandbox's tool.  Returns (status, text, timed_out).  stdin is ALWAYS a pipe: '' means input that ends.
    stdin_dir=True makes it a DIRECTORY instead: read() on it fails (EISDIR), which is not the end of input."""
    cmd = [os.path.join(BIN, name)] + list(args)
    if stdin_dir:
        say("    $ (stdin is a directory) " + " ".join(cmd).replace(BOX, "<box>"))
    else:
        say("    $ " + (("printf %r | " % stdin) if stdin else "(stdin ends) ") + " ".join(cmd).replace(BOX, "<box>"))
    env = dict(os.environ, SD_CONFIG=CONF)
    dfd = os.open("/", os.O_RDONLY) if stdin_dir else None
    try:
        if stdin_dir:
            p = subprocess.run(cmd, stdin=dfd, capture_output=True, text=True, errors="replace", env=env, cwd=WORK,
                               timeout=timeout)
        else:
            p = subprocess.run(cmd, input=stdin, capture_output=True, text=True, errors="replace", env=env, cwd=WORK,
                               timeout=timeout)
        return p.returncode, ANSI.sub("", p.stdout + p.stderr), False
    except subprocess.TimeoutExpired as e:
        out = e.stdout or b""
        out = out.decode("utf-8", "replace") if isinstance(out, bytes) else out
        return None, ANSI.sub("", out), True
    finally:
        if dfd is not None:
            os.close(dfd)


def fresh_long(name, length):
    """Copy the fixture to a data directory whose path is exactly LENGTH characters (components of 100 or fewer)."""
    top = os.path.join(WORK, name)
    if os.path.exists(top):
        shutil.rmtree(top)
    os.makedirs(top)
    need = length - len(top) - 1
    comps = []
    while need > 0:
        n = min(need, 100)
        if need - n == 1:
            n -= 1
        comps.append("d" * n)
        need -= n + 1
    dst = top + "/" + "/".join(comps)
    if len(dst) != length:
        bail("could not make a path of %d characters (made %d)" % (length, len(dst)))
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    shutil.copytree(FIX, dst, symlinks=True)
    return dst


def fresh(name, where=None):
    """Copy the fixture's directory to <where or WORK>/<name>/f and return that path (the data file's directory)."""
    top = os.path.join(where or WORK, name)
    if os.path.exists(top):
        shutil.rmtree(top)
    os.makedirs(top)
    dst = os.path.join(top, "f")
    shutil.copytree(FIX, dst, symlinks=True)
    return dst


def ls(d):
    try:
        return sorted(os.listdir(d))
    except OSError:
        return None


def blob(d):
    """The bytes of every subfile of a data directory, for 'nothing was written'."""
    out = {}
    for n in ls(d) or []:
        with open(os.path.join(d, n), "rb") as fh:
            out[n] = fh.read()
    return out


def q(data):
    return tool("sdidx", "-q", data)[1]


def header_offsets(data):
    """{label: hex offset text} from sdfix's interactive H command (needs DEBUG bit 2 in the config)."""
    rc, out, to = tool("sdfix", "-I", data, stdin="H\nq\n")
    d = {}
    for m in re.finditer(r"(?m)^([0-9A-Fa-f]{4}): ([A-Za-z][A-Za-z ]*?)\s{2,}", out):
        d[m.group(2).strip()] = m.group(1)
    return d


def hdr_int16(data, off_hex):
    with open(os.path.join(data, "%0"), "rb") as fh:
        fh.seek(int(off_hex, 16))
        return struct.unpack("<h", fh.read(2))[0]


def set_int16(data, off_hex, value):
    with open(os.path.join(data, "%0"), "r+b") as fh:
        fh.seek(int(off_hex, 16))
        fh.write(struct.pack("<h", value))


def bytes_at(data, off_hex, n):
    with open(os.path.join(data, "%0"), "rb") as fh:
        fh.seek(int(off_hex, 16))
        return fh.read(n)


def sdfix_lines(out, *words):
    return [w for w in words if w in out]


# --------------------------------------------------------------------------------------------------------------------
PROG_FILL = """   open '%s' to f else stop 'no file'
   open 'DICT %s' to d else stop 'no dict'
   write 'D':@fm:'1':@fm:'':@fm:'City':@fm:'12L':@fm:'S' on d, 'CITY'
   for i = 1 to 40
      write 'City':mod(i,5) on f, 'r':i
   next i
end
""" % (F, F)

PROG_HOLD = """   open '%s' to f else stop 'no file'
   crt 'HELD'
   input x
   crt 'RELEASED'
end
""" % F


class Live:
    """A session on a pipe kept open: it opens the fixture, says HELD and waits for a line."""

    def __init__(self):
        self.out = os.path.join(BOX, "live-hold.out")
        env = dict(os.environ, SD_CONFIG=CONF)
        self.fh = open(self.out, "w")
        self.p = subprocess.Popen([os.path.join(SYSD, "bin", "sd")], stdin=subprocess.PIPE, stdout=self.fh,
                                  stderr=subprocess.STDOUT, cwd=os.path.join(BOX, "user_accounts"), env=env, text=True)
        self.p.stdin.write("\nTERM 200,9999\nRUN bp %s\n" % HOLD)
        self.p.stdin.flush()
        say("    > live session: RUN bp %s (opens %s, waits for a line)" % (HOLD, F))

    def text(self):
        try:
            self.fh.flush()
        except ValueError:
            pass
        with open(self.out, errors="replace") as fh:
            return ANSI.sub("", fh.read())

    def wait_for(self, word, seconds=30):
        end = time.time() + seconds
        while time.time() < end:
            if re.search(r"(?m)^" + word + r"\s*$", self.text()):
                return True
            time.sleep(0.3)
        return False

    def release(self):
        try:
            self.p.stdin.write("\nOFF\n")
            self.p.stdin.flush()
            self.p.stdin.close()
        except (OSError, ValueError):
            pass
        try:
            self.p.wait(timeout=30)
        except subprocess.TimeoutExpired:
            self.p.kill()
            self.p.wait()
        self.fh.close()

    def kill(self):
        if self.p.poll() is None:
            self.p.kill()
            self.p.wait()
        try:
            self.fh.close()
        except OSError:
            pass


# --------------------------------------------------------------------------------------------------------------------
def sdidx_rows():
    say("\n=== sdidx ================================================================================================")
    d = fresh("i-local")
    say("    data directory %s (%d characters, so '/%%2' after it is %d: over the old 33-byte buffer)" % (d, len(d), len(d) + 3))
    if len(d) + 3 <= 32:
        bail("the scratch path is not longer than 32 characters; the long-path rows would prove nothing")
    row("I0 (control): the fixture holds %0 %1 %2 and sdidx -q says the indices are not relocated",
        ls(d) == ["%0", "%1", "%2"] and "Indices are not relocated" in q(d), repr(ls(d)))

    say("\n--- -m from local to elsewhere, long path ---------------------------------------------------------------")
    x = os.path.join(WORK, "i-local", "idx")
    say("    BEFORE %r" % ls(d))
    rc, out, to = tool("sdidx", "-m", d, x)
    say("    AFTER  data %r   target %r" % (ls(d), ls(x)))
    row("I1 -m moves the indices: reports it, status 0", rc == 0 and "Indices have been moved" in out, "%r %r" % (rc, out[-200:]))
    row("I2 ... and the old %2 is GONE from the data directory", ls(d) == ["%0", "%1"], repr(ls(d)))
    row("I3 ... and the new directory holds the %2 and -q names it",
        ls(x) == ["%2"] and ("Index directory is " + x) in q(d), "%r %r" % (ls(x), q(d)[-120:]))
    say("\n--- ... and back --------------------------------------------------------------------------------------")
    rc, out, to = tool("sdidx", "-m", d)
    say("    AFTER  data %r   old target %r" % (ls(d), ls(x)))
    row("I4 -m with no path moves the indices back (a stale %2 made it fail: error 17)",
        rc == 0 and "Indices have been moved" in out and ls(d) == ["%0", "%1", "%2"], "%r %r %r" % (rc, out[-200:], ls(d)))
    row("I5 ... and the emptied index directory is gone", ls(x) is None, repr(ls(x)))

    say("\n--- -d local, long path -------------------------------------------------------------------------------")
    d = fresh("i-dlocal")
    say("    BEFORE %r" % ls(d))
    rc, out, to = tool("sdidx", "-d", d)
    say("    AFTER  %r" % ls(d))
    row("I6 -d on local indices: reports it, status 0", rc == 0 and "All indices deleted" in out, "%r %r" % (rc, out[-200:]))
    row("I7 ... the %2 is GONE and -q says the file has no indices",
        ls(d) == ["%0", "%1"] and "File has no indices" in q(d), "%r %r" % (ls(d), q(d)[-120:]))

    say("\n--- CONTROL: the same move on a SHORT path, where the 33-byte buffer was enough --------------------------")
    sdir = tempfile.mkdtemp(prefix="sdt", dir="/tmp")
    shorts.append(sdir)
    sd_ = fresh("s", sdir)
    sx = os.path.join(sdir, "i")
    say("    short data directory %s (%d characters)" % (sd_, len(sd_)))
    if len(sd_) + 3 > 32:
        bail("the 'short' path is not short")
    rc, out, to = tool("sdidx", "-m", sd_, sx)
    row("I8 (control) short path: -m moves and the old %2 is gone", rc == 0 and ls(sd_) == ["%0", "%1"] and ls(sx) == ["%2"],
        "%r %r %r" % (rc, ls(sd_), ls(sx)))

    say("\n--- -d on relocated indices, the answer n, and input that ends ------------------------------------------")
    d = fresh("i-dn")
    x = os.path.join(WORK, "i-dn", "idx")
    tool("sdidx", "-m", d, x)
    row("I9 setup: the indices are relocated to %s" % x, ("Index directory is " + x) in q(d) and ls(x) == ["%2"], q(d)[-150:])
    before = blob(d)
    rc, out, to = tool("sdidx", "-d", d, stdin="n\n")
    say("    AFTER  data %r   index dir %r" % (ls(d), ls(x)))
    row("I10 answering n: the header is NOT touched and the index directory is still there",
        blob(d) == before and ls(x) == ["%2"] and ("Index directory is " + x) in q(d), "%r %r" % (ls(x), q(d)[-150:]))
    row("I11 ... and it does not say that the indices were deleted", "All indices deleted" not in out, out[-200:])
    d = fresh("i-deof")
    x = os.path.join(WORK, "i-deof", "idx")
    tool("sdidx", "-m", d, x)
    before = blob(d)
    rc, out, to = tool("sdidx", "-d", d, stdin="", timeout=8)
    row("I12 input that ends at the question: the program ends and says so (it read a stale answer or looped for ever)",
        not to and "End of input" in out, "timed out: %r; %r" % (to, out[-200:]))
    row("I13 ... and it deletes nothing, the header included", blob(d) == before and ls(x) == ["%2"], "%r" % ls(x))
    d = fresh("i-dn2")
    x = os.path.join(WORK, "i-dn2", "idx")
    tool("sdidx", "-m", d, x)
    rc, out, to = tool("sdidx", "-d", d, stdin="y\n")
    say("    AFTER  data %r   index dir %r" % (ls(d), ls(x)))
    row("I14 answering y: the indices are deleted, the header cleared, the emptied directory removed",
        rc == 0 and "All indices deleted" in out and ls(x) is None and "File has no indices" in q(d), "%r %r %r" % (rc, ls(x), out[-150:]))

    say("\n--- -d and -m must remove only the index files, not whatever else is in the directory ---------------------")
    d = fresh("i-dnote")
    x = os.path.join(WORK, "i-dnote", "idx")
    tool("sdidx", "-m", d, x)
    note = os.path.join(x, "note-from-admin")
    with open(note, "w") as fh:
        fh.write("keep me\n")
    rc, out, to = tool("sdidx", "-d", d, stdin="y\n")
    say("    AFTER  index dir %r" % ls(x))
    row("I15 -d (answer y): the indices go, the administrator's note and its directory stay",
        ls(x) == ["note-from-admin"] and "File has no indices" in q(d), repr(ls(x)))

    d = fresh("i-mnote")
    x = os.path.join(WORK, "i-mnote", "idx")
    y = os.path.join(WORK, "i-mnote", "idy")
    tool("sdidx", "-m", d, x)
    note = os.path.join(x, "note-from-admin")
    with open(note, "w") as fh:
        fh.write("keep me\n")
    rc, out, to = tool("sdidx", "-m", d, y)
    say("    AFTER  old dir %r   new dir %r" % (ls(x), ls(y)))
    row("I16 -m from a relocated place: the note in the old directory is still there",
        os.path.exists(note) and ls(x) == ["note-from-admin"], repr(ls(x)))
    row("I17 ... the move itself is done (%2 in the new directory, -q names it, status 0)",
        rc == 0 and "Indices have been moved" in out and ls(y) == ["%2"] and ("Index directory is " + y) in q(d),
        "%r %r %r" % (rc, ls(y), out[-150:]))
    d = fresh("i-mclean")
    x = os.path.join(WORK, "i-mclean", "idx")
    y = os.path.join(WORK, "i-mclean", "idy")
    tool("sdidx", "-m", d, x)
    rc, out, to = tool("sdidx", "-m", d, y)
    row("I18 (control) -m from a relocated place with nothing else in it: the old directory is removed",
        rc == 0 and ls(x) is None and ls(y) == ["%2"], "%r %r %r" % (rc, ls(x), ls(y)))
    d = fresh("i-mnest")
    x = os.path.join(WORK, "i-mnest", "idx")
    y = os.path.join(x, "sub")
    tool("sdidx", "-m", d, x)
    rc, out, to = tool("sdidx", "-m", d, y)
    say("    AFTER  old dir %r   new dir (inside it) %r" % (ls(x), ls(y)))
    row("I19 -m to a directory INSIDE the old one: the new copy survives and -q names it",
        rc == 0 and ls(y) == ["%2"] and ("Index directory is " + y) in q(d), "%r %r %r" % (rc, ls(y), q(d)[-150:]))

    say("\n--- -p ---------------------------------------------------------------------------------------------------")
    d = fresh("i-p")
    z = os.path.join(WORK, "i-p", "byhand")
    os.makedirs(z)
    shutil.move(os.path.join(d, "%2"), os.path.join(z, "%2"))
    rc, out, to = tool("sdidx", "-p", d, z)
    row("I20 -p says what it did (the same words -q gives), status 0", rc == 0 and ("Index directory is " + z) in out, "%r %r" % (rc, out[-200:]))
    row("I21 ... and -q agrees", ("Index directory is " + z) in q(d), q(d)[-150:])
    shutil.move(os.path.join(z, "%2"), os.path.join(d, "%2"))
    rc, out, to = tool("sdidx", "-p", d)
    row("I22 -p with no path: says the indices are not relocated, status 0", rc == 0 and "Indices are not relocated" in out, "%r %r" % (rc, out[-200:]))
    rc, out, to = tool("sdidx", "-p", d, os.path.join(WORK, "i-p", "nosuch"))
    row("I23 (control) -p to a directory that is not there is refused, status 1", rc == 1 and "does not exist" in out, "%r %r" % (rc, out[-200:]))

    say("\n--- an argument longer than the header can hold ------------------------------------------------------------")
    d = fresh("i-long")
    long_path = "/tmp/" + "p" * 300
    before = blob(d)
    rc, out, to = tool("sdidx", "-m", d, long_path)
    row("I24 -m with a 305 character path: refused with a message, status 1, nothing changed",
        rc == 1 and "too long" in out and blob(d) == before, "%r %r" % (rc, out[-200:]))
    rc, out, to = tool("sdidx", "-p", d, long_path)
    row("I25 -p with a 305 character path: refused with a message, status 1, nothing changed",
        rc == 1 and "too long" in out and blob(d) == before, "%r %r" % (rc, out[-200:]))


# --------------------------------------------------------------------------------------------------------------------
def make_conf(debug):
    path = os.path.join(WORK, "debug2.conf" if debug else "plain.conf")
    with open(os.path.join(BOX, "sd.conf")) as fh:
        text = fh.read()
    if debug:
        text = text.replace("[sd]\n", "[sd]\nDEBUG=2\n", 1)
        if "DEBUG=2" not in text:
            bail("could not put DEBUG=2 in the sandbox's sd.conf copy")
    with open(path, "w") as fh:
        fh.write(text)
    return path


def sdfix_rows():
    global CONF
    say("\n=== sdfix ================================================================================================")
    plain = CONF
    debug_conf = make_conf(True)

    d = fresh("f-clean")
    rc, out, to = tool("sdfix", "-B", d)
    row("F0 (control) a check of the untouched copy ends Status: 0 and reports no error",
        rc == 0 and "Status: 0" in out and "Checking free chain" in out and not re.search(r"(?i)invalid|error|unexpected|not found", out),
        out[-300:])
    CONF = debug_conf
    offs = header_offsets(d)
    CONF = plain
    say("    header offsets from H: %r" % offs)
    for k in ("Split load", "Merge load", "Trigger name", "AK path"):
        if k not in offs:
            bail("sdfix -I / H did not print the offset of '%s' (is DEBUG=2 in the config it read?):\n%s" % (k, repr(offs)))
    sl, ml = offs["Split load"], offs["Merge load"]
    default = (hdr_int16(d, sl), hdr_int16(d, ml))
    row("F1 (control) a file SD made has the default loads, split 80 merge 50 (dh_int.h)", default == (80, 50), repr(default))

    say("\n--- -F and a local index subfile ---------------------------------------------------------------------")
    d = fresh("f-stray")
    saved = open(os.path.join(d, "%2"), "rb").read()
    tool("sdidx", "-d", d)
    with open(os.path.join(d, "%2"), "wb") as fh:
        fh.write(saved)
    say("    stray index file put back: %r (the header lists no index)" % ls(d))
    rc, out, to = tool("sdfix", "-B", d)
    row("F2 (control) a check reports the stray %2", "AK0 subfile found but not expected" in out, out[-300:])
    rc, out, to = tool("sdfix", "-B", "-F", d)
    say("    AFTER -F  %r" % ls(d))
    row("F3 -F says it deleted the stray index subfile", "Corrected by deleting affected AK index subfile" in out, out[-300:])
    row("F4 ... and the %2 is really GONE", ls(d) == ["%0", "%1"], repr(ls(d)))
    rc, out, to = tool("sdfix", "-B", d)
    row("F5 ... so the next check is clean", rc == 0 and "AK0" not in out and "Status: 0" in out, out[-300:])

    d = fresh("f-magic")
    with open(os.path.join(d, "%2"), "r+b") as fh:
        fh.write(b"\x00\x00")
    rc, out, to = tool("sdfix", "-B", "-F", d)
    say("    AFTER -F  %r" % ls(d))
    row("F6 an index file with a bad magic number: -F says it is deleted", "has incorrect magic number" in out and "Corrected by deleting" in out, out[-300:])
    row("F7 ... the %2 is GONE and the file lists no index", ls(d) == ["%0", "%1"] and "File has no indices" in q(d), "%r %r" % (ls(d), q(d)[-100:]))

    say("\n--- the split and merge loads --------------------------------------------------------------------------")
    for tag, bad in (("inverted", (50, 80)), ("equal", (60, 60)), ("zero-split", (0, 50))):
        d = fresh("f-load-" + tag)
        set_int16(d, sl, bad[0])
        set_int16(d, ml, bad[1])
        rc, out, to = tool("sdfix", "-B", d)
        row("F8 %s: the check reports the loads (%d, %d)" % (tag, bad[0], bad[1]),
            ("Invalid split and/or merge loads (%d, %d)" % bad) in out, out[-300:])
        row("F9 %s: a check alone writes nothing" % tag, (hdr_int16(d, sl), hdr_int16(d, ml)) == bad, repr((hdr_int16(d, sl), hdr_int16(d, ml))))
        rc, out, to = tool("sdfix", "-B", "-F", d)
        after = (hdr_int16(d, sl), hdr_int16(d, ml))
        say("    header split/merge: %r -> %r" % (bad, after))
        row("F10 %s: -F writes the defaults SD gives a new file, (80, 50)" % tag, after == (80, 50), repr(after))
        rc, out, to = tool("sdfix", "-B", d)
        row("F11 %s: the next check accepts what -F wrote" % tag, "Invalid split" not in out and "Status: 0" in out, out[-300:])
    d = fresh("f-load-msg")
    set_int16(d, sl, 50)
    set_int16(d, ml, 80)
    rc, out, to = tool("sdfix", "-B", "-F", d)
    row("F12 the message names the values it wrote", "(80, 50)" in out and "(50, 80)" not in out.split("Corrected")[-1], out[-300:])

    say("\n--- input that ends ----------------------------------------------------------------------------------------")
    d = fresh("f-eof")
    set_int16(d, sl, 50)
    set_int16(d, ml, 80)
    before = blob(d)
    rc, out, to = tool("sdfix", "-B", "-Q", d, stdin="", timeout=8)
    row("F13 -Q whose input ends at Fix?: the program ends (it looped for ever)", not to, "still running after 8 seconds; output so far: " + out[-200:])
    row("F14 ... it asked, took the end of input as no, and wrote nothing", "Fix?" in out and blob(d) == before, out[-300:])
    row("F15 ... and says that the input ended", "end of input" in out.lower(), out[-300:])
    rc, out, to = tool("sdfix", "-B", "-Q", d, stdin="Y", timeout=8)
    row("F16 (control) -Q answered Y repairs it", (hdr_int16(d, sl), hdr_int16(d, ml)) == (80, 50), repr((hdr_int16(d, sl), hdr_int16(d, ml))))
    d = fresh("f-n")
    set_int16(d, sl, 50)
    set_int16(d, ml, 80)
    before = blob(d)
    rc, out, to = tool("sdfix", "-B", "-Q", d, stdin="N", timeout=8)
    row("F17 (control) -Q answered N repairs nothing", blob(d) == before and not to, out[-300:])
    CONF = debug_conf
    rc, out, to = tool("sdfix", "-I", d, stdin="", timeout=8)
    CONF = plain
    row("F18 interactive mode whose input ends: the program ends and says so (it prompted for ever)",
        not to and "End of input" in out and "Status: 0" in out, "timed out: %r; %r" % (to, out[-200:]))

    say("\n--- the interactive W command: hex address, hex data, written as typed -------------------------------------")
    d = fresh("f-w")
    t = offs["Trigger name"]
    base = int(t, 16)
    # sdfix prints header offsets in hex, so the same text is the W address
    cmds = "W%s=41\nW%X=4243\nW%X=44454647\nq\n" % (t, base + 1, base + 3)
    CONF = debug_conf
    rc, out, to = tool("sdfix", "-I", d, stdin=cmds, timeout=15)
    CONF = plain
    got = bytes_at(d, t, 7)
    say("    asked: W%s=41, W%X=4243, W%X=44454647   file now has %s from %s" % (t, base + 1, base + 3, got.hex(), t))
    row("F19 W with 2, 4 and 8 hex digits writes 1, 2 and 4 bytes in the order typed, at the hex address",
        got == bytes([0x41, 0x42, 0x43, 0x44, 0x45, 0x46, 0x47]), got.hex())
    d = fresh("f-wb")
    CONF = debug_conf
    rc, out, to = tool("sdfix", "-I", d, stdin="W%s=41\nW%s=4a\nq\n" % (t, t), timeout=15)
    CONF = plain
    row("F19b W with a hex letter in the value writes it, and 'Was' shows the bytes that were there",
        bytes_at(d, t, 1) == b"\x4a" and "Was 00" in out and "Was 41" in out, "%s %r" % (bytes_at(d, t, 1).hex(), out[-200:]))
    d = fresh("f-w2")
    cmds = "W%s=\"hi\"\nq\n" % t
    CONF = debug_conf
    rc, out, to = tool("sdfix", "-I", d, stdin=cmds, timeout=15)
    CONF = plain
    row("F20 W with a quoted string writes the text at the hex address", bytes_at(d, t, 2) == b"hi", bytes_at(d, t, 2).hex())
    d = fresh("f-w3")
    before = blob(d)
    cmds = "WFFFFFF00=41\nWzz=41\nW%s=4g\nW%s=123\nW%s\nq\n" % (t, t, t)
    CONF = debug_conf
    rc, out, to = tool("sdfix", "-I", d, stdin=cmds, timeout=15)
    CONF = plain
    row("F21 (control) an address past the end, a non-hex address or digit, an odd number of digits and no '=' write nothing",
        blob(d) == before and "Illegal address" in out and out.count("Format error in W command") >= 2 and "Illegal data length" in out, out[-400:])

    say("\n--- -R given with -F or -Q ---------------------------------------------------------------------------------")
    for flag in ("-F", "-Q"):
        d = fresh("f-r" + flag[1])
        set_int16(d, sl, 50)
        set_int16(d, ml, 80)
        before = blob(d)
        rc, out, to = tool("sdfix", "-B", flag, "-R", d, stdin="Y", timeout=20)
        row("F22 %s -R is refused with a message that names the two options, status 1" % flag,
            rc == 1 and "-r cannot be combined with -f or -q" in out, "%r %r" % (rc, out[-300:]))
        row("F23 ... and it did not touch the file (no recovery, no repair)", blob(d) == before and "Recovering space" not in out, out[-200:])
    d = fresh("f-r")
    rc, out, to = tool("sdfix", "-B", "-R", d)
    row("F24 (control) -R alone still recovers space", rc == 0 and "Recovering space" in out, "%r %r" % (rc, out[-300:]))
    d = fresh("f-rc")
    rc, out, to = tool("sdfix", "-B", "-C", "-R", d)
    row("F25 (control) -C -R still checks and then recovers",
        rc == 0 and "Checking file header" in out and "Recovering space" in out, "%r %r" % (rc, out[-300:]))


# --------------------------------------------------------------------------------------------------------------------
def open_rows():
    say("\n=== a file that a live session has open ============================================================================")
    with open(os.path.join(SYSD, "bp", HOLD), "w") as fh:
        fh.write(PROG_HOLD)
    out = sess("BASIC bp %s" % HOLD)
    if "Compiled 1 program(s) with no errors" not in out:
        bail("the holder program did not compile:\n" + out[-500:])
    live = Live()
    try:
        if not live.wait_for("HELD"):
            bail("the holder session never opened the file:\n" + live.text()[-500:])
        say("    the session says HELD: %s is open in SD" % F)
        before = blob(FIX)
        link = os.path.join(WORK, "open-link")
        if os.path.lexists(link):
            os.remove(link)
        os.symlink(FIX, link)
        rc, out, to = tool("sdidx", "-q", FIX)
        row("O1 (control) sdidx -q refuses a file open in SD, status 1", rc == 1 and "File is currently open within SD" in out, "%r %r" % (rc, out[-200:]))
        rc, out, to = tool("sdfix", "-B", FIX)
        row("O2 sdfix refuses it the same way, and says Status: 1", rc == 1 and "File is currently open within SD" in out and "Status: 1" in out, "%r %r" % (rc, out[-300:]))
        row("O3 ... and it read nothing: no check ran", "Checking file header" not in out, out[-300:])
        rc, out, to = tool("sdfix", "-B", link)
        row("O4 ... also when the file is named through a symbolic link", "File is currently open within SD" in out, out[-300:])
        rc, out, to = tool("sdfix", "-B", FIX + "/")
        row("O5 ... also with a trailing slash", "File is currently open within SD" in out, out[-300:])
        rc, out, to = tool("sdfix", "-B", "-F", FIX)
        row("O6 ... also with -F", "File is currently open within SD" in out and "Checking file header" not in out, out[-300:])
        row("O7 ... and none of this wrote to the file", blob(FIX) == before)
    finally:
        live.release()
    say("    the session ended: %r" % live.text()[-120:])
    rc, out, to = tool("sdfix", "-B", FIX)
    row("O8 (control) once the session has closed the file, sdfix checks it: Status: 0",
        rc == 0 and "File is currently open within SD" not in out and "Checking file header" in out and "Status: 0" in out, "%r %r" % (rc, out[-300:]))


# --------------------------------------------------------------------------------------------------------------------
def verifier_rows():
    """Faults found by trying to break the first fixes (18 Oct 26): rows V1-V13, each run red on the tree before."""
    global CONF
    say("\n=== found by trying to break the fixes ===================================================================")
    plain = CONF
    debug_conf = make_conf(True)
    CONF = debug_conf
    offs = header_offsets(fresh("v-offs"))
    CONF = plain
    t = offs["Trigger name"]
    sl, ml = offs["Split load"], offs["Merge load"]

    say("\n--- a data path so long that a two-digit index subfile name does not fit --------------------------------")
    d = fresh_long("v-long251", 251)
    before = blob(d)
    rc, out, to = tool("sdfix", "-B", "-F", d)
    row("V1 (control) at 251 characters every subfile name fits: -F ends Status: 0 and changes nothing",
        rc == 0 and blob(d) == before and "AK" not in out.replace("Checking AK", "") and "Status: 0" in out, "%r %r" % (rc, out[-300:]))
    d = fresh_long("v-long252", 252)
    before = blob(d)
    say("    BEFORE %r" % ls(d))
    rc, out, to = tool("sdfix", "-B", "-F", d)
    say("    AFTER  %r" % ls(d))
    row("V2 at 252 characters the name of AK 8 and up is cut short to %1: -F must not delete the overflow subfile or the "
        "index (it did both)", blob(d) == before, "left %r" % ls(d))
    row("V3 ... it refuses the file, says why, and ends Status: 1",
        rc == 1 and "too long" in out and "Status: 1" in out and "Checking file header" not in out, "%r %r" % (rc, out[-300:]))
    rc, out, to = tool("sdfix", "-B", "-C", d)
    row("V4 ... and a plain check does not report AK subfiles that are the overflow subfile cut short",
        "found but not expected" not in out and "too long" in out, out[-300:])

    say("\n--- input that fails (as opposed to ending) ----------------------------------------------------------------")
    d = fresh("v-stdin-dir")
    CONF = debug_conf
    rc, out, to = tool("sdfix", "-I", d, stdin_dir=True, timeout=8)
    CONF = plain
    row("V5 interactive mode whose input FAILS (stdin is a directory): the program ends (it prompted for ever), "
        "Status: 1", not to and rc == 1 and "Input error" in out, "timed out: %r %r %r" % (to, rc, out[-100:]))
    d = fresh("v-stdin-q")
    set_int16(d, sl, 50)
    set_int16(d, ml, 80)
    before = blob(d)
    rc, out, to = tool("sdfix", "-B", "-Q", d, stdin_dir=True, timeout=8)
    row("V6 -Q whose input fails ends, answers no and writes nothing", not to and blob(d) == before and "end of input" in out.lower(),
        "timed out: %r %r" % (to, out[-200:]))
    d = fresh("v-stdin-idx")
    x = os.path.join(WORK, "v-stdin-idx", "idx")
    tool("sdidx", "-m", d, x)
    rc, out, to = tool("sdidx", "-d", d, stdin_dir=True, timeout=8)
    row("V7 (control) sdidx -d whose input fails stops with nothing deleted, status 1",
        not to and rc == 1 and ls(x) == ["%2"] and "Indices not deleted" in out, "%r %r %r" % (to, rc, out[-200:]))

    say("\n--- the W command's address ---------------------------------------------------------------------------")
    d = fresh("v-w")
    before = blob(d)
    cmds = "W%sg0=41\nW%sxyz=41\nW%s =41\nW%s=41zz\nq\n" % (t, t, t, t)
    CONF = debug_conf
    rc, out, to = tool("sdfix", "-I", d, stdin=cmds, timeout=15)
    CONF = plain
    row("V8 junk after the hex address (g0, xyz, a space) is a format error and writes nothing; it wrote at the part it "
        "could read", blob(d) == before and out.count("Format error in W command") == 4, "%d format errors; %r" % (out.count("Format error in W command"), out[-300:]))

    say("\n--- an index file that cannot be read -----------------------------------------------------------------------")
    d = fresh("v-ak0")
    with open(os.path.join(d, "%2"), "r+b") as fh:
        fh.truncate(0)
    rc, out, to = tool("sdfix", "-B", "-C", d)
    row("V9 an empty index file: a check reports it unreadable once, not also as a bad magic number read from nothing",
        "Cannot read AK0 subfile header" in out and "incorrect magic number" not in out, out[-300:])
    rc, out, to = tool("sdfix", "-B", "-F", d)
    say("    AFTER -F  %r" % ls(d))
    row("V10 -F deletes it and says so once, not a second time that it could not",
        ls(d) == ["%0", "%1"] and out.count("Corrected by deleting") == 1 and "could not be deleted" not in out, out[-400:])

    say("\n--- the exit status over several files ----------------------------------------------------------------")
    d = fresh("v-multi")
    rc, out, to = tool("sdfix", "-B", d + "/nonexistent", d)
    row("V11 a file that is not found, then a good one: the status is 1, not the last file's 0", rc == 1 and "Status: 0" in out,
        "%r %r" % (rc, out[-300:]))

    say("\n--- a relative index path -----------------------------------------------------------------------------")
    d = fresh("v-rel")
    rc, out, to = tool("sdidx", "-m", d, "v-rel/idx")
    where = os.path.join(WORK, "v-rel", "idx")
    row("V12 -m with a RELATIVE index path stores the full path (the header held the text as typed)",
        rc == 0 and ls(where) == ["%2"] and ("Index directory is " + where) in q(d), "%r %r" % (rc, q(d)[-200:]))
    d = fresh("v-relp")
    where = os.path.join(WORK, "v-relp", "idx")
    os.makedirs(where)
    shutil.copy(os.path.join(d, "%2"), where)
    rc, out, to = tool("sdidx", "-p", d, "v-relp/idx")
    row("V13 -p with a RELATIVE index path stores the full path",
        rc == 0 and ("Index directory is " + where) in out and ("Index directory is " + where) in q(d), "%r %r" % (rc, q(d)[-200:]))


def sdconv_rows():
    """sdconv (owner's choice A, 18 Oct 26): a hashed file is refused with a message and status 1, nothing changed; a compiled program is not refused."""
    say("\n=== sdconv ===============================================================================================")
    d = fresh("c-hashed")
    before = blob(d)
    rc, out, to = tool("sdconv", d)
    row("C1 a hashed file is refused: the message says so and the status is 1",
        rc == 1 and "is a hashed file: sdconv converts compiled programs only, nothing was changed" in out, "%r %r" % (rc, out[-250:]))
    row("C2 ... and the file is byte for byte as it was", blob(d) == before and ls(d) == ["%0", "%1", "%2"], repr(ls(d)))
    for opt in ("-L", "-B"):
        rc, out, to = tool("sdconv", opt, d)
        row("C3 %s on a hashed file: the same refusal, status 1, nothing changed" % opt,
            rc == 1 and "is a hashed file" in out and blob(d) == before, "%r %r" % (rc, out[-200:]))
    rc, out, to = tool("sdconv", d, d)
    row("C4 two hashed files named: refused twice, status 1", rc == 1 and out.count("is a hashed file") == 2, "%r %r" % (rc, out[-250:]))
    # controls: something that is neither a hashed file nor a program is left alone and is not an error
    txt = os.path.join(WORK, "c-plain.txt")
    with open(txt, "w") as fh:
        fh.write("not a file sdconv knows\n")
    rc, out, to = tool("sdconv", txt)
    row("C5 (control) an ordinary file: no refusal, status 0", rc == 0 and "hashed file" not in out, "%r %r" % (rc, out[-200:]))
    prog = os.path.join(SYSD, "bp.out", "zztf" + RUN)
    cp = os.path.join(WORK, "c-prog")
    if os.path.exists(prog):
        shutil.copy(prog, cp)
        rc, out, to = tool("sdconv", cp)
        row("C6 (control) a compiled program is not refused: status 0 and no 'hashed file' in the output", rc == 0 and "hashed file" not in out, "%r %r" % (rc, out[-250:]))
    else:
        row("C6 (control) the compiled fixture program exists in bp.out", False, prog)


# --------------------------------------------------------------------------------------------------------------------
def main():
    global BOX, SYSD, BIN, WORK, CONF, FIX
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) != 1:
        bail("usage: sandbox-tools.py <dir> [--build]")
    BOX = os.path.abspath(args[0])
    SYSD = os.path.join(BOX, "sys")
    BIN = os.path.join(SYSD, "bin")
    WORK = os.path.join(BOX, "work")
    CONF = os.path.join(BOX, "sd.conf")
    FIX = os.path.join(SYSD, F)
    say("sandbox-tools: sandbox %s" % BOX)
    say("sandbox-tools: tree    %s" % os.path.dirname(HERE))
    say("sandbox-tools: file    %s, holder program %s" % (F, HOLD))
    if "--build" in sys.argv:
        if os.path.exists(BOX) and os.listdir(BOX):
            bail("%s is not empty" % BOX)
        r = subprocess.run([sys.executable, TOOL, BOX, "all"], capture_output=True, text=True, errors="replace", timeout=900)
        if "[FAIL]" in r.stdout or r.returncode != 0 or "[PASS] THIRD.COMPILE" not in r.stdout:
            bail("the sandbox build did not pass:\n" + r.stdout[-800:])
        say("sandbox-tools: built, bootstrap passed")
    elif not os.path.isfile(os.path.join(BIN, "sd")):
        bail("%s holds no built sandbox (use --build, or point it at one)" % BOX)
    for t in ("sdidx", "sdfix", "sdconv"):
        if not os.path.isfile(os.path.join(BIN, t)):
            bail("%s is not in the sandbox" % t)
        with open(os.path.join(BIN, t), "rb") as fh:
            body = fh.read()
        say("sandbox-tools: tool    %s (%d bytes, sha1 %s)" % (os.path.join(BIN, t), len(body), hashlib.sha1(body).hexdigest()[:12]))
    subprocess.run([sys.executable, TOOL, BOX, "start"], capture_output=True, text=True, errors="replace", timeout=120)
    os.makedirs(WORK, exist_ok=True)

    made = []
    try:
        say("\n--- the fixture: SD makes a file, 40 records and a built index on CITY ------------------------------------")
        with open(os.path.join(SYSD, "bp", "zztf" + RUN), "w") as fh:
            fh.write(PROG_FILL)
        made.append("zztf" + RUN)
        out = sess("DELETE.FILE %s" % F, "CREATE.FILE %s" % F, "BASIC bp zztf%s" % RUN)
        if "Compiled 1 program(s) with no errors" not in out:
            bail("the fixture program did not compile:\n" + out[-500:])
        out = sess("RUN bp zztf%s" % RUN, "CREATE.INDEX %s CITY" % F, "BUILD.INDEX %s CITY" % F)
        if "Added index for CITY" not in out or "40 records processed" not in out:
            bail("the index was not made and built (40 records):\n" + out[-600:])
        if ls(FIX) != ["%0", "%1", "%2"]:
            bail("the fixture directory is %r, not %%0 %%1 %%2:\n%s" % (ls(FIX), FIX))
        say("    fixture %s holds %r" % (FIX, ls(FIX)))
        sdidx_rows()
        sdfix_rows()
        open_rows()
        verifier_rows()
        sdconv_rows()
    finally:
        say("\n--- cleanup -------------------------------------------------------------------------------------")
        sess("DELETE.FILE %s" % F)
        for nm in made + [HOLD]:
            for dd in ("bp", "bp.out"):
                pth = os.path.join(SYSD, dd, nm)
                if os.path.exists(pth):
                    os.remove(pth)
        shutil.rmtree(WORK, ignore_errors=True)
        for s in shorts:
            shutil.rmtree(s, ignore_errors=True)
        left = [n for n in (F, F + ".dic") if os.path.exists(os.path.join(SYSD, n))]
        row("cleanup: the fixture file is gone", not left, " ".join(left))

    say("\nsandbox-tools: %d passed, %d failed" % (passed, failed))
    if passed + failed == 0:
        bail("no row ran - a broken test, not a pass")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
