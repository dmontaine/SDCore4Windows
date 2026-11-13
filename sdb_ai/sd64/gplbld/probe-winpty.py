#!/usr/bin/env python3
"""probe-winpty.py - Linux's ptydrive.PtySession for SD Core for Windows: SD on a REAL pseudo-terminal (RELEASE_1.1 272).

WHY.  Linux's TUI and screen suites (sandbox-winsize.py and 25 more) drive sd through gplbld/ptydrive.py, which needs
pty.fork(), termios and fcntl.  Native Windows Python has none of them.  MSYS2's Python has all three (its platform is
"cygwin"), but a Cygwin pty is only a terminal to a process of the SAME runtime installation, and Cygwin tells
installations apart by the folder msys-2.0.dll is loaded from: python3.exe loads C:\\msys64\\usr\\bin\\msys-2.0.dll and the
installed sd.exe loads C:\\Program Files\\SD\\usr\\bin\\msys-2.0.dll.  Measured 13 Nov 26: Linux's ptydrive run under
C:\\msys64's Python against the installed sd.exe printed only "SD has not been started."

THE ROUTE.  Python joins SD's OWN runtime installation; sd.exe is the installed one, run where it is:

    %LOCALAPPDATA%\\SD-verify\\winpty-py   MSYS2's python3.12.exe and the DLLs it needs that SD does not ship - and NO
                                         msys-2.0.dll.  The server is started with C:\\Program Files\\SD\\usr\\bin first on
                                         PATH, so Windows' loader finds msys-2.0.dll THERE: Python's runtime root is then
                                         C:\\Program Files\\SD (its etc\\fstab maps /dev/shm), its pids are SD's pids and its
                                         ptys are terminals to sd.exe.  PYTHONHOME points at C:\\msys64\\usr for the library.

Nothing is written to C:\\Program Files\\SD or C:\\msys64.  ensure_root() refuses to go on unless the root's Python reports
the root it measured (/usr/bin/sd.exe exists, the segment is under /dev/shm), so a Python that found another runtime is
refused rather than used.

WHY NOT A COPIED ROOT (tried first, 13 Nov 26, and it cost the install).  A scratch root holding copies of sd.exe, its DLLs
and Python shares one runtime between them, but it is a SECOND installation beside SD's: Cygwin pids are numbered per
installation, and SD keys every session by pid and asks kill(pid, 0) whether it lives (sysseg.c, clopts.c
process_exists(), sdwind.c's lost-user check).  The copied sd.exe (Cygwin pid 1677) printed nothing; ended by the hang-up
and a second one by a timeout, they left the installed SD in the RELEASE_1.1 152 state - every new session, the installed
sd.exe on a pipe included, spins at full CPU with no output.  Do not build a copied root against a running SD.

THE SPLIT.  The suites run under native Python (verify-carry-run.py patches subprocess, open ... there).  So this file is
both halves:
  * imported under native Python it gives PtySession, with ptydrive's interface (type, settle, resize, keeps_writing,
    finish, raw, screen, exited, status, pid).  Each session starts the root's Python on THIS file with --serve;
  * --serve, under the root's Python, runs Linux's ptydrive.PtySession unchanged (probe-ptydrive.py, a byte copy) and
    answers one JSON line per request.  The bytes SD wrote go back to the client, which feeds its own termscreen.Screen
    (probe-termscreen.py, a byte copy), so screen.lines() is what Linux's emulator makes of the same bytes.  Settling
    (the idle wait) is timed in the server, beside the pty, as on Linux.
  * Linux's finish() ends with SIGKILL when a hang-up does not end sd.  HERE IT NEVER KILLS (CLAUDE.md, memory
    never-stop-process-an-sd-session: a killed session once left every later one spinning).  finish() reads until
    sd exits, then hangs the terminal up (the master closes: SIGHUP, which SD handles), and if sd is STILL running it
    prints its pid and Windows pid and leaves it.

USE.
    python probe-winpty.py --build              build or refresh the root, print what it holds
    python probe-winpty.py --selftest [ACCTDIR] the root, then SD on a 100 by 30 pty in ACCTDIR (default: the caller's
                                                account): TERM must answer Page width: 100 and Page depth: 30
    python probe-winpty.py --selfpty            the root, then a pty round trip with PYTHON as the child (no SD session)
Environment: SD_EXE (the installed sd.exe, default the multi-user install's), SD_WINPTY_ROOT (the Python folder),
SD_WINPTY_MSYS (MSYS2's folder, default C:\\msys64).  Exit 0 passed, 1 failed, 2 could not run.

START-HISTORY:
13 Nov 26 dm  New (RELEASE_1.1 272).
END-HISTORY
"""
import base64
import importlib.util
import json
import os
import re
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
PY_FILES = ("python3.12.exe",)
# What MSYS2's python3.12.exe and the modules this file imports need beyond what SD's usr\bin ships (ldd, 13 Nov 26; the
# root's Python is made to import every module the server uses before the root is believed: ensure_root()).  NEVER
# msys-2.0.dll: its absence from this folder is what makes the loader take SD's.
PY_DLLS = ("msys-python3.12.dll", "msys-intl-8.dll", "msys-iconv-2.dll", "msys-z.dll")
SERVER_IMPORTS = "import pty, fcntl, termios, select, json, base64, struct, codecs, errno, signal, importlib.util"
# What the root's Python must report before it is used: its runtime root is SD's (sd.exe at /usr/bin, the segment under
# /dev/shm through SD's fstab) - a Python that loaded another msys-2.0.dll sees neither.
ROOT_CHECK = (SERVER_IMPORTS + "; import os, sys; print('PYOK', sys.platform, os.path.isfile('/usr/bin/sd.exe'), "
              "any(n.startswith('sd_shm_') for n in os.listdir('/dev/shm')), sys.prefix)")


