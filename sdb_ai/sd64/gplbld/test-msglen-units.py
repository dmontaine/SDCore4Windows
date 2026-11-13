#!/usr/bin/env python3
# test-msglen-units.py - drives check-msglen.py against a copy of the three C
# sources it reads its bound from, one premise changed at a time.  Added
# 14 Sep 2026 when the bound stopped being hard-coded (PRE_RELEASE 11).
#
#   python sdb_ai/sd64/gplbld/test-msglen-units.py
#   (13 Nov 26 Windows port - from Linux b1d496df, RELEASE_1.1 254 F4: with check-msglen.py in Linux's form; case 8 re-anchored.)
#
# No sudo, no install, no sd.  Exit 0 all cases passed, 1 a case failed.
#
# Case 0 is a POSITIVE control: the unchanged copy must derive 231 and pass a
# short message, or every change after it proves nothing.  Every mutation must
# match its source text, or the case fails - an injection that changed nothing
# is not a test.

import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
SD64 = os.path.dirname(HERE)
CHECKER = os.path.join(HERE, "check-msglen.py")
SOURCES = ("sddefs.h", "k_error.c", "messages.c")

BS = chr(92)
SHORT = "line one" + BS + "nline two\n"            # fits: 18 chars
LONG = ("x" * 70 + BS + "n") * 4 + "\n"            # 4 * 72 - 2 = 286 > 231
PLAIN = "no escapes at all\n"

# (name, file, old text, new text, message, expected exit, text the output
#  must carry)
CASES = [
    ("0 control: unchanged source, short message", None, None, None,
     SHORT, 0, "bound           : 231"),
    ("1 control: unchanged source, long message", None, None, None,
     LONG, 1, "fits            : False"),
    ("2 no escapes is a refusal", None, None, None,
     PLAIN, 2, "REFUSED: no escapes"),
    ("3 MAX_EMSG_LEN 100 moves the bound to 291", "sddefs.h",
     "#define MAX_EMSG_LEN 80", "#define MAX_EMSG_LEN 100",
     LONG, 0, "bound           : 291"),
    ("4 MAX_ERROR_LINES 2 moves the bound to 151", "sddefs.h",
     "#define MAX_ERROR_LINES 3", "#define MAX_ERROR_LINES 2",
     SHORT, 0, "bound           : 151"),
    ("5 a longer prefix moves the bound to 230", "k_error.c",
     'sprintf(s, "%08X: ",', 'sprintf(s, "%08X:: ",',
     SHORT, 0, "bound           : 230"),
    ("6 MAX_EMSG_LEN gone is a refusal", "sddefs.h",
     "#define MAX_EMSG_LEN 80", "#define MAX_EMSG_LENGTH 80",
     SHORT, 2, "REFUSED: premise not found in gplsrc/sddefs.h"),
    ("7 buffer declared differently is a refusal", "k_error.c",
     "char s[(MAX_ERROR_LINES * MAX_EMSG_LEN) + 1];",
     "char s[(MAX_ERROR_LINES + MAX_EMSG_LEN) + 1];",
     SHORT, 2, "REFUSED: premise not found in gplsrc/k_error.c"),
    ("8 the D1 fix reverted is a refusal", "k_error.c",
     # 13 Nov 26 Windows: anchored on the call; this tree's k_error.c says "sizeof(s) - n," first in its history comment (line 39).
     "vsnprintf(&(s[n]), sizeof(s) - n,", "vsnprintf(&(s[n]), (MAX_ERROR_LINES + MAX_EMSG_LEN) + 1,",
     SHORT, 2, "REFUSED: premise not found in gplsrc/k_error.c"),
    ("9 backslash-n without the CR is a refusal", "messages.c",
     "*(p+1) = '" + BS + "r';", "*(p+1) = ' ';",
     SHORT, 2, "no longer replaced by LF then CR"),
]


def run_case(name, fname, old, new, message, want_exit, want_text):
    tmp = tempfile.mkdtemp(prefix="msglen-")
    try:
        os.makedirs(os.path.join(tmp, "gplbld"))
        os.makedirs(os.path.join(tmp, "gplsrc"))
        shutil.copy(CHECKER, os.path.join(tmp, "gplbld", "check-msglen.py"))
        for s in SOURCES:
            shutil.copy(os.path.join(SD64, "gplsrc", s),
                        os.path.join(tmp, "gplsrc", s))
        if fname:
            p = os.path.join(tmp, "gplsrc", fname)
            text = open(p, "rb").read().decode("latin-1")
            if old not in text:
                return False, "INJECTION MATCHED NOTHING in %s: %r" % (fname, old)
            open(p, "wb").write(text.replace(old, new, 1).encode("latin-1"))
        msg = os.path.join(tmp, "msg")
        open(msg, "w").write(message)
        cmd = [sys.executable, os.path.join(tmp, "gplbld", "check-msglen.py"), msg]
        r = subprocess.run(cmd, capture_output=True, text=True)
        out = r.stdout + r.stderr
        ok = r.returncode == want_exit and want_text in out
        detail = "exit %d (want %d), %s %r" % (
            r.returncode, want_exit,
            "found" if want_text in out else "MISSING", want_text)
        if not ok:
            detail += "\n      cmd: %s\n      output:\n%s" % (
                " ".join(cmd), "".join("        " + l + "\n"
                                       for l in out.splitlines()))
        return ok, detail
    finally:
        shutil.rmtree(tmp)


print("checker : %s" % CHECKER)
print("sources : %s" % ", ".join(os.path.join(SD64, "gplsrc", s) for s in SOURCES))
failed = 0
for case in CASES:
    ok, detail = run_case(*case)
    print("%s  %s\n      %s" % ("PASS" if ok else "FAIL", case[0], detail))
    failed += 0 if ok else 1
if not CASES:
    print("REFUSED: no cases ran")
    sys.exit(1)
print("test-msglen-units: %d cases, %d failed" % (len(CASES), failed))
sys.exit(1 if failed else 0)
