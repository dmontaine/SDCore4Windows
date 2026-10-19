"""The pieces of verify-carry-run.py that stand in for Linux mechanisms must do what the suites rely on.

WHY THIS EXISTS.  19 Oct 2026 (RELEASE_1.1 159).  Linux's sandbox-tools.py runs the stand-alone tools sdidx, sdfix and
sdconv on scratch copies of a hashed file, keeps a session open to hold a file, builds directories of 251 and 252
characters, links a directory, and starts a program whose stdin FAILS.  Windows has none of those as Linux has them, and
the launcher (verify-carry-run.py) supplies each one without editing the suite.  A wrong stand-in does not fail loudly:
a link that is a copy, a stdin that ends instead of failing, a tool that is not the installed one, or a session that
never receives SD Core Solo's password gives rows that pass or hang for the wrong reason.  SD Core Solo's half (the
password and the spare OFF lines, SessionStdin) cannot be run without the owner's password, so it is exercised here.

Pure Python: no SD, no install, no elevation.  Identical in both Windows trees.  An optional argument names another copy
of the launcher, which is how a mutant is tried without touching the live file.

  python gplbld/test-carryrun-units.py [launcher.py]

MUTANT-TESTED 19 Oct 2026: seven copies of the launcher, each with one fault (no password, no tool mapping, the long-path
threshold moved, no directory handle, spare OFF lines added twice, a missing tool reported present, no short /tmp) all
went red, the live launcher stayed green and was byte-identical (SHA-256) afterwards.

Exit 0 all checks passed, 1 a check failed, 2 the launcher is not there to read.
"""

import importlib.util
import os
import shutil
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
LAUNCHER = os.path.abspath(sys.argv[1]) if len(sys.argv) > 1 else os.path.join(HERE, "verify-carry-run.py")

failures = 0
passes = 0


def check(label, ok, detail=""):
    global failures, passes
    if ok:
        passes += 1
        print("  [PASS] " + label)
    else:
        failures += 1
        print("  [FAIL] " + label + ("   <- " + str(detail) if detail else ""))