def load(name, fname):
    """A byte copy of a Linux module, under the name Linux imports it by."""
    if name in sys.modules:
        return sys.modules[name]
    spec = importlib.util.spec_from_file_location(name, os.path.join(HERE, fname))
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return mod


def posix(p):
    """A Windows path as the root's runtime spells it (the root's fstab sets no cygdrive prefix, so it is /cygdrive)."""
    p = os.path.abspath(p) if re.match(r"^[A-Za-z]:", p) or "\\" in p else p
    m = re.match(r"^([A-Za-z]):[\\/]?(.*)$", p)
    if not m:
        return p.replace("\\", "/")
    return "/cygdrive/" + m.group(1).lower() + "/" + m.group(2).replace("\\", "/")


# ---------------------------------------------------------------------------------------------------------------------
# The server: runs under the ROOT's Python (sys.platform "cygwin").
# ---------------------------------------------------------------------------------------------------------------------

def serve():
    load("termscreen", "probe-termscreen.py")
    ptydrive = load("ptydrive", "probe-ptydrive.py")
    out = sys.stdout.buffer
    inp = sys.stdin.buffer
    s = None
    sent = 0

    def reply(**kw):
        nonlocal sent
        if s is not None:
            kw["data"] = base64.b64encode(s.raw[sent:]).decode("ascii")
            sent = len(s.raw)
            kw["exited"] = s.exited
            kw["status"] = s.status
        out.write((json.dumps(kw) + "\n").encode("ascii"))
        out.flush()

    def winpid(pid):
        try:
            with open("/proc/%d/winpid" % pid) as fh:
                return int(fh.read().strip())
        except (OSError, ValueError):
            return None

    def finish(limit):
        """ptydrive.finish without its SIGKILL: read until sd exits; then hang up; never kill."""
        end = time.time() + limit
        while time.time() < end and not s.exited:
            s._pump(0.2)
            if s._reap(0.0):
                s.exited = True
        hung_up = False
        if not s.exited or s.status is None:
            if s._reap(2.0):
                s.exited = True
        if s.status is None:
            hung_up = True
            try:
                os.close(s.fd)          # the master closes: the session leader gets SIGHUP
            except OSError:
                pass
            s.fd = -1
            if s._reap(10.0):
                s.exited = True
        still = None if s.status is not None else {"pid": s.pid, "winpid": winpid(s.pid)}
        if s.fd >= 0:
            try:
                os.close(s.fd)
            except OSError:
                pass
            s.fd = -1
        return hung_up, still

    while True:
        line = inp.readline()
        if not line:                    # the client has gone: end the session the clean way, never by a kill
            if s is not None and s.status is None:
                finish(3.0)
            return 0
        req = json.loads(line.decode("ascii"))
        op = req.get("op")
        try:
            if op == "start":
                argv, cwd = req["argv"], req["cwd"]
                if not os.path.isfile(argv[0]) or not os.path.isdir(cwd):
                    reply(error="NULL CASE: the program %r or the directory %r is not there (as the root sees it)" % (argv[0], cwd))
                    continue
                s = ptydrive.PtySession(argv, cwd, dict(os.environ), req["cols"], req["rows"])
                reply(pid=s.pid, winpid=winpid(s.pid), platform=sys.platform, python=sys.executable)
            elif op == "type":
                s.type(base64.b64decode(req["data"]), settle=req.get("settle", True), idle=req.get("idle", 0.35))
                reply()
            elif op == "settle":
                s.settle(req.get("idle", 0.35), req.get("limit", 20.0))
                reply()
            elif op == "pump":
                s._pump(req.get("wait", 0.0))
                reply()
            elif op == "resize":
                s.resize(req["cols"], req["rows"], req.get("idle", 0.6))
                reply()
            elif op == "keeps_writing":
                s.keeps_writing()
                reply()
            elif op == "finish":
                hung_up, still = finish(req.get("limit", 10.0))
                reply(hung_up=hung_up, still_running=still)
                return 0
            else:
                reply(error="unknown op %r" % op)
        except Exception as e:          # the client prints it; the session is left to finish or to the hang-up above
            reply(error="%s: %s" % (type(e).__name__, e))


