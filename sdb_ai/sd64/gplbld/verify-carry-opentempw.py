#!/usr/bin/env python3
#
# verify-carry-opentempw.py - OPENTEMP on Windows (RELEASE_1.1 251): the file is made, named and DELETED ON CLOSE by Windows code
# (remove_temp_file in op_dio1.c), which is the part of Linux's b9c71c3d that is not identical here.  WRITTEN FOR WINDOWS, NOT A
# COPY of a Linux suite.  The statement's own logic (op_opentemp) is Linux's and is not retested.
#
#   powershell -ExecutionPolicy Bypass -File <tree>\sdb_ai\sd64\gplbld\verify-carry.ps1 -Suite opentempw      (an ordinary prompt)
#
# It runs under verify-carry-run.py like every carried suite: <box>/sys is the caller's own account directory, the commands go to
# the installed sd.exe, and the suite writes its probe programs into that account's bp and removes them.  Exit 0 every row passed,
# 1 a row failed, 2 it could not run.
#
# START-HISTORY:
# 13 Nov 26  Written for RELEASE_1.1 251.
# END-HISTORY
#
# THE INSTRUMENT is what each program prints between brackets (THEN or ELSE taken, STATUS(), FILEINFO's path, OSPATH key 2 before
# and after CLOSE) and the disk as Python reads it AFTER the session.  A row whose fixture is missing fails; it is never skipped.
#   T1  no pathname: made under SYSTEM(38) (TEMPDIR) with SD's generated name, there while open, gone after CLOSE
#   T2  two in one program get two different names, and both are gone after CLOSE
#   T3  a pathname inside the account: made there, holds a record, gone after CLOSE
#   T4  a pathname that already exists: ELSE, and the folder is still there afterwards (never taken over)
#   T5  a pathname OUTSIDE the account, by the account's OS switch (register field 8): off, ELSE with ER$PERM and nothing made;
#       on, made and gone after CLOSE.  T1 and T2 depend on the switch the same way (TEMPDIR is outside the account).

import os
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.path.join(HERE, "sandbox-fromtree.py")
ANSI = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]")
passed = failed = 0


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
    say("verify-carry-opentempw: CANNOT RUN - " + msg)
    sys.exit(2)


def sess(box, *cmds):
    say("    > %d commands" % len(cmds))
    p = subprocess.run([sys.executable, TOOL, box, "sess", os.path.join(box, "user_accounts")] + list(cmds),
                       capture_output=True, text=True, timeout=900)
    out = ANSI.sub("", p.stdout + p.stderr)
    return out.split(":TERM 200,9999", 1)[-1]


def os_switch(acct):
    """'on' / 'off' from the account's register record (field 8, ACC$OS.EXEC), or 'unknown' (as verify-carry-ospathw.py)."""
    name = os.path.basename(acct.rstrip("\\/")).lower()
    d = os.path.dirname(acct.rstrip("\\/"))
    for _ in range(4):
        reg = os.path.join(d, "sdsys", "accounts")
        if os.path.isdir(reg):
            for f in os.listdir(reg):
                if f.lower() == name:
                    with open(os.path.join(reg, f), encoding="latin-1") as h:
                        lines = h.read().replace("\r\n", "\n").split("\n")
                    say("  register record: %s (%d fields)" % (os.path.join(reg, f), len(lines)))
                    return "on" if len(lines) >= 8 and lines[7].strip().lower() == "yes" else "off"
        d = os.path.dirname(d)
    return "unknown"


def q(s):
    if "'" in s:
        bail("a path holds a single quote: %r" % s)
    return "'" + s + "'"


def winpath(p):
    """A path SD printed (C:/x, C:\\x or /cygdrive/c/x) as Windows spells it, for the disk checks."""
    p = p.strip()
    m = re.match(r"^/cygdrive/([a-zA-Z])/(.*)$", p)
    if m:
        p = m.group(1) + ":/" + m.group(2)
    return os.path.normpath(p)


# Each program prints: <id>[taken|status|path|exists before close|exists after close]
PROG = ("$include err.h\n"
        "   taken = 'else'\n"
        "   opentemp %s to f then taken = 'then' else null\n"
        "   st = status()\n"
        "   p = '' ; b = '' ; a = ''\n"
        "   if taken = 'then' then\n"
        "      write 'x' on f, 'r1'\n"
        "      p = fileinfo(f, 2)\n"
        "      b = ospath(p, 2)\n"
        "      close f\n"
        "      a = ospath(p, 2)\n"
        "   end\n"
        "   crt 'R%s[':taken:'|':st:'|':(st = ER$PERM):'|':p:'|':b:'|':a:']'\n"
        "end\n")

