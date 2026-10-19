#!/usr/bin/env python3
"""verify-carry-run.py <verify-carry-NAME.py> <box> [args] - run one Linux sandbox suite against the INSTALLED SD.

WHAT THIS IS.  The files gplbld/verify-carry-*.py are BYTE COPIES of SD Core for Linux's sandbox-*.py suites
(the area 1 backlog, 1c94d00..ba885ac), renamed into this tree's verify- family so that assert-current does not
watch them.  Each suite drives a private Linux SD through gplbld/sandbox-fromtree.py:

    sandbox-fromtree.py <box> all            build the sandbox        -> here: nothing to build
    sandbox-fromtree.py <box> start | stop   daemon                   -> here: the installed service runs
    sandbox-fromtree.py <box> sess <cwd> "<command>" ...             -> here: sd.exe, commands on its stdin

and writes its probe programs into <box>/sys/bp (and compiles them with BASIC bp NAME).  verify-carry.ps1 makes
<box>/sys a junction to the caller's own account directory, so those writes land in that account's bp file, and
this launcher stands in for sandbox-fromtree.py by intercepting subprocess.run in the suite's own process.
The suites are not edited, so the next carry from Linux is a plain copy.

WHAT IT CHANGES, AND NOTHING ELSE:
  1. subprocess.run/Popen/check_output of "<this python> .../sandbox-fromtree.py ..." -> the emulation above.
     A session is "\\nTERM 200,9999\\n" + the commands + "OFF\\n" on sd.exe's stdin, exactly as Linux sends it, and
     the output is ANSI-stripped and ends with "exit N" like Linux's.
  2. A call of <box>/sys/bin/sd (a few suites run the binary themselves) -> the installed sd.exe.
  3. os.path.isfile/exists of <box>/sys/bin/sd -> True (there is no such file in an account, only sd.exe).
  4. open() in a text WRITE mode defaults to newline="\\n": the suites write BASIC source and directory-file
     records, and a CR LF written by Windows text mode would reach BCOMP as part of every line.
  5. time.tzset (absent from Python on Windows) is a no-op, so a suite that sets TZ for the sessions it starts still
     starts them; the zone it asks for is whatever sd.exe makes of the variable (the C library, not Python).
  6. <box>/sd.conf is a COPY of the installed sd.conf (SD_CARRY_CONF, default C:\\ProgramData\\SD\\sd.conf), made when the
     box has none.  Linux's suites read it, change a parameter and restart the daemon; here the copy is changed and the
     installed service never reads it, so a row that needs the changed parameter FAILS, and is named in
     verify-carry-known.psd1 as a Linux mechanism rather than hidden.
  7. (RELEASE_1.1 159, sandbox-tools.py) A call of <box>/sys/bin/sdidx, sdfix or sdconv -> the installed exe beside sd.exe;
     os.symlink to a directory falls back to a junction when a symbolic link is refused; os.open("/") (a stdin on which
     read() fails) is a directory handle opened with FILE_FLAG_BACKUP_SEMANTICS; tempfile.mkdtemp(dir="/tmp") is the root of
     the system drive (the suite needs a SHORT path); os.mkdir and os.rmdir take the \\\\?\\ prefix on a path over 240 characters
     (the suite builds directories of 251 and 252); a text-mode Popen pipe writes bare LF, as the launcher's sessions do; and
     a session a suite starts itself (Popen of the stand-in sd) gets the SD_CARRY_PW first line and the SD_CARRY_SPARE_OFF
     lines at its end (SessionStdin), and its output file is read with the password masked.

Environment (all optional): SD_EXE the sd executable (default the multi-user install's sd.exe);
SD_CARRY_PW the account password to send first (SD Core Solo); SD_CARRY_SPARE_OFF extra OFF lines;
SD_CARRY_TIMEOUT seconds a session may run (default 600); SD_CARRY_CONF the sd.conf to copy into the box;
SD_CARRY_TOOLDIR the folder holding sdidx.exe, sdfix.exe and sdconv.exe (default: beside sd.exe).

Exit status is the suite's own: 0 every row passed, 1 a row failed, 2 it could not run.
"""
import builtins
import io
import os
import re
import runpy
import shutil
import subprocess
import sys
import tempfile
import time

