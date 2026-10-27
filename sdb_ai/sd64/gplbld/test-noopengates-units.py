#!/usr/bin/env python3
"""test-noopengates-units.py - the installer has no way to open an access gate (owner, 26 Oct 2026, via Linux 945e766: "keep it closed").

  python gplbld/test-noopengates-units.py

FREE CHECK: no install, no sd, no administrator.  Exit 0 every check passed, 1 a check failed, 2 it could not run.

The installing user's account starts with every access gate closed, like every account SD makes.  The task "opengates", the switch
attach-account.ps1 -OpenGates, its result line and its exit code 4 were removed on 26 Oct 2026 (RELEASE_1.1 180); this guard reads the three
files that carried them and fails if one comes back.  A gate is opened afterwards with modify.account, a word at a time.
"""

import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
FILES = {
    "sd.iss": os.path.join(HERE, "sd.iss"),
    "attach-account.ps1": os.path.join(HERE, "attach-account.ps1"),
}


def code_lines(text, comment_prefixes):
    out = []
    for ln in text.splitlines():
        s = ln.strip()
        if any(s.startswith(p) for p in comment_prefixes):
            continue
        out.append(ln)
    return "\n".join(out)


def main():
    for p in FILES.values():
        if not os.path.isfile(p):
            print("test-noopengates-units: CANNOT RUN - %s is not readable" % p, file=sys.stderr)
            return 2
    iss = open(FILES["sd.iss"], encoding="utf-8", errors="replace").read()
    att = open(FILES["attach-account.ps1"], encoding="utf-8", errors="replace").read()
    iss_code = code_lines(iss, (";", "{", "(*"))
    att_code = code_lines(att, ("#",))
    rows = [
        ("sd.iss has no task named opengates", re.search(r'^Name:\s*"opengates"', iss, re.M) is None),
        ("sd.iss never asks WizardIsTaskSelected('opengates')", "WizardIsTaskSelected('opengates')" not in iss_code),
        ("sd.iss never passes -OpenGates to attach-account.ps1", "-OpenGates" not in iss_code),
        ("sd.iss keeps no OpenGatesMsg", "OpenGatesMsg" not in iss_code),
        ("attach-account.ps1 has no -OpenGates switch", re.search(r"\[switch\]\s*\$OpenGates", att_code) is None),
        ("attach-account.ps1 has no Open-InstallerGates", "Open-InstallerGates" not in att_code),
        ("attach-account.ps1 never ends with exit code 4 for gates", "$result = 4" not in att_code),
    ]
    bad = 0
    for name, ok in rows:
        bad += 0 if ok else 1
        print("  [%s] %s" % ("PASS" if ok else "FAIL", name))
    print("\ntest-noopengates-units: %d checks, %d failed" % (len(rows), bad))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