# ---------------------------------------------------------------------------------------------------------------------
# The root, built from native Python.
# ---------------------------------------------------------------------------------------------------------------------

def sd_exe():
    return os.environ.get("SD_EXE") or os.path.join(os.environ.get("ProgramFiles", "C:\\Program Files"), "SD", "usr", "bin", "sd.exe")


def root_dir():
    return os.environ.get("SD_WINPTY_ROOT") or os.path.join(os.environ.get("LOCALAPPDATA", HERE), "SD-verify", "winpty-py")


def msys_dir():
    return os.environ.get("SD_WINPTY_MSYS") or "C:\\msys64"


def py_env(env):
    """The environment the root's Python is started with: SD's usr\\bin FIRST on PATH (the loader takes msys-2.0.dll from
    there), the library from MSYS2, and no PYTHONPATH.  The same environment reaches sd.exe through the fork, so the only
    difference from what a suite asked for is PATH's first entry, SD's own program folder."""
    e = dict(env)
    e.pop("PYTHONPATH", None)
    e["PATH"] = os.path.dirname(sd_exe()) + ";" + e.get("PATH", "")
    e["PYTHONHOME"] = posix(os.path.join(msys_dir(), "usr"))
    e["PYTHONNOUSERSITE"] = "1"
    return e


_ROOT = None