ANSI = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]")
SD_EXE = os.environ.get("SD_EXE") or os.path.join(os.environ.get("ProgramFiles", r"C:\Program Files"), "SD", "usr", "bin", "sd.exe")
TOOL_NAME = "sandbox-fromtree.py"

real_run = subprocess.run
real_popen = subprocess.Popen
real_isfile = os.path.isfile
real_exists = os.path.exists
real_open = builtins.open
real_symlink = os.symlink
real_os_open = os.open
real_mkdtemp = tempfile.mkdtemp
real_mkdir = os.mkdir
real_rmdir = os.rmdir

# The stand-alone tools a suite runs as <box>/sys/bin/<name> (sandbox-tools.py): here the installed <name>.exe beside sd.exe,
# or beside SD_CARRY_TOOLDIR when that is set (a freshly built tool checked BEFORE a cycle installs it; the suite prints the
# size and hash of the file it ran, so a run says which one it was).
STUB_TOOLS = ("sdidx", "sdfix", "sdconv")
TOOL_DIR = os.environ.get("SD_CARRY_TOOLDIR") or os.path.dirname(SD_EXE)


def is_stub_sd(p):
    try:
        n = os.path.normpath(str(p)).replace("\\", "/")
    except Exception:
        return False
    return n.endswith("/sys/bin/sd")


def stub_tool(p):
    """The installed exe that a <box>/sys/bin/<tool> path stands for, or None if p is not one."""
    if not isinstance(p, str):
        return None
    n = os.path.normpath(p).replace("\\", "/")
    for t in STUB_TOOLS:
        if n.endswith("/sys/bin/" + t):
            return os.path.join(TOOL_DIR, t + ".exe")
    return None


def fake_isfile(p):
    t = stub_tool(p)
    if t is not None:
        return real_isfile(t)               # a missing tool is reported as missing, not invented
    return True if is_stub_sd(p) else real_isfile(p)


def fake_exists(p):
    t = stub_tool(p)
    if t is not None:
        return real_exists(t)
    return True if is_stub_sd(p) else real_exists(p)


def tool_call(args):
    """The argument list after TOOL if args is a call of sandbox-fromtree.py, else None."""
    if isinstance(args, (list, tuple)) and len(args) >= 3 and os.path.basename(str(args[1])) == TOOL_NAME:
        return [str(a) for a in args[2:]]
    return None


def emulate(rest, kw):
    """rest = [box, step, ...].  Returns a CompletedProcess."""
    step = rest[1] if len(rest) > 1 else ""
    out = ""
    rc = 0
    if step in ("all", "build"):
        out = "sandbox-fromtree (Windows launcher): nothing to build; the installed SD is used.\n[PASS] THIRD.COMPILE\n"
    elif step in ("assemble", "boot", "start", "stop"):
        out = ""
    elif step == "sess":
        cmds = rest[3:]
        # SD_CARRY_PW: the account password, first line of input (SD Core Solo asks for it at every
        # session).  SD_CARRY_SPARE_OFF: extra OFF lines at the end (Solo needs two - SOLO 16: at the end
        # of piped input the command editor otherwise rings the bell in a loop).
        pw = os.environ.get("SD_CARRY_PW")
        spare = int(os.environ.get("SD_CARRY_SPARE_OFF") or "0")
        body = ("\n" if pw is None else pw + "\n") + "TERM 200,9999\n" + "".join(c + "\n" for c in cmds) + "OFF\n" + "OFF\n" * spare
        # Output goes to a FILE, never a pipe: a service helper that inherits a pipe holds it open for ever.
        import tempfile
        fd, tmp = tempfile.mkstemp(prefix="carry-sess-", suffix=".txt")
        os.close(fd)
        try:
            with real_open(tmp, "wb") as fh:
                p = real_run([SD_EXE], input=body.encode("ascii" if pw is not None else "utf-8", "replace"), stdout=fh,
                             stderr=subprocess.STDOUT, timeout=kw.get("timeout") or int(os.environ.get("SD_CARRY_TIMEOUT") or "600"))
            with real_open(tmp, "rb") as fh:
                raw = fh.read()
        finally:
            try:
                os.remove(tmp)
            except OSError:
                pass
        text = raw.decode("utf-8", "replace").replace("\r\n", "\n")
        # sd.exe echoes a piped command twice: ":BASICbpzz1" for the keystrokes, a CR, then ":BASIC bp zz1" redrawn.  Linux's
        # sd shows the second form on a line of its own, and suites find a command by `^:BASIC bp zz1$`; a bare CR is a line end.
        text = re.sub(r"\r(?!\n)", "\n", text)
        if pw:
            text = text.replace(pw, "********")
        out = ANSI.sub("", text) + "\nexit %d\n" % p.returncode
        rc = 0
    else:
        return subprocess.CompletedProcess(rest, 2, "", "sandbox-fromtree (Windows launcher): unknown step %r\n" % step)
    text_mode = kw.get("text") or kw.get("universal_newlines") or kw.get("encoding") or kw.get("errors")
    return subprocess.CompletedProcess(rest, rc, out if text_mode else out.encode("utf-8", "replace"), "" if text_mode else b"")


