"""The second command name for this product is a launcher that cannot reach another install.

WHY THIS EXISTS.  Owner's ruling, 1 Oct 2026: "sd" and "sd-full" start the FULL
SD Core for Windows when both it and SD Core Solo are installed, "sd-solo" starts
Solo, and with one installed "sd" starts that one.  This product's second name,
sd-full, is a one-line text launcher beside its own sd.exe (no binary: this
repository ships none).  Three things make it safe and each is easy to lose in a
tidy-up:

  1. it runs the sd.exe BESIDE ITSELF ("%~dp0sd.exe"), never one found on the PATH -
     a launcher that searched would start Solo's sd.exe from the full product's name;
  2. it passes the arguments through (%*), or "sd-full WHERE" would run "sd" with none;
  3. it returns the program's exit code, or a script calling it sees success on failure.

And stage.py has to ship it into usr\\bin beside sd.exe (which is also what puts it on
the PATH), or the name does not exist on an installed system.

A source check: no install, no SD, no elevation.  The mutants run on synthetic text.
The behaviour (arguments, exit codes, a folder with a space in it, by name through
cmd.exe) was measured with a stand-in program on 1 Oct 2026 and is repeated by hand at
a cycle; this keeps the text from drifting between cycles.

  python gplbld/test-launcher-units.py

Exit 0 all checks passed, 1 a check failed, 2 the tree is not there to read.
"""

import os
import re
import sys

# THIS PRODUCT.  The Solo tree's copy of this file names sd-solo.
PRODUCT = "SD Core for Windows"
LAUNCHER = "sd-full.cmd"

HERE = os.path.dirname(os.path.abspath(__file__))

failures = 0
passes = 0


def check(label, ok, detail=""):
    global failures, passes
    if ok:
        passes += 1
        print("  [PASS] " + label)
    else:
        failures += 1
        print("  [FAIL] " + label + ("  " + detail if detail else ""))


def read(name):
    p = os.path.join(HERE, name)
    if not os.path.isfile(p):
        return None
    with open(p, "rb") as f:
        return f.read().decode("latin-1").replace("\r\n", "\n")


def code_lines(t):
    """The launcher's lines that are not comments, echo-off or blank."""
    out = []
    for line in t.split("\n"):
        s = line.strip()
        if not s or s.lower().startswith("rem") or s.lower() == "@echo off":
            continue
        out.append(s)
    return out


def launcher_problems(t):
    bad = []
    lines = code_lines(t)
    if lines[:1] != ['"%~dp0sd.exe" %*']:
        bad.append("the first command is %r, want the sd.exe beside the launcher with the arguments passed" % (lines[:1],))
    if lines[1:] != ["exit /b %ERRORLEVEL%"]:
        bad.append("what follows is %r, want the program's exit code returned" % (lines[1:],))
    return bad


def stage_problems(t, name):
    # shipped beside sd.exe, from this directory, and a missing file is a build failure
    if not re.search(r"os\.path\.join\(pfbin,\s*'%s'\)" % re.escape(name), t):
        return ["stage.py does not copy %s into usr\\bin beside sd.exe" % name]
    if not re.search(r"os\.path\.join\(here,\s*'%s'\)" % re.escape(name), t):
        return ["stage.py does not read %s from gplbld" % name]
    if not re.search(r"raise SystemExit\('missing %%s - the %s command" % re.escape(name[:-4]), t):
        return ["stage.py no longer refuses a build whose %s is missing" % name]
    return []


print("test-launcher-units: %s, launcher %s" % (PRODUCT, LAUNCHER))
text = read(LAUNCHER)
stage = read("stage.py")
if text is None or stage is None:
    print("test-launcher-units: %s or stage.py not found - nothing measured." % LAUNCHER)
    sys.exit(2)

check("CONTROL: the launcher has code lines to check", len(code_lines(text)) >= 2)
p = launcher_problems(text)
check("the launcher runs the sd.exe beside itself, passes the arguments and returns the exit code", p == [], "; ".join(p))
s = stage_problems(stage, LAUNCHER)
check("stage.py ships the launcher into usr\\bin and refuses a build without it", s == [], "; ".join(s))
check("the launcher is plain ASCII (cmd.exe reads it in the console's code page)", all(ord(c) < 128 for c in text))
check("the launcher does not search the PATH for sd (no 'where', no bare sd call)",
      not re.search(r"(?im)^\s*(where|sd(\.exe)?)\b", "\n".join(code_lines(text))))

# MUTANTS, on synthetic text: each is a plausible tidy-up.
good = '@echo off\n"%~dp0sd.exe" %*\nexit /b %ERRORLEVEL%\n'
check("CONTROL: correct synthetic text passes", launcher_problems(good) == [])
check("MUTANT: sd.exe found on the PATH instead of beside the launcher is caught",
      launcher_problems('@echo off\nsd.exe %*\nexit /b %ERRORLEVEL%\n') != [])
check("MUTANT: arguments not passed is caught",
      launcher_problems('@echo off\n"%~dp0sd.exe"\nexit /b %ERRORLEVEL%\n') != [])
check("MUTANT: exit code dropped is caught",
      launcher_problems('@echo off\n"%~dp0sd.exe" %*\n') != [])
check("MUTANT: a stage.py that no longer copies the launcher is caught",
      stage_problems("src = os.path.join(here, 'sd-full.cmd')\n", LAUNCHER) != [])

print("")
if passes == 0:
    print("test-launcher-units: VOID - no check ran.")
    sys.exit(2)
if failures:
    print("test-launcher-units: %d passed, %d failed." % (passes, failures))
    sys.exit(1)
print("test-launcher-units: %d passed, 0 failed." % passes)
sys.exit(0)