def ensure_root(verbose=False):
    """Build or refresh the Python folder; return {'root', 'python', 'sd'} (Windows paths).  RuntimeError if it cannot."""
    global _ROOT
    if _ROOT is not None:
        return _ROOT
    import shutil
    import subprocess

    def say(m):
        if verbose:
            print("winpty-root: " + m)

    sdbin = os.path.dirname(sd_exe())
    msysbin = os.path.join(msys_dir(), "usr", "bin")
    root = root_dir()
    for need in (sd_exe(), os.path.join(sdbin, "msys-2.0.dll"), os.path.join(msysbin, PY_FILES[0]),
                 os.path.join(msys_dir(), "usr", "lib", "python3.12", "os.py")):
        if not os.path.exists(need):
            raise RuntimeError("NULL CASE: %s is not there" % need)
    os.makedirs(root, exist_ok=True)
    if os.path.exists(os.path.join(root, "msys-2.0.dll")):
        raise RuntimeError("%s holds an msys-2.0.dll: the Python there would load it, not SD's (remove it)" % root)
    srcs = [(os.path.join(msysbin, f), f) for f in PY_FILES + PY_DLLS]
    copied = 0
    for src, f in srcs:
        if not os.path.isfile(src):
            raise RuntimeError("NULL CASE: %s is not there" % src)
        dst = os.path.join(root, f)
        st = os.stat(src)
        if os.path.isfile(dst):
            dt = os.stat(dst)
            if dt.st_size == st.st_size and int(dt.st_mtime) == int(st.st_mtime):
                continue
        shutil.copy2(src, dst)          # an error here (a copy in use) is raised, not passed over
        copied += 1
    py = os.path.join(root, PY_FILES[0])
    say("python    %s (%s copied from %s, %d refreshed; no msys-2.0.dll)" % (py, ", ".join(f for _, f in srcs), msysbin, copied))
    say("runtime   %s first on PATH" % sdbin)
    r = subprocess.run([py, "-s", "-c", ROOT_CHECK], capture_output=True, timeout=60, env=py_env(os.environ))
    txt = (r.stdout + r.stderr).decode("utf-8", "replace").strip()
    say("measured  %s" % txt)
    if r.returncode != 0 or not re.search(r"(?m)^PYOK cygwin True True ", txt):
        raise RuntimeError("the Python is not in SD's runtime (want 'PYOK cygwin True True': sd.exe at /usr/bin and the "
                           "segment under /dev/shm): rc %d, %s" % (r.returncode, txt[-400:]))
    _ROOT = {"root": root, "python": py, "sd": sd_exe()}
    return _ROOT


# ---------------------------------------------------------------------------------------------------------------------
# The client: ptydrive.PtySession's interface, under native Python.
# ---------------------------------------------------------------------------------------------------------------------

def _is_sd(p):
    n = str(p).replace("\\", "/").lower()
    return n.endswith("/sys/bin/sd") or n.endswith("/sd.exe") or n.endswith("/bin/sd")


