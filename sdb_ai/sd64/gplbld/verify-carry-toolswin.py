#!/usr/bin/env python3
#
# verify-carry-toolswin.py - Windows-only rows for the stand-alone tools sdidx and sdfix.  NOT a copy of a Linux suite: the
#                            carried verify-carry-tools.py (Linux's sandbox-tools.py, a byte copy) is imported, so its helpers
#                            and its fixture are the ones that suite uses, and these rows are the ones it could not have.
#
#   python verify-carry-run.py verify-carry-toolswin.py <box>        (verify-carry.ps1 -Suite toolswin does this)
#
# START-HISTORY:
# 19 Oct 26  Written for RELEASE_1.1 159.  The docs run of the tools page found three faults that the carried rows passed over,
#            all of them Windows only: the test for a file open in SD compared the path as a string, and NTFS ignores case
#            (a path typed ...\Don\x was not the file SD had recorded as ...\don\x, so sdidx and sdfix ran on a file a
#            session held open); sdidx -m could not create missing parents typed with backslashes (status 1, no message);
#            and a relative index path with a missing parent failed the same way.  Each was red on the build before.
# 23 Oct 26  W15, W16 (RELEASE_1.1 169): sdidx -m onto a drive that does not exist says why (Linux S.70, 0b49d68), as the carried V15-V17
#            cannot on NTFS.  Written, parse-checked, not run.
# END-HISTORY
#
# THE NULL CASES.  The held file is read back through the tools in its EXACT spelling first (a control: the refusal works at
# all), and the other spellings are only believed if that passed.  The data directories are copies under the box and the
# suite refuses to run when it cannot make the fixture.

import importlib.util
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location("carried_tools", os.path.join(HERE, "verify-carry-tools.py"))
T = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(T)

say = T.say
row = T.row


def tool_refuses(name, path, *opts):
    rc, out, to = T.tool(name, *(list(opts) + [path]))
    return rc == 1 and "File is currently open within SD" in out, "%r %r" % (rc, out[-200:])


def open_rows():
    say("\n=== a file open in SD, named in another spelling ====================================================================")
    with open(os.path.join(T.SYSD, "bp", T.HOLD), "w") as fh:
        fh.write(T.PROG_HOLD)
    out = T.sess("BASIC bp %s" % T.HOLD)
    if "Compiled 1 program(s) with no errors" not in out:
        T.bail("the holder program did not compile:\n" + out[-500:])
    live = T.Live()
    try:
        if not live.wait_for("HELD"):
            T.bail("the holder session never opened the file:\n" + live.text()[-500:])
        real = os.path.realpath(T.FIX)
        say("    SD has %s open; its on-disk spelling is %s" % (T.F, real))
        if real.swapcase() == real:
            T.bail("the path has no letters to change the case of; the rows would prove nothing")
        ok, why = tool_refuses("sdidx", real, "-q")
        row("W1 (control) sdidx -q on the exact on-disk spelling is refused", ok, why)
        ok2, why2 = tool_refuses("sdfix", real, "-B")
        row("W2 (control) sdfix on the exact on-disk spelling is refused", ok2, why2)
        if not (ok and ok2):
            T.bail("the exact spelling was not refused, so the other spellings say nothing")
        for tag, spelled in (("every letter's case swapped", real.swapcase()), ("upper case", real.upper()),
                             ("lower case", real.lower())):
            ok, why = tool_refuses("sdidx", spelled, "-q")
            row("W3 sdidx -q, path in %s: refused, the file is open in SD" % tag, ok, why)
            ok, why = tool_refuses("sdidx", spelled, "-d")
            row("W4 sdidx -d, path in %s: refused (it would delete indexes under a session)" % tag, ok, why)
            ok, why = tool_refuses("sdfix", spelled, "-B")
            row("W5 sdfix, path in %s: refused" % tag, ok, why)
            ok, why = tool_refuses("sdfix", spelled, "-B", "-F")
            row("W6 sdfix -F, path in %s: refused (it would repair a file under a session)" % tag, ok, why)
        fwd = real.replace("\\", "/")
        ok, why = tool_refuses("sdfix", fwd, "-B")
        row("W7 sdfix, path with forward slashes: refused", ok, why)
    finally:
        live.release()
    rc, out, to = T.tool("sdfix", "-B", os.path.realpath(T.FIX).upper())
    row("W8 (control) once the session has closed the file, the upper-case spelling is checked: Status: 0",
        rc == 0 and "File is currently open within SD" not in out and "Status: 0" in out, "%r %r" % (rc, out[-200:]))


