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

Environment (all optional): SD_EXE the sd executable (default the multi-user install's sd.exe);
SD_CARRY_PW the account password to send first (SD Core Solo); SD_CARRY_SPARE_OFF extra OFF lines;
SD_CARRY_TIMEOUT seconds a session may run (default 600).

Exit status is the suite's own: 0 every row passed, 1 a row failed, 2 it could not run.
"""
import builtins
import os
import re
import runpy
import subprocess
import sys

ANSI = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]")
SD_EXE = os.environ.get("SD_EXE") or os.path.join(os.environ.get("ProgramFiles", r"C:\Program Files"), "SD", "usr", "bin", "sd.exe")
TOOL_NAME = "sandbox-fromtree.py"

real_run = subprocess.run
real_popen = subprocess.Popen
real_isfile = os.path.isfile
real_exists = os.path.exists
real_open = builtins.open


def is_stub_sd(p):
    try:
        n = os.path.normpath(str(p)).replace("\\", "/")
    except Exception:
        return False
    return n.endswith("/sys/bin/sd")


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
    if isinstance(args, (list, tuple)) and args and is_stub_sd(args[0]):
        args = [SD_EXE] + list(args[1:])
    return real_run(args, *a, **kw)


class PatchedPopen(real_popen):
    def __init__(self, args, *a, **kw):
        if isinstance(args, (list, tuple)) and args and is_stub_sd(args[0]):
            args = [SD_EXE] + list(args[1:])
        super().__init__(args, *a, **kw)


def patched_open(file, mode="r", *a, **kw):
    if isinstance(mode, str) and "b" not in mode and any(c in mode for c in "wax+") and "newline" not in kw and len(a) < 4:
        kw["newline"] = "\n"
    return real_open(file, mode, *a, **kw)


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
    subprocess.run = patched_run
    subprocess.Popen = PatchedPopen
    os.path.isfile = lambda p: True if is_stub_sd(p) else real_isfile(p)
    os.path.exists = lambda p: True if is_stub_sd(p) else real_exists(p)
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