class PtySession:
    idle_cap = None

    def __init__(self, argv, cwd, env, cols=100, rows=24, utf8=False):
        import codecs
        import subprocess
        import tempfile
        Screen = load("termscreen", "probe-termscreen.py").Screen
        r = ensure_root()
        self.cols = cols
        self.rows = rows
        self.dec = codecs.getincrementaldecoder("utf-8")("replace") if utf8 else None
        self.raw = b""
        self.screen = Screen(cols, rows)
        self.exited = False
        self.status = None
        self.killed = False
        self.fd = 0
        # The box's stand-in sd, or any sd.exe, is the INSTALLED sd.exe, which the runtime root names /usr/bin/sd.exe.
        args = ["/usr/bin/sd.exe" if (i == 0 and _is_sd(a)) else (posix(a) if (i == 0 or re.match(r"^[A-Za-z]:\\", str(a))) else str(a))
                for i, a in enumerate(argv)]
        fd, self._errf = tempfile.mkstemp(prefix="winpty-serve-", suffix=".err")
        os.close(fd)
        self._err = open(self._errf, "wb")
        self._p = subprocess.Popen([r["python"], "-s", "-u", posix(os.path.abspath(__file__)), "--serve"],
                                   stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=self._err, env=py_env(env))
        rep = self._call(op="start", argv=args, cwd=posix(cwd), cols=cols, rows=rows)
        self.pid = rep.get("pid")
        self.winpid = rep.get("winpid")
        self.argv_used = args

    def _call(self, **req):
        try:
            self._p.stdin.write((json.dumps(req) + "\n").encode("ascii"))
            self._p.stdin.flush()
            line = self._p.stdout.readline()
        except OSError:
            line = b""
        if not line:
            self._err.flush()
            with open(self._errf, "rb") as fh:
                err = fh.read().decode("utf-8", "replace")
            raise RuntimeError("probe-winpty: the pty server ended (op %s); its stderr: %s" % (req.get("op"), err[-1500:]))
        rep = json.loads(line.decode("ascii"))
        data = base64.b64decode(rep.get("data", ""))
        if data:
            self.raw += data
            self.screen.feed(self.dec.decode(data) if self.dec else data.decode("latin-1"))
        if "exited" in rep:
            self.exited = rep["exited"]
            self.status = rep["status"]
        if rep.get("error"):
            raise RuntimeError("probe-winpty: %s" % rep["error"])
        return rep

    def keeps_writing(self):
        self.idle_cap = 0.7
        self._call(op="keeps_writing")

    def resize(self, cols, rows, idle=0.6):
        # ptydrive: the ioctl, then the emulator resizes, then what the program writes in answer is fed.  The client's emulator
        # resizes before the answer's bytes come back, so the order of feeding is Linux's.
        self.cols = cols
        self.rows = rows
        self.screen.resize(cols, rows)
        self._call(op="resize", cols=cols, rows=rows, idle=idle)

    def _pump(self, wait):
        before = len(self.raw)
        if not self.exited:
            self._call(op="pump", wait=wait)
        return self.raw[before:]

    def settle(self, idle=0.35, limit=20.0):
        if not self.exited:
            self._call(op="settle", idle=idle, limit=limit)

    def type(self, data, settle=True, idle=0.35):
        if isinstance(data, str):
            data = data.encode("latin-1")
        if self.exited or self._p is None:
            return
        self._call(op="type", data=base64.b64encode(data).decode("ascii"), settle=settle, idle=idle)

    def finish(self, limit=10.0):
        """Let sd go: read until it exits, then hang up.  NEVER a kill: one still running is printed and left."""
        if self._p is None:
            return self.status
        rep = self._call(op="finish", limit=limit)
        self.exited = True
        still = rep.get("still_running")
        if still:
            print("probe-winpty: SD IS STILL RUNNING after OFF and a hang-up - pid %s, Windows pid %s; LEFT ALONE (no kill), "
                  "report it" % (still.get("pid"), still.get("winpid")))
        try:
            self._p.stdin.close()
        except OSError:
            pass
        try:
            self._p.wait(timeout=30)
        except Exception:
            print("probe-winpty: the pty server (Windows pid %d) did not end; left alone" % self._p.pid)
        self._p = None
        self._err.close()
        try:
            os.remove(self._errf)
        except OSError:
            pass
        return self.status


# ---------------------------------------------------------------------------------------------------------------------

def selfpty():
    """No SD session: the root's Python on the pty, as the child, says whether its stdin is a terminal, the size it was
    given, which SD processes it can see by Windows pid (the pid namespace is SD's), and echoes a typed line back."""
    import subprocess
    try:
        r = ensure_root(verbose=True)
    except RuntimeError as e:
        print("probe-winpty: CANNOT RUN - %s" % e)
        return 2
    tl = subprocess.run(["tasklist", "/fo", "csv", "/nh"], capture_output=True, text=True).stdout
    sdp = {int(m.group(2)): m.group(1) for m in re.finditer(r'(?m)^"(sd\.exe|sdsvc\.exe|sdwind\.exe)","(\d+)"', tl)}
    print("probe-winpty: SD processes running (tasklist): %r" % sdp)
    child = ("import os, struct, fcntl, termios\n"
             "w = set()\n"
             "for d in os.listdir('/proc'):\n"
             "    try:\n"
             "        w.add(int(open('/proc/%s/winpid' % d).read()))\n"
             "    except (OSError, ValueError):\n"
             "        pass\n"
             "sz = struct.unpack('HHHH', fcntl.ioctl(0, termios.TIOCGWINSZ, bytes(8)))\n"
             "print('CHILD isatty=%s rows=%d cols=%d' % (os.isatty(0), sz[0], sz[1]))\n"
             "print('CHILD sees=%s' % sorted(w & set(" + repr(sorted(sdp)) + ")))\n"
             "print('CHILD read=<%s>' % input('CHILD ready> '))\n")
    s = PtySession([r["python"], "-s", "-c", child], os.environ.get("TEMP", HERE), dict(os.environ), 90, 27)
    print("probe-winpty: started %r on a 90 by 27 pty: pid %s, Windows pid %s" % (s.argv_used[0], s.pid, s.winpid))
    try:
        s.settle(1.0)
        s.type("hello pty\r", idle=0.8)
    finally:
        s.finish()
    txt = s.raw.decode("latin-1")
    print("probe-winpty: the child wrote %r" % txt)
    a = re.search(r"CHILD isatty=True rows=27 cols=90", txt) is not None
    b = re.search(r"CHILD read=<hello pty>", txt) is not None
    m = re.search(r"CHILD sees=\[([\d, ]*)\]", txt)
    seen = [int(x) for x in m.group(1).split(",") if x.strip()] if m else []
    # Every running sd.exe must be visible, and at least one SD process: sdsvc.exe is the native service wrapper, and one of the
    # two sdwind.exe Windows processes is outside Cygwin's table (13 Nov 26: 2408 and the sd.exe seen, 8052 and 12140 not).
    sds = {p for p, n in sdp.items() if n == "sd.exe"}
    c = bool(seen) and sds <= set(seen)
    print("probe-winpty: a terminal of 90 by 27: %s; a typed line read back: %s; SD's processes visible by pid %r of %r: %s"
          % (a, b, seen, sdp, c))
    if not sdp:
        print("probe-winpty: NULL CASE for the pid row - no SD process is running to look for")
    ok = a and b and c
    print("probe-winpty: %s" % ("PASSED" if ok else "FAILED"))
    return 0 if ok else 1