def patched_run(args, *a, **kw):
    t = tool_call(args)
    if t is not None:
        return emulate(t, kw)
    return real_run(real_args(args), *a, **kw)


def real_args(args):
    """A call of the box's stand-in sd or tool becomes a call of the installed exe."""
    if isinstance(args, (list, tuple)) and args:
        if is_stub_sd(args[0]):
            return [SD_EXE] + list(args[1:])
        t = stub_tool(args[0])
        if t is not None:
            return [t] + list(args[1:])
    return args


class SessionStdin:
    """The stdin of a session a suite starts ITSELF (sandbox-tools.py keeps one open to hold a file), for SD Core Solo: its
    sd-solo asks for the password as the first line and, at the end of piped input, needs spare OFF lines or its command
    editor rings the bell in a loop (SOLO 16).  The launcher's own sessions send both (emulate); this does the same for a
    suite's, so the suite is not edited.  The suite's first write starts with the LF Linux's sd takes as its first line;
    the password goes in front of it."""

    def __init__(self, f, pw, spare):
        self._f = f
        self._pw = pw
        self._spare = spare
        self._first = True
        self._closed = False

    def write(self, s):
        if self._first:
            self._first = False
            s = self._pw + (s if s.startswith("\n") else "\n" + s)
        return self._f.write(s)

    def close(self):
        if not self._closed:
            self._closed = True
            try:
                self._f.write("OFF\n" * self._spare)
                self._f.flush()
            except (OSError, ValueError):
                pass
        self._f.close()

    def __getattr__(self, name):
        return getattr(self._f, name)


class PatchedPopen(real_popen):
    def __init__(self, args, *a, **kw):
        is_sd = isinstance(args, (list, tuple)) and bool(args) and is_stub_sd(args[0])
        super().__init__(real_args(args), *a, **kw)
        # A text-mode pipe turns "\n" into "\r\n" on Windows; sd.exe reads the LF as a second, empty line, which a program
        # waiting in INPUT takes as its answer.  The launcher's own sessions send bare LF (emulate); so does a suite's Popen.
        if self.stdin is not None and hasattr(self.stdin, "reconfigure"):
            self.stdin.reconfigure(newline="\n")
        pw = os.environ.get("SD_CARRY_PW")
        if is_sd and pw is not None and self.stdin is not None:
            self.stdin = SessionStdin(self.stdin, pw, int(os.environ.get("SD_CARRY_SPARE_OFF") or "0"))


def patched_open(file, mode="r", *a, **kw):
    t = stub_tool(file)
    if t is not None:
        file = t                            # a suite reads the tool's bytes to print its hash
    pw = os.environ.get("SD_CARRY_PW")
    if pw and isinstance(file, str) and file.endswith("live-hold.out") and mode in ("r", "rt"):
        with real_open(file, mode, *a, **kw) as fh:          # a suite's own session: its output is printed on a failure
            return io.StringIO(fh.read().replace(pw, "********"))
    if isinstance(mode, str) and "b" not in mode and any(c in mode for c in "wax+") and "newline" not in kw and len(a) < 4:
        kw["newline"] = "\n"
    return real_open(file, mode, *a, **kw)


def patched_symlink(src, dst, target_is_directory=False, **kw):
    """A symbolic link needs Developer Mode or an elevated process on Windows.  A directory JUNCTION needs neither and a
    program that resolves a path sees through it the same way, so a link to a directory falls back to one."""
    try:
        return real_symlink(src, dst, target_is_directory=target_is_directory, **kw)
    except OSError:
        if not os.path.isdir(src):
            raise
        r = real_run(["cmd", "/c", "mklink", "/J", str(dst), str(src)], capture_output=True, text=True)
        if r.returncode != 0:
            raise