PROG2 = ("   opentemp to f1 then t1 = 'then' else t1 = 'else'\n"
         "   opentemp to f2 then t2 = 'then' else t2 = 'else'\n"
         "   p1 = '' ; p2 = ''\n"
         "   if t1 = 'then' then p1 = fileinfo(f1, 2)\n"
         "   if t2 = 'then' then p2 = fileinfo(f2, 2)\n"
         "   if t1 = 'then' then close f1\n"
         "   if t2 = 'then' then close f2\n"
         "   crt 'RT2[':t1:'|':t2:'|':p1:'|':p2:'|':system(38):']'\n"
         "end\n")


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) != 1:
        bail("usage: verify-carry-opentempw.py <box>")
    box = os.path.abspath(args[0])
    sysd = os.path.join(box, "sys")
    acct = os.path.realpath(sysd)
    say("verify-carry-opentempw: box %s, account directory %s" % (box, acct))
    if not os.path.isdir(os.path.join(acct, "bp")):
        bail("%s has no bp folder: not an account" % acct)

    inside = os.path.join(acct, "zzotw.tmp")
    exists = os.path.join(acct, "zzotw.exists")
    out_dir = tempfile.mkdtemp(prefix="zzotw-out-")
    outside = os.path.join(out_dir, "o.tmp")
    shutil.rmtree(inside, ignore_errors=True)
    shutil.rmtree(exists, ignore_errors=True)
    os.makedirs(exists)
    with open(os.path.join(exists, "keep.txt"), "w") as h:
        h.write("x\n")
    say("  inside %s ; existing %s ; outside %s" % (inside, exists, outside))

    cases = [("t1", ""), ("t3", q(inside.replace("/", "\\"))), ("t4", q(exists.replace("/", "\\"))),
             ("t5", q(outside.replace("/", "\\")))]
    names = []
    cmds = []
    try:
        for i, (cid, arg) in enumerate(cases):
            nm = "zzotw%d" % i
            names.append(nm)
            with open(os.path.join(sysd, "bp", nm), "w") as h:
                h.write(PROG % (arg, cid))
            cmds += ["BASIC bp %s" % nm, "RUN bp %s" % nm]
        names.append("zzotwb")     # not zzotw<n>: the cases above take zzotw0 to zzotw3 (the first run overwrote T4's program)
        with open(os.path.join(sysd, "bp", "zzotwb"), "w") as h:
            h.write(PROG2)
        cmds += ["BASIC bp zzotwb", "RUN bp zzotwb"]

        out = sess(box, *cmds)
        say("\n--- raw output (every line the programs printed) --------------------------------")
        for ln in out.splitlines():
            if re.match(r"^R\w+\[", ln.strip()):
                say("    " + ln.strip())

        def got(cid, n):
            m = re.search(r"(?m)^R%s\[(.*)\]\s*$" % re.escape(cid), out)
            if not m:
                return None
            parts = m.group(1).split("|")
            return parts if len(parts) == n else None

        g = {cid: got(cid, 6) for cid, _a in cases}
        t2 = got("T2", 5)
        osw = os_switch(acct)
        say("  the account's OS switch (register field 8): %s" % osw)
        say("\n--- rows ----------------------------------------------------------------------")
        row("C0 the probe programs compiled and ran (every result line is there)",
            all(g[c] is not None for c, _a in cases) and t2 is not None,
            "missing: %s" % ([c for c, _a in cases if g[c] is None] + ([] if t2 else ["T2"])))

        def made_and_gone(cid):
            r = g[cid]
            return r is not None and r[0] == "then" and r[3] != "" and r[4] == "1" and r[5] == "0" \
                and not os.path.exists(winpath(r[3]))

        # T3: inside the account is allowed whatever the switch
        r = g["t3"]
        row("T3 a pathname inside the account: THEN, there while open, OSPATH says gone after CLOSE, and gone from the disk",
            made_and_gone("t3"), "got %r" % (r,))
        row("T3 its path is the one asked for", r is not None and r[3] != "" and
            os.path.normcase(winpath(r[3])) == os.path.normcase(os.path.normpath(inside)), "got %r, asked %r" % (r and r[3], inside))
        r = g["t4"]
        row("T4 a pathname that already exists: ELSE, and the folder and its file are still there",
            r is not None and r[0] == "else" and os.path.exists(os.path.join(exists, "keep.txt")), "got %r" % (r,))

        if osw == "on":
            r = g["t1"]
            tdir = winpath(t2[4]) if t2 else ""
            row("T1 no pathname: THEN, made under SYSTEM(38) with a name holding 'sdtmp', there while open, gone after CLOSE",
                made_and_gone("t1") and tdir != "" and os.path.normcase(winpath(r[3])).startswith(os.path.normcase(tdir))
                and "sdtmp" in os.path.basename(winpath(r[3])), "got %r, SYSTEM(38) %r" % (r, t2 and t2[4]))
            row("T2 two in one program: both THEN, two different names, both gone after CLOSE",
                t2 is not None and t2[0] == "then" and t2[1] == "then" and t2[2] != "" and t2[2] != t2[3]
                and not os.path.exists(winpath(t2[2])) and not os.path.exists(winpath(t2[3])), "got %r" % (t2,))
            row("T5 outside the account, switch on: made there and gone after CLOSE", made_and_gone("t5"), "got %r" % (g["t5"],))
        elif osw == "off":
            for cid, nm in (("t1", "T1 no pathname (TEMPDIR is outside the account)"), ("t5", "T5 a pathname outside the account")):
                r = g[cid]
                row(nm + ", switch off: ELSE with STATUS() ER$PERM", r is not None and r[0] == "else" and r[2] == "1",
                    "got %r" % (r,))
            row("T5 switch off: nothing was made outside", not os.path.exists(outside), "exists: %s" % os.path.exists(outside))
            row("T2 switch off: both ELSE", t2 is not None and t2[0] == "else" and t2[1] == "else", "got %r" % (t2,))
        else:
            for nm in ("T1", "T2", "T5"):
                row(nm + " the account's OS switch could not be read, so the gate was not measured", False, "no register record")
    finally:
        for nm in names:
            for d in ("bp", "bp.out"):
                pth = os.path.join(sysd, d, nm)
                if os.path.exists(pth):
                    os.remove(pth)
        shutil.rmtree(inside, ignore_errors=True)
        shutil.rmtree(exists, ignore_errors=True)
        shutil.rmtree(out_dir, ignore_errors=True)

    if passed + failed == 0:
        bail("no row ran")
    say("\nverify-carry-opentempw: %d passed, %d failed" % (passed, failed))
    sys.exit(0 if failed == 0 else 1)


if __name__ == "__main__":
    main()
