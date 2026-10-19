#!/usr/bin/env python3
#
# sandbox-fcontrol.py - the public FCONTROL(fvar, action {, qualifier}) with openQM 4's action numbers (15 Oct 26), run by an
#                       ORDINARY program: FC$SET.SEQ.KEY, FC$GET.SEQ.KEY, the field access test (5), FC$VALID.ID and FC$MINMOD, the
#                       refusals (a file opened read only, a file that is not hashed, a qualifier under 1), FC$SYNC (16 Oct 26) and an
#                       unknown action, which must stop the program with a message.  FC$CRLF was refused until 16 Oct 26 and is
#                       tested in sandbox-crlf.py; here it is only asked of a hashed file.  The internal function, renamed
#                       FCONTROL.INT, is checked through CONFIGURE.FILE ... NEXT.
#                       No install, no sudo.
#
#   python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/sandbox-fcontrol.py <dir> [--build]
#
# <dir> is a sandbox made by sandbox-fromtree.py.  With --build it is built first from THIS tree (it must be empty or
# absent).  Exit 0 every row passed, 1 a row failed, 2 it could not run.
#
# START-HISTORY:
# 15 Oct 26 dm  Written for the public FCONTROL().
# END-HISTORY
#
#   1  FC$SET.SEQ.KEY and FC$GET.SEQ.KEY (the qualifier left out), against the id a CREATING.SEQKEY write is then given
#   2  a directory file: SET gives 0 with STATUS 3005, GET gives the null string
#   3  a file opened read only: SET, GET and MINMOD give nothing, STATUS is 3018, and the counter is where it was
#   4  action 5, FC$VALID.ID, FC$MINMOD (and a qualifier under 1)
#   5  FC$SYNC, FC$CRLF and an unknown action stop the program with a message, and the next statement does not run
#   6  the internal function under its new name: CONFIGURE.FILE ... NEXT n and NEXT QUERY still work

import os
import re
import subprocess
import sys

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
    say("sandbox-fcontrol: CANNOT RUN - " + msg)
    sys.exit(2)


def sess(box, *cmds, quiet=False):
    if not quiet:
        say("    > " + " | ".join(cmds))
    p = subprocess.run([sys.executable, TOOL, box, "sess", os.path.join(box, "user_accounts")] + list(cmds),
                       capture_output=True, text=True, timeout=600)
    out = ANSI.sub("", p.stdout + p.stderr)
    out = out.split(":TERM 200,9999", 1)[-1]
    if not quiet:
        for line in out.splitlines():
            if line.strip() and not line.startswith(":") and not line.startswith("exit "):
                say("      | " + line.rstrip()[:130])
    return out