def load():
    if not os.path.isfile(LAUNCHER):
        print("test-carryrun-units: no launcher at %s" % LAUNCHER)
        sys.exit(2)
    spec = importlib.util.spec_from_file_location("vcr_under_test", LAUNCHER)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def main():
    if sys.platform != "win32":
        print("test-carryrun-units: Windows only")
        return 2
    print("test-carryrun-units: launcher %s" % LAUNCHER)
    vcr = load()
    scratch = tempfile.mkdtemp(prefix="vcrunits")
    try:
        # --- the tools -------------------------------------------------------------------------------------------
        print("\n--- <box>/sys/bin/<tool> is the installed exe ------------------------------------------------------")
        vcr.TOOL_DIR = os.path.join(scratch, "tools")
        os.makedirs(vcr.TOOL_DIR)
        for t in ("sdidx", "sdfix", "sdconv"):
            with open(os.path.join(vcr.TOOL_DIR, t + ".exe"), "wb") as fh:
                fh.write(b"MZ")
        box = os.path.join(scratch, "box")
        for t in ("sdidx", "sdfix", "sdconv"):
            want = os.path.join(vcr.TOOL_DIR, t + ".exe")
            check("U1 %s: a box path maps to %s" % (t, want), vcr.stub_tool(os.path.join(box, "sys", "bin", t)) == want,
                  vcr.stub_tool(os.path.join(box, "sys", "bin", t)))
        check("U2 the stand-in sd is not a tool", vcr.stub_tool(os.path.join(box, "sys", "bin", "sd")) is None)
        check("U3 some other path is not a tool", vcr.stub_tool(os.path.join(box, "sys", "bin", "sdwind")) is None
              and vcr.stub_tool(os.path.join(box, "work", "sdidx")) is None)
        check("U4 a value that is not a path is not a tool", vcr.stub_tool(7) is None and vcr.stub_tool(None) is None)
        check("U5 isfile: a tool that is there is a file", vcr.fake_isfile(os.path.join(box, "sys", "bin", "sdfix")) is True)
        os.remove(os.path.join(vcr.TOOL_DIR, "sdfix.exe"))
        check("U6 NULL CASE: a tool that is NOT there is not a file (a missing tool is reported, not invented)",
              vcr.fake_isfile(os.path.join(box, "sys", "bin", "sdfix")) is False and vcr.fake_exists(os.path.join(box, "sys", "bin", "sdfix")) is False)
        check("U7 the stand-in sd is a file without being there", vcr.fake_isfile(os.path.join(box, "sys", "bin", "sd")) is True)
        a = vcr.real_args([os.path.join(box, "sys", "bin", "sdidx"), "-q", "x"])
        check("U8 a call of a tool becomes a call of the exe, arguments kept", a == [os.path.join(vcr.TOOL_DIR, "sdidx.exe"), "-q", "x"], a)
        a = vcr.real_args([os.path.join(box, "sys", "bin", "sd"), "-status"])
        check("U9 a call of the stand-in sd becomes a call of sd.exe", a == [vcr.SD_EXE, "-status"], a)
        check("U10 any other call is left alone", vcr.real_args(["python", "x"]) == ["python", "x"])

        # --- long directories ------------------------------------------------------------------------------------
        print("\n--- a directory path over 247 characters ---------------------------------------------------------")
        short = "C:\\a\\b"
        check("U11 a short path is left as it is", vcr.long_path(short) == short)
        longp = scratch + "\\" + "d" * 250
        got = vcr.long_path(longp.replace("\\", "/"))
        check("U12 a long one takes the \\\\?\\ prefix, once, with backslashes only",
              got.startswith("\\\\?\\") and "/" not in got and vcr.long_path(got) == got, got[:40])
        made = vcr.long_path(scratch + "\\" + "e" * 120 + "\\" + "f" * 120)
        os.makedirs(made)
        check("U13 CONTROL: a directory of 250+ characters can be created through the prefixed path",
              os.path.isdir(made), made[:60])

        # --- the short scratch place, the failing stdin, the link ------------------------------------------------
        print("\n--- /tmp, a stdin that fails, a directory link ----------------------------------------------------")
        d = vcr.patched_mkdtemp(prefix="sdt", dir="/tmp")
        try:
            check("U14 mkdtemp(dir='/tmp') is a SHORT path on the system drive (sandbox-tools tests a 33-byte buffer)",
                  len(d) + 6 <= 32 and d.upper().startswith(os.environ.get("SystemDrive", "C:").upper() + "\\"), d)
        finally:
            shutil.rmtree(d, ignore_errors=True)
        d2 = vcr.patched_mkdtemp(prefix="vcr", dir=scratch)
        check("U15 any other dir is passed through", os.path.dirname(d2) == scratch, d2)
        fd = vcr.patched_os_open("/", os.O_RDONLY)
        try:
            outcome = "?"
            try:
                data = os.read(fd, 1)
                outcome = "data" if data else "end of input"
            except OSError:
                outcome = "error"
        finally:
            os.close(fd)
        check("U16 os.open('/') is a handle whose read FAILS (neither data nor the end of input)", outcome == "error", outcome)
        target = os.path.join(scratch, "target")
        os.makedirs(target)
        with open(os.path.join(target, "inside"), "w") as fh:
            fh.write("x")
        link = os.path.join(scratch, "link")
        vcr.real_symlink = lambda *a, **k: (_ for _ in ()).throw(OSError("symbolic links refused"))
        vcr.patched_symlink(target, link)
        check("U17 a directory link that a symbolic link would be refused for becomes a junction that shows the directory",
              os.path.isdir(link) and os.path.exists(os.path.join(link, "inside")), os.listdir(scratch))
        os.rmdir(link)
        check("U18 ... and removing the link leaves the directory's contents", os.path.exists(os.path.join(target, "inside")))
        try:
            vcr.patched_symlink(os.path.join(scratch, "no-such-dir"), os.path.join(scratch, "l2"))
            refused = False
        except OSError:
            refused = True
        check("U19 NULL CASE: a link to something that is not a directory is refused, not faked", refused)

        # --- SD Core Solo: the password and the spare OFF --------------------------------------------------------
        print("\n--- a session the suite starts itself, for SD Core Solo -------------------------------------------")
        rec = []     # a recording stream: io.StringIO.close() would discard what was written

        class Rec:
            def write(self, x):
                rec.append(x)
                return len(x)

            def flush(self):
                pass

            def close(self):
                rec.append("<closed>")

        s = vcr.SessionStdin(Rec(), "pw-1", 2)
        s.write("\nTERM 200,9999\nRUN bp HOLD\n")
        s.write("\nOFF\n")
        s.close()
        s.close()
        text = "".join(rec)
        check("U20 the password goes first, in front of the suite's LF: what emulate() sends",
              text.startswith("pw-1\nTERM 200,9999\nRUN bp HOLD\n"), repr(text))
        check("U21 the suite's own later writes are unchanged", "\nOFF\n" in text)
        check("U22 the spare OFF lines go in once, at the close, after everything else, and then the stream closes",
              text.endswith("\nOFF\nOFF\nOFF\n<closed><closed>") or text.endswith("\nOFF\nOFF\nOFF\n<closed>"), repr(text[-40:]))
        check("U23 NULL CASE: closing twice does not add the spare lines twice", text.count("OFF\n") == 3, repr(text))
        rec.clear()
        s = vcr.SessionStdin(Rec(), "pw-2", 0)
        s.write("TERM 200,9999\n")
        s.close()
        text = "".join(rec)
        check("U24 a first write with no leading LF still gets the password on a line of its own; no spare lines when none asked",
              text == "pw-2\nTERM 200,9999\n<closed>", repr(text))
    finally:
        # junctions were removed above; nothing under scratch is a link now
        shutil.rmtree("\\\\?\\" + scratch, ignore_errors=True)

    print("\ntest-carryrun-units: %d passed, %d failed" % (passes, failures))
    if passes == 0:
        print("test-carryrun-units: no check ran - a broken test, not a pass")
        return 2
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