def selftest(acct):
    try:
        ensure_root(verbose=True)
    except RuntimeError as e:
        print("probe-winpty: CANNOT RUN - %s" % e)
        return 2
    if not os.path.isdir(acct):
        print("probe-winpty: CANNOT RUN - no account directory %s" % acct)
        return 2
    env = dict(os.environ, TERM="xterm")
    env.pop("LINES", None)
    env.pop("COLUMNS", None)
    s = PtySession([sd_exe()], acct, env, 100, 30)
    print("probe-winpty: started argv %r cwd %s on a 100 by 30 pty: pid %s, Windows pid %s" % (s.argv_used, posix(acct), s.pid, s.winpid))

    def show(t):
        print("\n=== %s: %d raw bytes; screen:" % (t, len(s.raw)))
        for i, ln in enumerate(s.screen.lines()):
            if ln.strip():
                print("%2d|%s" % (i, ln.rstrip()))

    ok = False
    try:
        s.settle(1.0)
        show("after start")
        s.type("TERM xterm\r", idle=0.8)
        s.type("TERM\r", idle=0.8)
        show("after TERM xterm, TERM")
        scr = "\n".join(s.screen.lines())
        w = re.search(r"(?m)^Page width: (\d+)\s*$", scr)
        d = re.search(r"(?m)^Page depth: (\d+)\s*$", scr)
        print("\nprobe-winpty: TERM answered width %s, depth %s" % (w and w.group(1), d and d.group(1)))
        ok = bool(w and d and w.group(1) == "100" and d.group(1) == "30")
        s.type("OFF\r", settle=False)
    finally:
        st = s.finish()
        print("probe-winpty: SD exited, status %r" % (st,))
    print("probe-winpty: %s" % ("PASSED - sd.exe ran on the pty and took its size" if ok else
                                "FAILED - no 'Page width: 100' and 'Page depth: 30' on the screen"))
    return 0 if ok else 1


def main():
    if "--serve" in sys.argv:
        return serve()
    if "--build" in sys.argv:
        try:
            ensure_root(verbose=True)
        except RuntimeError as e:
            print("probe-winpty: CANNOT RUN - %s" % e)
            return 2
        return 0
    if "--selfpty" in sys.argv:
        return selfpty()
    if "--selftest" in sys.argv:
        rest = [a for a in sys.argv[1:] if not a.startswith("--")]
        acct = rest[0] if rest else os.path.join(os.environ.get("ProgramData", "C:\\ProgramData"), "SD", "user_accounts",
                                                 os.environ.get("USERNAME", ""))
        return selftest(acct)
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main())