def got(out, tag):
    """The text between tag[ and ] on the last line that has it, or None."""
    m = re.findall(re.escape(tag) + r"\[([^\]]*)\]", out)
    return m[-1] if m else None


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) != 1:
        bail("usage: sandbox-fcontrol.py <dir> [--build]")
    box = os.path.abspath(args[0])
    sysd = os.path.join(box, "sys")
    bp = os.path.join(sysd, "bp")
    say("sandbox-fcontrol: sandbox %s" % box)
    if "--build" in sys.argv:
        if os.path.exists(box) and os.listdir(box):
            bail("%s is not empty" % box)
        r = subprocess.run([sys.executable, TOOL, box, "all"], capture_output=True, text=True, errors="replace", timeout=900)
        if "[FAIL]" in r.stdout or r.returncode != 0 or "[PASS] THIRD.COMPILE" not in r.stdout:
            bail("the sandbox build did not pass:\n" + r.stdout[-800:])
        say("sandbox-fcontrol: built, bootstrap passed")
    elif not os.path.isfile(os.path.join(sysd, "bin", "sd")):
        bail("%s holds no built sandbox (use --build, or point it at one)" % box)
    subprocess.run([sys.executable, TOOL, box, "start"], capture_output=True, text=True, errors="replace", timeout=120)

    made = []

    def prog(name, text):
        with open(os.path.join(bp, name), "w") as f:
            f.write(text)
        made.append(name)

    def compile_all(names):
        out = sess(box, *["BASIC bp " + n for n in names], quiet=True)
        bad = [l for l in out.splitlines() if re.search(r"(?i)\berror\b|unknown|not defined|not assigned", l)
               and not re.search(r"(?i)0 error", l)]
        return out, bad

    try:
        # ---- the programs ----
        prog("zzfc_seq", "$include keys.h\n   open 'zzfc' to f else stop 'no file'\n"
                         "   r1 = fcontrol(f, FC$SET.SEQ.KEY, 50)\n   crt 'SET[':r1:']'\n"
                         "   g = fcontrol(f, FC$GET.SEQ.KEY)\n   crt 'GET1[':g:']'\n"
                         "   write 'x' to f creating.seqkey id\n   crt 'WRITE[':id:']'\n"
                         "   g = fcontrol(f, FC$GET.SEQ.KEY, 0)\n   crt 'GET2[':g:']'\n"
                         "   write 'y' to f creating.seqkey id\n   crt 'WRITE2[':id:']'\nend\n")
        prog("zzfc_dir", "$include keys.h\n   open 'zzfcd' to d else stop 'no dir'\n"
                         "   r = fcontrol(d, FC$SET.SEQ.KEY, 5)\n   crt 'SETD[':r:'/':status():']'\n"
                         "   g = fcontrol(d, FC$GET.SEQ.KEY, 0)\n   crt 'GETD[':g:'/':len(g):']'\n"
                         "   m = fcontrol(d, FC$MINMOD, 4)\n   crt 'MMD[':m:'/':status():']'\nend\n")
        prog("zzfc_ro", "$include keys.h\n   open 'zzfc' to g else stop 'no file'\n"
                        "   void fcontrol(g, FC$SET.SEQ.KEY, 10)\n   m0 = fileinfo(g, FL$MINMOD)\n"
                        "   open 'zzfc' readonly to f else stop 'no ro'\n"
                        "   r = fcontrol(f, FC$SET.SEQ.KEY, 99)\n   crt 'ROSET[':r:'/':status():']'\n"
                        "   x = fcontrol(f, FC$GET.SEQ.KEY, 0)\n   crt 'ROGET[':x:'/':status():']'\n"
                        "   m = fcontrol(f, FC$MINMOD, 31)\n   crt 'ROMM[':m:'/':status():']'\n"
                        "   crt 'MMSAME[':(fileinfo(g, FL$MINMOD) = m0):']'\n"
                        "   n = fcontrol(g, FC$GET.SEQ.KEY, 0)\n   crt 'ROKEPT[':n:']'\nend\n")
        prog("zzfc_misc", "$include keys.h\n   open 'zzfc' to f else stop 'no file'\n"
                          "   crt 'F5[':fcontrol(f, 5, 0):']'\n"
                          "   crt 'V1[':fcontrol(f, FC$VALID.ID, 'abc'):']'\n"
                          "   crt 'V2[':fcontrol(f, FC$VALID.ID, ''):']'\n"
                          "   crt 'V3[':fcontrol(f, FC$VALID.ID, 'a':@fm:'b'):']'\n"
                          "   crt 'V4[':fcontrol(f, FC$VALID.ID, str('x', 200)):']'\n"
                          "   r = fcontrol(f, FC$MINMOD, 7)\n   crt 'MM[':r:'/':fileinfo(f, FL$MINMOD):']'\n"
                          "   r = fcontrol(f, FC$MINMOD, 0)\n   crt 'MM0[':r:'/':status():'/':fileinfo(f, FL$MINMOD):']'\nend\n")
        # 16 Oct 26: FC$SYNC (forced writes, QM4 Fixes item 102) works now; it was refused until then
        prog("zzfc_sync", "$include keys.h\n   open 'zzfc' to f else stop 'no file'\n"
                          "   r = fcontrol(f, FC$SYNC, @true)\n   crt 'S1[':r:']'\n   crt 'S2[':fileinfo(f, FL$SYNC):']'\n"
                          "   crt 'S3[':fcontrol(f, FC$SYNC, -1):']'\n   r = fcontrol(f, FC$SYNC, @false)\n"
                          "   crt 'S4[':r:'/':fileinfo(f, FL$SYNC):']'\nend\n")
        # 16 Oct 26: FC$CRLF (QM4 Fixes item 452) works on a directory or sequential file (sandbox-crlf.py); on a hashed file it
        # answers 0 with STATUS 3004.  It was refused with message 11354 until then.
        prog("zzfc_crlf", "$include keys.h\n   open 'zzfc' to f else stop 'no file'\n"
                          "   r = fcontrol(f, FC$CRLF, -1)\n   crt 'CRLF[':r:'/':status():']'\nend\n")
        prog("zzfc_bad", "   open 'zzfc' to f else stop 'no file'\n"
                         "   r = fcontrol(f, 99, 0)\n   crt 'AFTER_BAD[':r:']'\nend\n")
        prog("zzfc_get", "$include keys.h\n   open 'zzfc' to f else stop 'no file'\n   crt 'G[':fcontrol(f, FC$GET.SEQ.KEY, 0):']'\nend\n")
        out, bad = compile_all(["zzfc_seq", "zzfc_dir", "zzfc_ro", "zzfc_misc", "zzfc_sync", "zzfc_crlf", "zzfc_bad", "zzfc_get"])
        row("setup: all eight programs compile as an ordinary user's programs (the public FCONTROL and the FC$ tokens exist)",
            not bad, "compile lines: %r" % bad[:4])

        sess(box, "DELETE.FILE DICT zzfc", "DELETE.FILE zzfc", "DELETE.FILE zzfcd", "CREATE.FILE zzfc",
             "CREATE.FILE zzfcd DIRECTORY", quiet=True)

        say("\n--- leg 1: the sequential id counter ------------------------------------------------------")
        out = sess(box, "RUN bp zzfc_seq")
        row("THE ROW: FC$SET.SEQ.KEY 50 returns 1", got(out, "SET") == "1", "got %r" % out[-300:])
        row("THE ROW: FC$GET.SEQ.KEY (the qualifier left out) gives 50, the id SET put there, and moves the counter on",
            got(out, "GET1") == "50", "got %r" % got(out, "GET1"))
        row("the next CREATING.SEQKEY write is given 51 (the one after the id reserved)", got(out, "WRITE") == "51", "got %r" % got(out, "WRITE"))
        row("GET again gives 52 (the write and the function use the one counter)", got(out, "GET2") == "52", "got %r" % got(out, "GET2"))
        row("and the write after that is given 53", got(out, "WRITE2") == "53", "got %r" % got(out, "WRITE2"))

        say("\n--- leg 2: a file that is not hashed -------------------------------------------------------")
        out = sess(box, "RUN bp zzfc_dir")
        row("THE ROW: FC$SET.SEQ.KEY on a directory file gives 0 and STATUS 3005", got(out, "SETD") == "0/3005", "got %r" % got(out, "SETD"))
        row("FC$GET.SEQ.KEY gives the null string (length 0)", got(out, "GETD") == "/0", "got %r" % got(out, "GETD"))
        row("FC$MINMOD on a directory file gives 0 and STATUS 3005", got(out, "MMD") == "0/3005", "got %r" % got(out, "MMD"))

        say("\n--- leg 3: a file opened read only --------------------------------------------------------")
        out = sess(box, "RUN bp zzfc_ro")
        row("THE ROW: SET on a read only file gives 0 and STATUS 3018", got(out, "ROSET") == "0/3018", "got %r" % got(out, "ROSET"))
        row("GET on a read only file gives the null string and STATUS 3018", got(out, "ROGET") == "/3018", "got %r" % got(out, "ROGET"))
        row("MINMOD on a read only file gives 0 and STATUS 3018", got(out, "ROMM") == "0/3018", "got %r" % got(out, "ROMM"))
        row("and the minimum modulus is as it was", got(out, "MMSAME") == "1", "got %r" % got(out, "MMSAME"))
        row("and the counter is where SET left it (10): the refused GET did not move it", got(out, "ROKEPT") == "10", "got %r" % got(out, "ROKEPT"))

        say("\n--- leg 4: field access, valid ids and the minimum modulus ------------------------------------")
        out = sess(box, "RUN bp zzfc_misc")
        row("action 5 (field access) is true: SD has no field level encryption", got(out, "F5") == "1", "got %r" % got(out, "F5"))
        row("FC$VALID.ID: an ordinary id is valid", got(out, "V1") == "1", "got %r" % got(out, "V1"))
        row("a null id is not", got(out, "V2") == "0", "got %r" % got(out, "V2"))
        row("an id holding a field mark is not", got(out, "V3") == "0", "got %r" % got(out, "V3"))
        row("an id longer than the file's limit (200 characters) is not", got(out, "V4") == "0", "got %r" % got(out, "V4"))
        row("THE ROW: FC$MINMOD 7 gives 1 and FILEINFO(f, FL$MINMOD) reads 7", got(out, "MM") == "1/7", "got %r" % got(out, "MM"))
        row("FC$MINMOD 0 gives 0 with STATUS 1 and leaves the modulus alone", got(out, "MM0") == "0/1/7", "got %r" % got(out, "MM0"))

        say("\n--- leg 5a: FC$SYNC, forced writes (16 Oct 26) ---------------------------------------------------")
        out = sess(box, "RUN bp zzfc_sync")
        row("FC$SYNC true returns the previous state, 0, and FILEINFO(f, FL$SYNC) then reads 1", got(out, "S1") == "0" and got(out, "S2") == "1",
            "got %r %r" % (got(out, "S1"), got(out, "S2")))
        row("-1 asks without changing: 1", got(out, "S3") == "1", "got %r" % got(out, "S3"))
        row("false returns the previous state, 1, and the file reads 0 again", got(out, "S4") == "1/0", "got %r" % got(out, "S4"))

        say("\n--- leg 5: FC$CRLF on a hashed file (it has no line terminators), and an unknown action -----------------")
        out = sess(box, "RUN bp zzfc_crlf")
        row("THE ROW: FC$CRLF on a hashed file gives 0 and STATUS 3004 (not a directory file); it no longer stops the program",
            got(out, "CRLF") == "0/3004" and "FCONTROL cannot do this action in SD" not in out, "got %r" % out[-300:])
        out = sess(box, "RUN bp zzfc_bad")
        row("THE ROW: action 99 stops the program with the unknown-action message", "the action is not one SD knows" in out, "got %r" % out[-300:])
        row("and the statement after it does not run", "AFTER_BAD[" not in out, "got %r" % out[-300:])

        say("\n--- leg 6: the internal function under its new name --------------------------------------------")
        out = sess(box, "CONFIGURE.FILE zzfc NEXT 100", "CONFIGURE.FILE zzfc NEXT QUERY")
        row("CONFIGURE.FILE NEXT 100 then NEXT QUERY says the next id is 100",
            re.search(r"next sequential record id is 100", out) is not None, "got %r" % out[-300:])
        out = sess(box, "RUN bp zzfc_get")
        row("and the public FCONTROL sees the same counter: GET gives 100", got(out, "G") == "100", "got %r" % got(out, "G"))
    finally:
        for n in made:
            for d in ("bp", "bp.out"):
                p = os.path.join(sysd, d, n)
                if os.path.exists(p):
                    os.remove(p)
        sess(box, "DELETE.FILE DICT zzfc", "DELETE.FILE zzfc", "DELETE.FILE zzfcd", quiet=True)

    say("\nsandbox-fcontrol: %d passed, %d failed" % (passed, failed))
    sys.exit(0 if failed == 0 else 1)


if __name__ == "__main__":
    main()