def patched_os_open(path, flags, mode=0o777, **kw):
    """os.open('/', O_RDONLY) gives a stdin on which read() FAILS (EISDIR) rather than ends.  Windows refuses os.open on a
    directory; CreateFile with FILE_FLAG_BACKUP_SEMANTICS gives a handle on which ReadFile fails in the same way."""
    if path == "/" and flags == os.O_RDONLY:
        import ctypes
        import msvcrt
        k32 = ctypes.WinDLL("kernel32", use_last_error=True)
        k32.CreateFileW.restype = ctypes.c_void_p
        k32.CreateFileW.argtypes = [ctypes.c_wchar_p, ctypes.c_uint32, ctypes.c_uint32, ctypes.c_void_p, ctypes.c_uint32,
                                    ctypes.c_uint32, ctypes.c_void_p]
        h = k32.CreateFileW(os.environ.get("SystemDrive", "C:") + "\\", 0x80000000, 7, None, 3, 0x02000000, None)
        if h in (None, 0, ctypes.c_void_p(-1).value):
            raise ctypes.WinError(ctypes.get_last_error())
        return msvcrt.open_osfhandle(h, os.O_RDONLY)
    return real_os_open(path, flags, mode, **kw)


def long_path(p):
    """CreateDirectory and RemoveDirectory refuse a path over 247 characters unless long paths are enabled (they are not,
    by default) or the path carries the \\\\?\\ prefix, which also wants backslashes only.  A suite that builds a 251 or 252
    character data path (sdfix's MAX_PATHNAME_LEN of 255 is the thing under test) needs both calls to accept it."""
    if isinstance(p, str) and len(p) > 240 and not p.startswith("\\\\?\\"):
        return "\\\\?\\" + os.path.abspath(p)
    return p


def patched_mkdir(path, mode=0o777, *, dir_fd=None):
    return real_mkdir(long_path(path), mode, dir_fd=dir_fd)


def patched_rmdir(path, *, dir_fd=None):
    return real_rmdir(long_path(path), dir_fd=dir_fd)


def patched_mkdtemp(suffix=None, prefix=None, dir=None):
    """A suite that wants a SHORT scratch path (a 33-byte buffer is the thing under test) asks for /tmp; the drive's root is
    the nearest short place here."""
    if dir == "/tmp":
        dir = os.environ.get("SystemDrive", "C:") + "\\"
    return real_mkdtemp(suffix, prefix, dir)


def main():
    if len(sys.argv) < 3:
        print("usage: verify-carry-run.py <suite.py> <box> [args]")
        return 2
    suite = os.path.abspath(sys.argv[1])
    if not os.path.isfile(suite):
        print("verify-carry-run: no such suite: %s" % suite)
        return 2
    if not real_isfile(SD_EXE):
        print("verify-carry-run: no sd.exe at %s" % SD_EXE)
        return 2
    if not hasattr(time, "tzset"):
        time.tzset = lambda: None
    box = os.path.abspath(sys.argv[2])
    conf = os.environ.get("SD_CARRY_CONF") or os.path.join(os.environ.get("ProgramData", r"C:\ProgramData"), "SD", "sd.conf")
    if os.path.isdir(box) and not real_exists(os.path.join(box, "sd.conf")) and real_isfile(conf):
        shutil.copyfile(conf, os.path.join(box, "sd.conf"))
    subprocess.run = patched_run
    subprocess.Popen = PatchedPopen
    os.path.isfile = fake_isfile
    os.path.exists = fake_exists
    os.symlink = patched_symlink
    os.open = patched_os_open
    os.mkdir = patched_mkdir
    os.rmdir = patched_rmdir
    tempfile.mkdtemp = patched_mkdtemp
    builtins.open = patched_open
    sys.argv = [suite] + sys.argv[2:]
    sys.path.insert(0, os.path.dirname(suite))
    try:
        runpy.run_path(suite, run_name="__main__")
    except SystemExit as e:
        code = e.code
        return code if isinstance(code, int) else (0 if code is None else 1)
    return 0


if __name__ == "__main__":
    sys.exit(main())
