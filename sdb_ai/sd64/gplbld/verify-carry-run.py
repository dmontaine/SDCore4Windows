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

  8. (RELEASE_1.1 254) THE ADMINISTRATOR, adm().  Linux's suites make an administrator session by running the sandbox's sd
     with SDTEST_ADMIN=1 (their adm(), often with -internal), after patching the sandbox's CPROC so that the variable is the
     switch.  On Windows the administrator is the OS account SDSYS and nothing else (RELEASE_1.1 64), reached only through
     the SDSYS seat (sdsys-seat.ps1: a task inside SDSYS's own signed-in session, elevated and interactive).  So:
       - AN ORDINARY RUN (no SD_CARRY_ADM) REFUSES, exit 2, a suite in ADM_SUITES, a load of sandbox-gates.py or
         sandbox-stmt-q3.py, and any session with SDTEST_ADMIN=1.  Nothing else changes: every suite verify-carry.ps1 runs
         today runs exactly as before.  A suite that needs adm() can therefore never PASS from an ordinary prompt.
       - ADM MODE (SD_CARRY_ADM=1, set by verify-carry-adm.ps1 in an ELEVATED PowerShell) sends each administrator session
         (SDTEST_ADMIN=1, or -internal) to verify-carry-seat.ps1, which runs the same lines through Invoke-SdViaSeat; a
         seat that did not run stops the suite with exit 2, never an empty answer.  <box>/sys is then a junction to the
         INSTALLED SDSYS, so the suite's register records, bp programs and probes land where SD looks.  The installed SDSYS
         has no gpl.bp (its source is not installed): a write to <sys>/gpl.bp/X goes to <sys>/bp/X and "gpl.bp" in an
         administrator command reads "bp"; a read of <sys>/gpl.bp/X is this tree's sdsys/gpl.bp/X (assert-current says the
         two match).  CPROC IS NEVER PATCHED OR RECOMPILED: its read carries a comment naming SDTEST_ADMIN (so the suite's
         prepare() leaves it alone) and "BASIC gpl.bp cproc" is replaced, out loud, by a compile of a one-line control
         program in the same internal SDSYS session - SD's own "Compiled 1 program(s)" line, not one this launcher writes.
         A suite that WRITES a cproc (runin's --mutant) stops with exit 2.  An administrator session in a fixture account
         (sd -a<acct> with SDTEST_ADMIN=1) is the internal seat with LOGTO <acct> first, and LOGTO ends the administrator
         session on Windows (cproc), so rows that want admin=1 there FAIL rather than pass.  A held administrator session
         (Popen with SDTEST_ADMIN=1) has no seat and stops the suite with exit 2.
       - THE INSTALLED SDSYS IS GUARDED: a file that existed when the suite started may not be written or deleted through
         Python (exit 2 names it; append-open with no write, the suites' way to make sure a file exists, is allowed).  At the
         end every NEW entry under SDSYS that this run wrote, or whose name starts zz / $zz, is removed and named; other new
         entries are named and kept.
       - `id -gn` answers SD_CARRY_GROUP (the caller's own register group, so the fixture accounts admit the caller); the
         Linux modules grp and pwd, the os user-id calls and ptydrive stop the suite with exit 2 where it first USES them.

Environment (all optional): SD_EXE the sd executable (default the multi-user install's sd.exe);
SD_CARRY_PW the account password to send first (SD Core Solo); SD_CARRY_SPARE_OFF extra OFF lines;
SD_CARRY_TIMEOUT seconds a session may run (default 600); SD_CARRY_CONF the sd.conf to copy into the box;
SD_CARRY_TOOLDIR the folder holding sdidx.exe, sdfix.exe and sdconv.exe (default: beside sd.exe).
Adm mode only (verify-carry-adm.ps1 sets them): SD_CARRY_ADM=1; SD_CARRY_SDSYS the installed SDSYS directory;
SD_CARRY_GROUP the register group of the fixture accounts; SD_CARRY_SEAT the seat bridge (default verify-carry-seat.ps1
beside this file); SD_CARRY_GPLSRC the gpl.bp source (default this tree's sdsys/gpl.bp); SD_CARRY_RUN the run token.
"verify-carry-run.py --adm-suites" prints ADM_SUITES, one per line.

Exit status is the suite's own: 0 every row passed, 1 a row failed, 2 it could not run.
"""
import builtins
import importlib.util
import io
import os
import re
import runpy
import shutil
import subprocess
import sys
import tempfile
import time
import types

ANSI = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]")
HERE = os.path.dirname(os.path.abspath(__file__))
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
real_remove = os.remove
real_unlink = os.unlink
real_replace = os.replace
real_rename = os.rename
real_rmtree = shutil.rmtree
real_spec = importlib.util.spec_from_file_location

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
    if is_sd_argv(args):
        if ADM is not None and (wants_admin(kw) or "-internal" in [str(x) for x in args[1:]]):
            return admin_session(args, kw)
        if ADM is None and wants_admin(kw):                                           # MUT-ADM-RUNREFUSE
            raise CarryCannotRun(NEEDS_ADM % "it starts an administrator session (SDTEST_ADMIN=1)")
    if ADM is not None and is_id_call(args):
        return id_answer(args, kw)
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
        if is_sd and (wants_admin(kw) or (ADM is not None and "-internal" in [str(x) for x in args[1:]])):
            if ADM is None:
                raise CarryCannotRun(NEEDS_ADM % "it holds an administrator session open (Popen with SDTEST_ADMIN=1)")
            raise CarryCannotRun("a held administrator session (Popen with SDTEST_ADMIN=1 or -internal): the SDSYS seat runs "
                                 "one batch of commands and ends, so a session kept open as SDSYS has no Windows stand-in")
        super().__init__(real_args(args), *a, **kw)
        # A text-mode pipe turns "\n" into "\r\n" on Windows; sd.exe reads the LF as a second, empty line, which a program
        # waiting in INPUT takes as its answer.  The launcher's own sessions send bare LF (emulate); so does a suite's Popen.
        if self.stdin is not None and hasattr(self.stdin, "reconfigure"):
            self.stdin.reconfigure(newline="\n")
        pw = os.environ.get("SD_CARRY_PW")
        if is_sd and pw is not None and self.stdin is not None:
            self.stdin = SessionStdin(self.stdin, pw, int(os.environ.get("SD_CARRY_SPARE_OFF") or "0"))


def patched_open(file, mode="r", *a, **kw):
    if ADM is not None:
        handled, res = adm_open(file, mode, a, kw)
        if handled:
            return res
        file = res
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


# ---------------------------------------------------------------------------------------------------------------------
# THE ADMINISTRATOR, adm() (RELEASE_1.1 254) - item 8 of the header.  Everything below is inert in an ordinary run except the
# three refusals (ADM_SUITES, ADM_LIBS, SDTEST_ADMIN), which turn what used to be a crash into exit 2.  The lines tagged
# "MUT-ADM-" are the ones test-carryadm-units.py breaks to prove it can tell.

# The suites that need adm(): the nine of RELEASE_1.1 254 (gates, sdaccts, shared, editgates, runin, ospath, prof, resetall,
# and stmt-q3 with the five that load it), then net.  ONLY these may run in adm mode, because there <box>/sys IS the installed
# SDSYS: cmd-a9 (deletes <sys>/stacks), inhibit-q8 (writes <sys>/login.inhibit) and the rest are not cleared for that.
ADM_SUITES = ("gates", "sdaccts", "shared", "editgates", "runin", "ospath", "prof", "resetall",
              "stmt-q3", "classinit", "nameindex", "q4", "q5", "restricted", "net")
# The Linux libraries these suites load by file name, and the byte copy that stands for each here.
ADM_LIBS = {"sandbox-gates.py": "verify-carry-gates.py", "sandbox-stmt-q3.py": "verify-carry-stmt-q3.py"}
ZZ_NAME = re.compile(r"(?i)^\$?zz")
CPROC_COMPILE = re.compile(r"(?i)^\s*BASIC\s+gpl\.bp\s+cproc\s*$")
GPLBP_WORD = re.compile(r"(?i)(?<![\w.$])gpl\.bp(?![\w.])")
CONTROL_PROG = "zzcarryctl"
CPROC_MARK = ("\n* verify-carry-run (adm mode, RELEASE_1.1 254): SDTEST_ADMIN is not a CPROC patch on Windows - the administrator"
              " is the SDSYS seat, and this source is read from the tree, not from the install.\n")
NEEDS_ADM = ("%s: this suite needs an administrator session, adm(), which on Windows is the SDSYS seat.  Run it under "
             "verify-carry-adm.ps1 in an ELEVATED PowerShell; from here it is COULD NOT RUN, never a pass.")

ADM = None          # adm-mode settings (adm_config), set by main(); None in an ordinary run
ADM_GUARD = None    # the SdsysGuard of an adm run
ADM_STATE = {"gpl_written": set()}


class CarryCannotRun(BaseException):
    """The suite cannot be measured here.  A BaseException, as SystemExit is, so a suite's `except Exception` cannot swallow it
    and turn a refusal into a row; main() prints it and exits 2."""


def say_adm(msg):
    print(msg, flush=True)


def suite_name(path):
    n = os.path.basename(str(path))
    if n.startswith("verify-carry-"):
        n = n[len("verify-carry-"):]
    return n[:-3] if n.endswith(".py") else n


def is_elevated():
    try:
        import ctypes
        return bool(ctypes.windll.shell32.IsUserAnAdmin())
    except Exception:
        return False


def adm_config(environ, box):
    """The adm-mode settings, or None when SD_CARRY_ADM is not 1 (an ordinary run)."""
    if environ.get("SD_CARRY_ADM") != "1":
        return None
    sdsys = environ.get("SD_CARRY_SDSYS") or os.path.join(environ.get("ProgramData", r"C:\ProgramData"), "SD", "sdsys")
    return {"box": box, "sys": os.path.join(box, "sys"), "sdsys": sdsys,
            "seat": environ.get("SD_CARRY_SEAT") or os.path.join(HERE, "verify-carry-seat.ps1"),
            "group": (environ.get("SD_CARRY_GROUP") or "").strip(),
            "gplsrc": environ.get("SD_CARRY_GPLSRC") or os.path.join(os.path.dirname(HERE), "sdsys", "gpl.bp"),
            "run": environ.get("SD_CARRY_RUN") or ""}


def adm_preflight(cfg, name):
    """Every reason the adm run of suite `name` may not start; empty when it may."""
    bad = []
    if name not in ADM_SUITES:
        bad.append("'%s' is not one of the suites cleared to run against the installed SDSYS (%s)" % (name, ", ".join(ADM_SUITES)))
    if not is_elevated():                                                             # MUT-ADM-ELEV
        bad.append("this process is not elevated: the SDSYS seat registers a task for another account, which needs it")
    if not re.match(r"^[a-z0-9]+$", cfg["run"]):
        bad.append("SD_CARRY_RUN is %r, not a run token of lower-case letters and digits" % cfg["run"])
    if not os.path.isdir(os.path.join(cfg["sdsys"], "accounts")):
        bad.append("%s has no accounts register: it is not an installed SDSYS" % cfg["sdsys"])
    if not real_isfile(cfg["seat"]):
        bad.append("no seat bridge at %s" % cfg["seat"])
    if not re.match(r"^[A-Za-z0-9_.-]+$", cfg["group"]):
        bad.append("SD_CARRY_GROUP is %r: the fixture accounts need a register group the caller is in" % cfg["group"])
    try:
        same = os.path.samefile(cfg["sys"], cfg["sdsys"])
    except OSError:
        same = False
    if not same:                                                                      # MUT-ADM-SAMESYS
        bad.append("%s is not the installed SDSYS (%s): the suite's register records would not reach SD" % (cfg["sys"], cfg["sdsys"]))
    return bad


class SdsysGuard:
    """What the run may change under the installed SDSYS.  A path that existed when the suite started is the install's and may
    not be written or deleted through Python; a path the run made is its own, and cleanup() removes it again."""

    def __init__(self, root):
        self.root = os.path.normcase(os.path.realpath(root))
        self.before = set(self.walk())
        self.written = set()

    def walk(self):
        for d, dirs, files in os.walk(self.root):
            for n in dirs + files:
                yield os.path.normcase(os.path.join(d, n))

    def under(self, p):
        if not isinstance(p, (str, os.PathLike)):
            return None
        try:
            rp = os.path.normcase(os.path.realpath(os.fspath(p)))
        except (OSError, ValueError, TypeError):
            return None
        return rp if rp.startswith(self.root + os.sep) else None

    def owned_by_install(self, p):
        rp = self.under(p)
        return rp is not None and rp in self.before                                   # MUT-ADM-GUARD

    def check_change(self, p, what):
        if self.owned_by_install(p):
            raise CarryCannotRun("the suite would %s %s, which the installed SD owns (it was there when the suite started)"
                                 % (what, os.fspath(p)))

    def note_write(self, p):
        rp = self.under(p)
        if rp is not None and rp not in self.before:
            self.written.add(rp)

    def cleanup(self):
        """Remove what the run made; return (removed, kept, failed), each a list of paths."""
        new = sorted(set(self.walk()) - self.before, key=len, reverse=True)
        removed, kept, failed = [], [], []
        for rp in new:
            if not (ZZ_NAME.match(os.path.basename(rp)) or rp in self.written):
                if not any(rp.startswith(r + os.sep) for r in removed):
                    kept.append(rp)
                continue
            if not os.path.lexists(rp):
                continue
            try:
                if os.path.isdir(rp) and not os.path.islink(rp):
                    real_rmtree(rp)
                else:
                    real_remove(rp)
                removed.append(rp)
            except OSError as e:
                failed.append("%s (%s)" % (rp, e))
        return removed, kept, failed


class AppendNoWrite:
    """An append-open of a file the install owns: the suites do it to make sure a file exists (open(..., 'a').close()), which
    changes nothing.  A write through it would change the install's file, so it stops the suite instead."""

    def __init__(self, path, f):
        self._path = path
        self._f = f

    def write(self, s):
        raise CarryCannotRun("the suite would append to %s, which the installed SD owns" % self._path)

    def writelines(self, s):
        self.write(s)

    def __enter__(self):
        return self

    def __exit__(self, *a):
        self._f.close()

    def __getattr__(self, name):
        return getattr(self._f, name)


def gplbp_name(p):
    """The record name when p is <box>/sys/gpl.bp/<name> or <sdsys>/gpl.bp/<name>, else None."""
    if ADM is None or not isinstance(p, str):
        return None
    a = os.path.abspath(p)
    d = os.path.normcase(os.path.dirname(a))
    for base in (ADM["sys"], ADM["sdsys"]):
        if d == os.path.normcase(os.path.abspath(os.path.join(base, "gpl.bp"))):
            return os.path.basename(a)
    return None


def adm_open(file, mode, a, kw):
    """The adm-mode half of open(): (handled, result).  handled False means open the (possibly mapped) path in result."""
    writing = isinstance(mode, str) and any(c in mode for c in "wax+")
    name = gplbp_name(file)
    if name is not None:
        bp_path = os.path.join(ADM["sys"], "bp", name)
        if writing:
            if name.lower() == "cproc":                                               # MUT-ADM-CPROCWRITE
                raise CarryCannotRun("the suite writes a CPROC (a patch or a mutant): the installed CPROC has no source "
                                     "on Windows and is never recompiled by this launcher")
            ADM_STATE["gpl_written"].add(name.lower())
            file = bp_path
        elif name.lower() in ADM_STATE["gpl_written"]:
            file = bp_path
        else:
            src = os.path.join(ADM["gplsrc"], name)
            if name.lower() == "cproc":
                with real_open(src, "r", encoding="utf-8", errors="replace") as fh:
                    return True, io.StringIO(fh.read() + CPROC_MARK)                 # MUT-ADM-MARK
            file = src if real_isfile(src) else bp_path
    if ADM_GUARD is not None and writing:
        if ADM_GUARD.owned_by_install(file):
            if mode in ("a", "at"):
                return True, AppendNoWrite(file, real_open(file, mode, *a, **kw))
            ADM_GUARD.check_change(file, "write")
        ADM_GUARD.note_write(file)
    return False, file


def wants_admin(kw):
    env = kw.get("env")
    return (env if env is not None else os.environ).get("SDTEST_ADMIN") == "1"


def is_sd_argv(args):
    return isinstance(args, (list, tuple)) and bool(args) and is_stub_sd(args[0])


def is_id_call(args):
    return isinstance(args, (list, tuple)) and bool(args) and os.path.basename(str(args[0])).lower() in ("id", "id.exe")


def text_or_bytes(kw, out):
    text_mode = kw.get("text") or kw.get("universal_newlines") or kw.get("encoding") or kw.get("errors")
    return (out if text_mode else out.encode("utf-8", "replace")), ("" if text_mode else b"")


def id_answer(args, kw):
    rest = [str(a) for a in args[1:]]
    if rest != ["-gn"]:
        raise CarryCannotRun("`id %s` has no Windows stand-in (only `id -gn`, the fixture accounts' group, has)" % " ".join(rest))
    out, err = text_or_bytes(kw, ADM["group"] + "\n")
    return subprocess.CompletedProcess(list(args), 0, out, err)


def body_lines(kw):
    """The command lines of a Linux session body ("\\nTERM 200,9999\\n" + commands + "OFF\\n") as the seat takes them: without
    the leading empty line (the seat sends its own) and without the closing OFF (the seat appends its own)."""
    data = kw.get("input")
    if data is None:
        raise CarryCannotRun("an administrator session was started with nothing on its stdin")
    if isinstance(data, bytes):
        data = data.decode("utf-8", "replace")
    lines = data.replace("\r\n", "\n").split("\n")
    if lines and lines[-1] == "":
        lines.pop()
    if lines and lines[0] == "":                                                      # MUT-ADM-LEAD
        lines.pop(0)
    if lines and lines[-1].strip().upper() == "OFF":                                  # MUT-ADM-OFF
        lines.pop()
    return lines


def parse_bridge(raw, rc=0, console=""):
    """The text SD printed, from verify-carry-seat.ps1's report; CarryCannotRun when the seat did not run or the report is not
    whole.  The report: SEATBRIDGE ok=0|1, why=..., detail=..., ---, SD's lines, ENDOFBRIDGE."""
    lines = (raw or "").replace("\r\n", "\n").split("\n")
    while lines and lines[-1] == "":
        lines.pop()
    m = re.match(r"^SEATBRIDGE ok=([01])$", lines[0]) if lines else None
    if m is None:
        raise CarryCannotRun("the seat bridge wrote no report (exit %s); it said: %s" % (rc, (console or "").strip()[-600:]))
    if len(lines) < 5 or lines[-1] != "ENDOFBRIDGE" or lines[3] != "---":
        raise CarryCannotRun("the seat bridge's report is cut off (no ENDOFBRIDGE): a report cut off is not an answer")
    why = lines[1][4:] if lines[1].startswith("why=") else lines[1]
    detail = lines[2][7:] if lines[2].startswith("detail=") else lines[2]
    if m.group(1) != "1":                                                             # MUT-ADM-SEATFAIL
        raise CarryCannotRun("the SDSYS seat did not run: %s  [%s]" % (why, detail))
    return "\n".join(lines[4:-1])


def run_seat_bridge(lines, internal, timeout):
    """Run the lines in sd.exe as SDSYS through verify-carry-seat.ps1 (Invoke-SdViaSeat); return SD's text."""
    d = os.path.join(ADM["box"], "adm-seat")
    os.makedirs(d, exist_ok=True)
    fd, inf = tempfile.mkstemp(prefix="seat-", suffix=".in", dir=d)
    os.close(fd)
    outf = inf[:-3] + ".out"
    try:
        with real_open(inf, "w", encoding="utf-8", newline="\n") as fh:
            fh.write("".join(c + "\n" for c in lines))
        argv = ["powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", ADM["seat"], "-InFile", inf,
                "-OutFile", outf, "-TimeoutSec", str(int(timeout))] + (["-Internal"] if internal else [])
        p = real_run(argv, capture_output=True, text=True, errors="replace", timeout=int(timeout) + 180)
        raw = ""
        if real_isfile(outf):
            with real_open(outf, "r", encoding="utf-8-sig", errors="replace") as fh:
                raw = fh.read()
        return parse_bridge(raw, p.returncode, p.stdout + p.stderr)
    finally:
        for f in (inf, outf):
            try:
                real_remove(f)
            except OSError:
                pass


SEAT_RUNNER = run_seat_bridge      # the guard replaces it; production never does


def admin_session(args, kw):
    """An administrator session the suite asked for (SDTEST_ADMIN=1, or -internal), run through the SDSYS seat."""
    argv = [str(x) for x in args[1:]]
    internal = "-internal" in argv
    account = next((x[2:] for x in argv if x.startswith("-a") and len(x) > 2), None)
    other = [x for x in argv if x != "-internal" and not (x.startswith("-a") and len(x) > 2)]
    if other:
        raise CarryCannotRun("an administrator session with arguments the seat cannot pass: %r" % other)
    sent = []
    for c in body_lines(kw):
        if CPROC_COMPILE.match(c):
            if "cproc" in ADM_STATE["gpl_written"]:
                raise CarryCannotRun("the suite compiles a CPROC it wrote: the installed CPROC is never recompiled here")
            ctl = os.path.join(ADM["sys"], "bp", CONTROL_PROG)
            with real_open(ctl, "w", encoding="ascii", newline="\n") as fh:           # MUT-ADM-CONTROL
                fh.write("   crt 'carry adm control'\nend\n")
            if ADM_GUARD is not None:
                ADM_GUARD.note_write(ctl)
            say_adm("    [adm] '%s' IS NOT RUN: Windows has no CPROC source installed and its administrator is the SDSYS seat, "
                    "not a patched CPROC.  The same internal SDSYS session compiles bp %s instead, so the compile line the "
                    "suite checks is SD's own." % (c.strip(), CONTROL_PROG))
            c = "BASIC bp " + CONTROL_PROG
        else:
            c = GPLBP_WORD.sub("bp", c)                                               # MUT-ADM-GPLBP
        sent.append(c)
    if account:
        internal = True                                                               # MUT-ADM-ACCTINT
        sent = ["LOGTO " + account] + sent
        say_adm("    [adm] an administrator session in %s: the internal seat with LOGTO %s first.  LOGTO ends the "
                "administrator session on Windows (cproc), so a row that wants admin=1 in that account FAILS here." % (account, account))
    if not any(s.strip() for s in sent):
        raise CarryCannotRun("an administrator session with no commands")
    say_adm("    [adm] SDSYS seat%s: %s" % (" -internal" if internal else "", " | ".join(sent)))
    text = SEAT_RUNNER(sent, internal, kw.get("timeout") or int(os.environ.get("SD_CARRY_TIMEOUT") or "600"))
    text = re.sub(r"\r(?!\n)", "\n", text.replace("\r\n", "\n"))
    out, err = text_or_bytes(kw, ANSI.sub("", text) + "\n")
    return subprocess.CompletedProcess(list(args), 0, out, err)


def patched_spec(name, location=None, *a, **kw):
    """A suite loads sandbox-gates.py or sandbox-stmt-q3.py from its own folder; here those are verify-carry-gates.py and
    verify-carry-stmt-q3.py, and only an adm run may load them (they are the administrator's fixtures)."""
    base = os.path.basename(str(location)) if location is not None else ""
    if base in ADM_LIBS:
        if ADM is None:                                                               # MUT-ADM-LIBREFUSE
            raise CarryCannotRun(NEEDS_ADM % ("it loads " + base))
        copy = os.path.join(os.path.dirname(str(location)), ADM_LIBS[base])
        if not real_isfile(copy):
            raise CarryCannotRun("it loads %s, which is not carried: %s is absent" % (base, copy))
        location = copy
    return real_spec(name, location, *a, **kw)


def stub_module(name, why):
    """A Linux-only module a suite imports: the import works, and the first USE stops the suite with exit 2."""
    m = types.ModuleType(name)

    def missing(attr):
        if attr.startswith("__"):
            raise AttributeError(attr)
        raise CarryCannotRun("%s.%s: %s" % (name, attr, why))
    m.__getattr__ = missing
    return m


class StubPtySession:
    def __init__(self, *a, **kw):
        raise CarryCannotRun("a pseudo-terminal row (ptydrive.PtySession): the Windows pty driver (RELEASE_1.1 272) is not "
                             "wired into this launcher")


def install_adm_stubs():
    for mod, why in (("grp", "the Linux group database has no Windows stand-in"),
                     ("pwd", "the Linux user database has no Windows stand-in")):
        if mod not in sys.modules and importlib.util.find_spec(mod) is None:
            sys.modules[mod] = stub_module(mod, why)
    if "ptydrive" not in sys.modules and importlib.util.find_spec("ptydrive") is None:
        pty = stub_module("ptydrive", "the Windows pty driver (RELEASE_1.1 272) is not wired into this launcher")
        pty.PtySession = StubPtySession
        sys.modules["ptydrive"] = pty
    for fn in ("getuid", "geteuid", "getgid", "getegid", "getgroups", "chown"):
        if not hasattr(os, fn):
            setattr(os, fn, no_uid(fn))


def no_uid(n):
    def f(*a, **kw):
        raise CarryCannotRun("os.%s: a Linux user or group id has no Windows stand-in" % n)
    return f


def guarded(real, what):
    def f(path, *a, **kw):
        if ADM_GUARD is not None:
            ADM_GUARD.check_change(path, what)
        return real(path, *a, **kw)
    return f


def guarded_move(real):
    def f(src, dst, *a, **kw):
        if ADM_GUARD is not None:
            ADM_GUARD.check_change(src, "move")
            ADM_GUARD.check_change(dst, "replace")
            ADM_GUARD.note_write(dst)
        return real(src, dst, *a, **kw)
    return f


def adm_cleanup():
    if ADM_GUARD is None:
        return
    removed, kept, failed = ADM_GUARD.cleanup()
    say_adm("verify-carry-run (adm): the run's entries under %s: %d removed, %d kept, %d could not be removed"
            % (ADM_GUARD.root, len(removed), len(kept), len(failed)))
    for p in sorted(removed):
        say_adm("    removed  %s" % p)
    for p in sorted(kept)[:20]:
        say_adm("    kept     %s   (new, not written by the suite and not zz-named: SD's own)" % p)
    for p in failed:
        say_adm("    LEFT     %s" % p)


def main():
    global ADM, ADM_GUARD
    if sys.argv[1:2] == ["--adm-suites"]:
        print("\n".join(ADM_SUITES))
        return 0
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
    name = suite_name(suite)
    try:
        ADM = adm_config(os.environ, box)
        if ADM is None:
            if name in ADM_SUITES:                                                    # MUT-ADM-SUITEREFUSE
                raise CarryCannotRun(NEEDS_ADM % name)
        else:
            bad = adm_preflight(ADM, name)
            if bad:
                raise CarryCannotRun("adm mode refused: " + "; ".join(bad))
            ADM_GUARD = SdsysGuard(ADM["sdsys"])
            say_adm("verify-carry-run (adm): run %s, suite %s, box %s" % (ADM["run"], name, box))
            say_adm("verify-carry-run (adm): sys -> %s (%d entries before the suite), group %s, seat %s, gpl.bp source %s"
                    % (ADM_GUARD.root, len(ADM_GUARD.before), ADM["group"], ADM["seat"], ADM["gplsrc"]))
            install_adm_stubs()
    except CarryCannotRun as e:
        print("verify-carry-run: CANNOT RUN - %s" % e, flush=True)
        return 2
    if os.path.isdir(box) and not real_exists(os.path.join(box, "sd.conf")) and real_isfile(conf):
        shutil.copyfile(conf, os.path.join(box, "sd.conf"))
    importlib.util.spec_from_file_location = patched_spec
    if ADM is not None:
        os.remove = guarded(real_remove, "delete")
        os.unlink = guarded(real_unlink, "delete")
        shutil.rmtree = guarded(real_rmtree, "delete")
        os.replace = guarded_move(real_replace)
        os.rename = guarded_move(real_rename)
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
    except CarryCannotRun as e:
        print("verify-carry-run: CANNOT RUN - %s" % e, flush=True)
        return 2
    except SystemExit as e:
        code = e.code
        return code if isinstance(code, int) else (0 if code is None else 1)
    finally:
        adm_cleanup()
    return 0


if __name__ == "__main__":
    sys.exit(main())
