#!/usr/bin/env python3
#
# verify-carry-ospathw.py - the public OSPATH() on Windows (RELEASE_1.1 241): a program that is not internal, in an ordinary account
# with the OS switch OFF (the delivered state).  WRITTEN FOR WINDOWS, NOT A COPY of a Linux suite: Linux's sandbox-ospath.py needs
# SDSYS sessions and fixture accounts and is NotRun here (verify-carry-known.psd1).  The half that needs the switch ON is a sitting.
#
#   powershell -ExecutionPolicy Bypass -File <tree>\sdb_ai\sd64\gplbld\verify-carry.ps1 -Suite ospathw      (an ordinary prompt)
#
# It runs under verify-carry-run.py like every carried suite: <box>/sys is the caller's own account directory, the commands go to
# the installed sd.exe, and the suite writes its probe programs into that account's bp and removes them.  Exit 0 every row passed,
# 1 a row failed, 2 it could not run.  The same file is in both Windows trees.
#
# START-HISTORY:
# 12 Nov 26  Written with pub_ospath() (op_dio2.c), the owner's D1 and D2 of 12 Nov 26.  NOT RUN when written.
# 12 Nov 26  First run (verify-carry-20261112-112430): every key row passed; the G rows failed because the account (don) holds OS
#            access (register field 8 yes).  The G rows now read that switch, print it, and check the state it gives: off, refused;
#            on, reached.  An account whose record cannot be found still fails them.
# END-HISTORY
#
# THE INSTRUMENT IS WHAT EACH PROGRAM PRINTS between brackets, with STATUS() after it, and the disk as Python reads it.  Every key
# that changes the disk is checked ON THE DISK, before and after.  A row whose fixture is missing fails; it is never skipped.
#   C  CONTROLS: OSPATH compiles in an ordinary program (it did not before: "Matrix OSPATH is not referenced"); key 2 of a file
#      this script made answers 1 and of a name it did not make answers 0.
#   K  the keys inside the account, given as C:\...\x (backslashes), as C:/.../x, and for 6 in the other case.
#   G  THE GATE, on a folder this script made OUTSIDE the account (in the user's temp folder).  The account's OS switch is read
#      from its register record (field 8, ACC$OS.EXEC) and printed.  Off: key 2 answers 0 with STATUS() ER$PERM, delete leaves the
#      file there, mkdir makes nothing, owner answers null.  On: each is let through.  A record that cannot be found fails the rows.

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
    say("verify-carry-ospathw: CANNOT RUN - " + msg)
    sys.exit(2)


def sess(box, *cmds):
    say("    > %d commands" % len(cmds))
    p = subprocess.run([sys.executable, TOOL, box, "sess", os.path.join(box, "user_accounts")] + list(cmds),
                       capture_output=True, text=True, timeout=900)
    out = ANSI.sub("", p.stdout + p.stderr)
    return out.split(":TERM 200,9999", 1)[-1]


