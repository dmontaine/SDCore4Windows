#!/usr/bin/env python3
#
# verify-carry-objtrust.py - an object's own HDR_INTERNAL bit is not trusted from an account's bp.out (SOLO 58; SD Core's S.64
# part 2, object.c load_object(): the bit stands only for an object from the global catalogue or an administrator's session).
# WRITTEN FOR WINDOWS from Linux's sandbox-editgates.py objtrust_section(), which compiles an $internal program as the
# administrator; here the suite cannot be the administrator (that takes the password), so it FORGES the bit into the header of an
# ordinary program's object on the disk instead - the attack the rule exists for.
#
#   powershell -ExecutionPolicy Bypass -File <tree>\sdb_ai\sd64\gplbld\verify-carry.ps1 -Suite objtrust      (an ordinary prompt)
#
# It runs under verify-carry-run.py like every carried suite: <box>/sys is the caller's own account directory, the commands go to
# the installed sd.exe, and the suite writes its probe program into that account's bp and removes it.  Exit 0 every row passed,
# 1 a row failed, 2 it could not run.  The same file is in both Windows trees.
#
# START-HISTORY:
# 12 Nov 26  Written for SOLO 58 (Solo) and carried to Core (same rule, S.64 part 2).  NOT RUN when written.
# END-HISTORY
#
# THE GATE IT USES: the account's OS switch (register field 8).  OFF (the delivered state): an ordinary program's OSPATH(path, 2)
# on a file OUTSIDE the account answers 0 with STATUS() ER$PERM; a program run as internal skips that gate and answers 1.  So:
#   C1  the program, compiled plainly into bp.out, is refused (the baseline: the gate is shut for this account)
#   F1  the object's flags word (byte 28, little endian, header.h hdr.flags = 29) has bit 0x0002 set after the forge, read back
#   T1  the forged object, run as the ordinary user, is STILL refused: the bit was not trusted
# With the switch ON the gate is open for everyone and the rows prove nothing: they FAIL and say so (the null case is refused).
# NOT IN THIS SUITE: the positive control (the same forged object run by the administrator answers 1) - it needs the administrator's
# password; a sitting can run it by hand.

import os
import re
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.path.join(HERE, "sandbox-fromtree.py")
ANSI = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]")
FLAGS_AT = 28          # header.h: hdr.flags = 29 (1-based); checked against installed objects 12 Nov 26
HDR_INTERNAL = 0x0002
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
    say("verify-carry-objtrust: CANNOT RUN - " + msg)
    sys.exit(2)


def sess(box, *cmds):
    say("    > " + " ; ".join(cmds))
    p = subprocess.run([sys.executable, TOOL, box, "sess", os.path.join(box, "user_accounts")] + list(cmds),
                       capture_output=True, text=True, timeout=900)
    out = ANSI.sub("", p.stdout + p.stderr)
    return out.split(":TERM 200,9999", 1)[-1]


def os_switch(acct):
    """'on' / 'off' from the account's register record (field 8), as verify-carry-ospathw.py reads it, or 'unknown'."""
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


def answer(out):
    """The program prints 'ZOT[<answer>|<status>]'; returns (answer, status) or None."""
    m = re.search(r"ZOT\[([^|\]]*)\|([^\]]*)\]", out)
    return (m.group(1), m.group(2)) if m else None


def flags_of(path):
    with open(path, "rb") as h:
        b = h.read(FLAGS_AT + 2)
    if len(b) < FLAGS_AT + 2 or b[0] not in (100, 101):
        return None
    return b[FLAGS_AT] | (b[FLAGS_AT + 1] << 8)


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) != 1:
        bail("usage: verify-carry-objtrust.py <box>")
    box = os.path.abspath(args[0])
    acct = os.path.realpath(os.path.join(box, "sys"))
    say("verify-carry-objtrust: box %s, account directory %s" % (box, acct))
    bp = os.path.join(acct, "bp")
    if not os.path.isdir(bp):
        bail("%s has no bp folder: not an account" % acct)
    switch = os_switch(acct)
    say("  the account's OS switch (register field 8): %s" % switch)

    outside = tempfile.mkdtemp(prefix="zzot-out-")
    target = os.path.join(outside, "o.txt")
    with open(target, "w") as h:
        h.write("x\n")
    tb = target.replace("/", "\\")
    if "'" in tb:
        bail("the temp path holds a single quote: %r" % tb)
    src = os.path.join(bp, "zzot")
    with open(src, "w", newline="\r\n") as h:
        h.write("program zzot\n   x = ospath('%s', 2)\n   crt 'ZOT[' : x : '|' : status() : ']'\nend\n" % tb)
    say("  probe program %s asks OSPATH(%s, 2)" % (src, tb))

    try:
        out = sess(box, "BASIC bp zzot", "RUN bp zzot")
        say("    | " + " | ".join(l for l in out.splitlines() if l.strip())[-400:])
        obj = None
        for cand in ("bp.out", "BP.OUT"):
            p = os.path.join(acct, cand, "zzot")
            if os.path.isfile(p):
                obj = p
        a = answer(out)
        row("C0 the probe compiled into the account's bp.out", obj is not None, "no bp.out/zzot after BASIC")
        if switch != "off":
            row("C1 the account's OS switch is off, so the gate can be measured", False,
                "switch is %s: with it on an ordinary program passes too, and the rows below would prove nothing" % switch)
            return
        row("C1 baseline: the plain program is refused outside the account (answer 0, a nonzero STATUS)",
            a is not None and a[0] == "0" and a[1] not in ("", "0"), "printed %r" % (a,))
        if obj is None:
            return
        before = flags_of(obj)
        with open(obj, "r+b") as h:
            h.seek(FLAGS_AT)
            h.write(bytes([(before | HDR_INTERNAL) & 0xFF, ((before | HDR_INTERNAL) >> 8) & 0xFF]))
        after = flags_of(obj)
        row("F1 the forged object's flags word has HDR_INTERNAL (0x0002) set: before 0x%04x, after 0x%s" %
            (before or 0, "%04x" % after if after is not None else "?"),
            after is not None and (after & HDR_INTERNAL) and not ((before or 0) & HDR_INTERNAL), "")
        out = sess(box, "RUN bp zzot")
        say("    | " + " | ".join(l for l in out.splitlines() if l.strip())[-400:])
        a = answer(out)
        row("T1 the forged object, run as the ordinary user, is STILL refused (the bit from bp.out is not trusted)",
            a is not None and a[0] == "0" and a[1] not in ("", "0"), "printed %r" % (a,))
    finally:
        for p in (src, os.path.join(acct, "bp.out", "zzot"), target):
            try:
                os.remove(p)
            except OSError:
                pass
        try:
            os.rmdir(outside)
        except OSError:
            pass


if __name__ == "__main__":
    main()
    say("verify-carry-objtrust: %d passed, %d failed" % (passed, failed))
    sys.exit(1 if failed else 0)