def path_rows():
    say("\n=== index directories typed the way a person types them on Windows ===================================================")
    d = T.fresh("w-parents")
    x = os.path.join(T.WORK, "w-parents", "a", "b", "idx")
    rc, out, to = T.tool("sdidx", "-m", d, x)
    say("    AFTER  data %r   target %r" % (T.ls(d), T.ls(x)))
    row("W10 -m to a directory whose parents do not exist (backslashes): made, moved, status 0",
        rc == 0 and "Indices have been moved" in out and T.ls(d) == ["%0", "%1"] and T.ls(x) == ["%2"], "%r %r %r" % (rc, T.ls(x), out[-150:]))
    row("W11 ... and -q names it as typed", ("Index directory is " + x) in T.q(d), T.q(d)[-150:])

    d = T.fresh("w-rel")
    rc, out, to = T.tool("sdidx", "-m", d, "w-rel\\p\\q\\idx")
    want = os.path.join(T.WORK, "w-rel", "p", "q", "idx")
    got = T.q(d)
    say("    -q says %s" % got.strip().split("\n")[-1])
    row("W12 -m with a RELATIVE path whose parents do not exist: moved, status 0",
        rc == 0 and "Indices have been moved" in out and T.ls(want) == ["%2"], "%r %r %r" % (rc, T.ls(want), out[-150:]))
    row("W13 ... stored as the Windows path, not /cygdrive/c/... (case aside)",
        ("Index directory is " + want).lower() in got.lower(), got[-200:])

    d = T.fresh("w-slash")
    x = os.path.join(T.WORK, "w-slash", "m", "n", "idx").replace("\\", "/")
    rc, out, to = T.tool("sdidx", "-m", d, x)
    row("W14 -m with forward slashes and missing parents: moved, status 0 (as on Linux)",
        rc == 0 and T.ls(x) == ["%2"], "%r %r" % (rc, out[-150:]))

    # 23 Oct 26, Linux 0b49d68 (S.70).  Linux's V15 makes a directory unwritable with chmod 0555; NTFS ignores that, so the
    # carried rows V15-V17 skip here.  What stops mkdir on Windows is a drive that does not exist.
    free = [c for c in "ZYXWVUTSRQPONMLKJIHGFED" if not os.path.exists(c + ":\\")]
    if not free:
        say("  [SKIP] W15-W16: every drive letter is in use; nothing measured (not counted as a pass)")
    else:
        d = T.fresh("w-nodrive")
        x = free[0] + ":\\sdidx-s70\\idx"
        rc, out, to = T.tool("sdidx", "-m", d, x)
        say("    AFTER  data %r   target %s" % (T.ls(d), x))
        row("W15 -m onto a drive that does not exist: status 1 and 'Cannot create directory <whole target as typed>: <reason>'",
            rc == 1 and ("Cannot create directory " + x + ": ") in out, "%r %r" % (rc, out[-250:]))
        row("W16 ... and nothing was moved: the index is where it was and the header still says so",
            T.ls(d) == ["%0", "%1", "%2"] and "Indices are not relocated" in T.q(d), "%r %r" % (T.ls(d), T.q(d)[-150:]))


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) != 1:
        T.bail("usage: verify-carry-toolswin.py <dir>")
    box = os.path.abspath(args[0])
    T.BOX = box
    T.SYSD = os.path.join(box, "sys")
    T.BIN = os.path.join(T.SYSD, "bin")
    T.WORK = os.path.join(box, "work")
    T.CONF = os.path.join(box, "sd.conf")
    T.FIX = os.path.join(T.SYSD, T.F)
    say("verify-carry-toolswin: sandbox %s" % box)
    for t in ("sdidx", "sdfix"):
        if not os.path.isfile(os.path.join(T.BIN, t)):
            T.bail("%s is not in the sandbox" % t)
    subprocess.run([sys.executable, T.TOOL, box, "start"], capture_output=True, text=True, errors="replace", timeout=120)
    os.makedirs(T.WORK, exist_ok=True)
    made = []
    try:
        with open(os.path.join(T.SYSD, "bp", "zztf" + T.RUN), "w") as fh:
            fh.write(T.PROG_FILL)
        made.append("zztf" + T.RUN)
        out = T.sess("DELETE.FILE %s" % T.F, "CREATE.FILE %s" % T.F, "BASIC bp zztf%s" % T.RUN)
        if "Compiled 1 program(s) with no errors" not in out:
            T.bail("the fixture program did not compile:\n" + out[-500:])
        out = T.sess("RUN bp zztf%s" % T.RUN, "CREATE.INDEX %s CITY" % T.F, "BUILD.INDEX %s CITY" % T.F)
        if "Added index for CITY" not in out or "40 records processed" not in out:
            T.bail("the index was not made and built (40 records):\n" + out[-600:])
        if T.ls(T.FIX) != ["%0", "%1", "%2"]:
            T.bail("the fixture directory is %r, not %%0 %%1 %%2:\n%s" % (T.ls(T.FIX), T.FIX))
        say("    fixture %s holds %r" % (T.FIX, T.ls(T.FIX)))
        path_rows()
        open_rows()
    finally:
        say("\n--- cleanup -------------------------------------------------------------------------------------")
        T.sess("DELETE.FILE %s" % T.F)
        for nm in made + [T.HOLD]:
            for dd in ("bp", "bp.out"):
                pth = os.path.join(T.SYSD, dd, nm)
                if os.path.exists(pth):
                    os.remove(pth)
        T.shutil.rmtree(T.WORK, ignore_errors=True)
        left = [n for n in (T.F, T.F + ".dic") if os.path.exists(os.path.join(T.SYSD, n))]
        row("cleanup: the fixture file is gone", not left, " ".join(left))
    say("\nverify-carry-toolswin: %d passed, %d failed" % (T.passed, T.failed))
    if T.passed + T.failed == 0:
        T.bail("no row ran - a broken test, not a pass")
    return 1 if T.failed else 0


if __name__ == "__main__":
    sys.exit(main())