def os_switch(acct):
    """'on' / 'off' from the account's register record (field 8, ACC$OS.EXEC), found as sdsys/accounts/<name> in a folder above
    the account directory (Core: C:/ProgramData/SD; Solo: the Solo folder), or 'unknown'."""
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
    """A BASIC string literal for s (single quotes; a path holds none)."""
    if "'" in s:
        bail("a path holds a single quote: %r" % s)
    return "'" + s + "'"


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) != 1:
        bail("usage: verify-carry-ospathw.py <box>")
    box = os.path.abspath(args[0])
    sysd = os.path.join(box, "sys")
    acct = os.path.realpath(sysd)
    say("verify-carry-ospathw: box %s, account directory %s" % (box, acct))
    if not os.path.isdir(os.path.join(acct, "bp")):
        bail("%s has no bp folder: not an account" % acct)

    work = os.path.join(acct, "zzospw")              # inside the account
    out_dir = tempfile.mkdtemp(prefix="zzospw-out-")  # outside it
    shutil.rmtree(work, ignore_errors=True)
    os.makedirs(os.path.join(work, "tree", "sub"))
    for f in ("f.txt", "del.txt", os.path.join("tree", "sub", "keep.txt")):
        with open(os.path.join(work, f), "w") as h:
            h.write("x\n")
    os.makedirs(os.path.join(work, "empty"))
    with open(os.path.join(out_dir, "o.txt"), "w") as h:
        h.write("x\n")
    wb = work.replace("/", "\\")        # C:\...\zzospw
    wf = work.replace("\\", "/")        # C:/.../zzospw
    ob = out_dir.replace("/", "\\")
    say("  inside %s ; outside %s" % (wb, ob))

    # (id, BASIC expression, what the row is about)
    cases = [
        ("c1", "ospath(%s, 2)" % q(wb + "\\f.txt"), "C1 key 2 of a file the script made"),
        ("c2", "ospath(%s, 2)" % q(wb + "\\nothere.txt"), "C2 key 2 of a name it did not make"),
        ("k0a", "ospath('C:\\a\\b', 0)", "key 0 of C:\\a\\b"),
        ("k0b", "ospath('', 0)", "key 0 of a null name"),
        ("k1a", "ospath('abc.txt', 1)", "key 1 of abc.txt"),
        ("k1b", "ospath('..', 1)", "key 1 of .."),
        ("k1c", "ospath('a\\b', 1)", "key 1 of a\\b"),
        ("k2f", "ospath(%s, 2)" % q(wf + "/f.txt"), "key 2 with forward slashes"),
        ("k3", "ospath(%s, 3)" % q(wb), "key 3 in the work folder"),
        ("k4", "ospath(%s, 4)" % q(wb + "\\f.txt"), "key 4 of the file"),
        ("k5f", "ospath(%s, 5)" % q(wb + "\\del.txt"), "key 5 of a file"),
        ("k5e", "ospath(%s, 5)" % q(wb + "\\empty"), "key 5 of an empty folder"),
        ("k5t", "ospath(%s, 5)" % q(wb + "\\tree"), "key 5 of a tree"),
        ("k7", "ospath(%s, 7)" % q(wb + "\\f.txt"), "key 7 of the file"),
        ("k10", "ospath(%s, 10)" % q(wb + "\\f.txt"), "key 10 of the file"),
        ("k10r", "ospath('C:\\', 10)", "key 10 of C:\\"),
        ("k11", "ospath(%s, 11)" % q(wb + "\\f.txt"), "key 11 (D1)"),
        ("k12", "ospath(%s, 12)" % q(wb + "\\f.txt"), "key 12 (D1)"),
        ("k15", "ospath(%s, 15)" % q(wb + "\\f.txt"), "key 15 (D1)"),
        ("k13", "ospath(%s, 13)" % q(wb + "\\made"), "key 13 makes a folder"),
        ("k14", "ospath(%s, 14)" % q(wb + "\\p\\q\\r"), "key 14 makes a path"),
        ("k16", "ospath(%s, 16)" % q(wb + "\\f.txt"), "key 16 of the file"),
        ("k17", "ospath(%s, 17)" % q(wb + "\\tree"), "key 17 of a folder"),
        ("k18", "ospath(%s, 18)" % q(wb + "\\f.txt"), "key 18 (D2) of the file"),
        ("k99", "ospath(%s, 99)" % q(wb + "\\f.txt"), "an unknown key"),
        ("g2", "ospath(%s, 2)" % q(ob + "\\o.txt"), "G key 2 outside the account"),
        ("g5", "ospath(%s, 5)" % q(ob + "\\o.txt"), "G key 5 outside the account"),
        ("g13", "ospath(%s, 13)" % q(ob + "\\m"), "G key 13 outside the account"),
        ("g18", "ospath(%s, 18)" % q(ob + "\\o.txt"), "G key 18 outside the account"),
    ]
    # Key 6: a file this program has open, named in upper case; and a name that is not open.
    k6 = ("open 'voc' to f else stop 'no voc'\n   p = fileinfo(f, 2)\n   x = ospath(upcase(p), 6)\n   crt 'P6[':p:']'\n"
          "   crt 'R6[':x:'|':status():']'\n   y = ospath(%s, 6)\n   crt 'R6N[':y:'|':status():']'" % q(wb + "\\f.txt"))

    names = []
    cmds = []
    try:
        for i, (cid, expr, _lbl) in enumerate(cases):
            nm = "zzospw%02d" % i
            names.append(nm)
            with open(os.path.join(sysd, "bp", nm), "w") as h:
                h.write("$include err.h\n   x = %s\n   crt 'R%s[':x:'|':status():'|':(status() = ER$PERM):'|':(status() = ER$ARGS):']'\nend\n"
                        % (expr, cid))
            cmds += ["BASIC bp %s" % nm, "RUN bp %s" % nm]
        names.append("zzospw6")
        with open(os.path.join(sysd, "bp", "zzospw6"), "w") as h:
            h.write("   " + k6 + "\nend\n")
        cmds += ["BASIC bp zzospw6", "RUN bp zzospw6"]

        before_del = os.path.exists(os.path.join(work, "del.txt"))
        before_o = os.path.exists(os.path.join(out_dir, "o.txt"))
        out = sess(box, *cmds)
        say("\n--- raw output (every line the programs printed) --------------------------------")
        for ln in out.splitlines():
            if re.match(r"^(R|P)\w*\[", ln.strip()):
                say("    " + ln.strip())

        def got(cid):
            m = re.search(r"(?m)^R%s\[(.*)\]\s*$" % re.escape(cid), out)
            if not m:
                return None
            parts = m.group(1).split("|")
            return parts if len(parts) == 4 else None

        say("\n--- rows ----------------------------------------------------------------------")
        row("C0 OSPATH compiles in an ordinary program", "Matrix OSPATH" not in out and got("c1") is not None,
            "the compiler refused it" if "Matrix OSPATH" in out else "no output")
        g = {cid: got(cid) for cid, _e, _l in cases}

        def val(cid):
            return g[cid][0] if g[cid] else None

        def perm(cid):
            return g[cid][2] == "1" if g[cid] else False

        row("C1 key 2 of a file the script made is 1", val("c1") == "1", "got %r" % g["c1"])
        row("C2 key 2 of a name it did not make is 0", val("c2") == "0", "got %r" % g["c2"])
        row("K0 C:\\a\\b is a valid path name", val("k0a") == "1", "got %r" % g["k0a"])
        row("K0 a null name is not", val("k0b") == "0", "got %r" % g["k0b"])
        row("K1 abc.txt is a valid file name", val("k1a") == "1", "got %r" % g["k1a"])
        row("K1 .. is not", val("k1b") == "0", "got %r" % g["k1b"])
        row("K1 a\\b is not (a separator)", val("k1c") == "0", "got %r" % g["k1c"])
        row("K2 the same file with forward slashes is 1", val("k2f") == "1", "got %r" % g["k2f"])
        u = val("k3")
        row("K3 a unique name is D and seven digits and is not in the folder",
            u is not None and re.fullmatch(r"D\d{7}", u) is not None and not os.path.exists(os.path.join(work, u)), "got %r" % g["k3"])
        f4 = val("k4") or ""
        row("K4 the full path ends with zzospw/f.txt (either separator, any case)",
            f4.replace("\\", "/").lower().endswith("zzospw/f.txt"), "got %r" % f4)
        row("K5 a file is deleted: answer 1, gone from the disk",
            before_del and val("k5f") == "1" and not os.path.exists(os.path.join(work, "del.txt")), "got %r" % g["k5f"])
        row("K5 an empty folder is deleted: answer 1, gone",
            val("k5e") == "1" and not os.path.exists(os.path.join(work, "empty")), "got %r" % g["k5e"])
        row("K5 a tree is NOT deleted: answer 0, its file still there",
            val("k5t") == "0" and os.path.exists(os.path.join(work, "tree", "sub", "keep.txt")), "got %r" % g["k5t"])
        mt = int(os.stat(os.path.join(work, "f.txt")).st_mtime)
        row("K7 the modified time is the file's (within 2 s)", val("k7") is not None and val("k7").lstrip("-").isdigit()
            and abs(int(val("k7")) - mt) <= 2, "got %r, disk %d" % (g["k7"], mt))
        row("K10 the parent of the file ends with zzospw", (val("k10") or "").replace("\\", "/").lower().endswith("zzospw"),
            "got %r" % g["k10"])
        row("K10 the parent of C:\\ is C:/", (val("k10r") or "").upper() in ("C:/", "C:\\"), "got %r" % g["k10r"])
        for cid in ("k11", "k12", "k15"):
            row("K%s is 0 on Windows (D1)" % cid[1:], val(cid) == "0", "got %r" % g[cid])
        row("K13 a folder is made: answer 1, on the disk", val("k13") == "1" and os.path.isdir(os.path.join(work, "made")),
            "got %r" % g["k13"])
        row("K14 a path is made: answer 1, on the disk", val("k14") == "1" and os.path.isdir(os.path.join(work, "p", "q", "r")),
            "got %r" % g["k14"])
        row("K16 the file is a file", val("k16") == "1", "got %r" % g["k16"])
        row("K17 the folder is a folder", val("k17") == "1", "got %r" % g["k17"])
        me = os.environ.get("USERNAME", "")
        row("K18 the owner is a Windows account name, this user's (D2)", bool(val("k18")) and me != "" and
            val("k18").lower().split("+")[-1].split("\\")[-1] == me.lower(), "got %r, USERNAME %r" % (g["k18"], me))
        row("K99 an unknown key answers 0 with STATUS() ER$ARGS", val("k99") == "0" and g["k99"] and g["k99"][3] == "1",
            "got %r" % g["k99"])
        m6 = re.search(r"(?m)^R6\[(.*)\]\s*$", out)
        m6n = re.search(r"(?m)^R6N\[(.*)\]\s*$", out)
        row("K6 the open VOC, named in upper case, is open", m6 is not None and m6.group(1).split("|")[0] == "1",
            "got %r" % (m6.group(1) if m6 else None))
        row("K6 a file that is not open is not", m6n is not None and m6n.group(1).split("|")[0] == "0",
            "got %r" % (m6n.group(1) if m6n else None))

        # The gate rows depend on the account's OS switch, so it is READ, from the account's register record, and printed: field 8
        # (ACC$OS.EXEC) 'yes' is on.  Off: the outside folder is refused.  On: it is reached (the switch is what lets it through).
        # No record found: the rows fail rather than guess (12 Nov 26: the first run was in an account with the switch on).
        osw = os_switch(acct)
        say("  the account's OS switch (register field 8): %s" % osw)
        if osw == "off":
            row("G2 outside the account: answer 0 and STATUS() ER$PERM", val("g2") == "0" and perm("g2"), "got %r" % g["g2"])
            row("G5 outside: the file is NOT deleted (ER$PERM, still on the disk)",
                before_o and perm("g5") and os.path.exists(os.path.join(out_dir, "o.txt")), "got %r" % g["g5"])
            row("G13 outside: nothing is made (ER$PERM, no folder)", perm("g13") and not os.path.exists(os.path.join(out_dir, "m")),
                "got %r" % g["g13"])
            row("G18 outside: the owner is null with ER$PERM", val("g18") == "" and perm("g18"), "got %r" % g["g18"])
        elif osw == "on":
            row("G2 outside, switch on: key 2 answers 1", val("g2") == "1" and not perm("g2"), "got %r" % g["g2"])
            row("G5 outside, switch on: the file is deleted (answer 1, gone)",
                before_o and val("g5") == "1" and not os.path.exists(os.path.join(out_dir, "o.txt")), "got %r" % g["g5"])
            row("G13 outside, switch on: the folder is made", val("g13") == "1" and os.path.isdir(os.path.join(out_dir, "m")),
                "got %r" % g["g13"])
            row("G18 outside, switch on: not refused (the file G5 deleted has no owner, so null)",
                val("g18") == "" and not perm("g18"), "got %r" % g["g18"])
        else:
            for nm in ("G2", "G5", "G13", "G18"):
                row(nm + " the account's OS switch could not be read, so the gate was not measured", False, "no register record")
    finally:
        for nm in names:
            for d in ("bp", "bp.out"):
                pth = os.path.join(sysd, d, nm)
                if os.path.exists(pth):
                    os.remove(pth)
        shutil.rmtree(work, ignore_errors=True)
        shutil.rmtree(out_dir, ignore_errors=True)

    if passed + failed == 0:
        bail("no row ran")
    say("\nverify-carry-ospathw: %d passed, %d failed" % (passed, failed))
    sys.exit(0 if failed == 0 else 1)


if __name__ == "__main__":
    main()
