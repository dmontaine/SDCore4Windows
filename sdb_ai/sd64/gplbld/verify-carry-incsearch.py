#!/usr/bin/env python3
#
# sandbox-incsearch.py - SEARCH file.list in $BASIC.OPTIONS (openQM 4, sheet 290).  No install, no sudo.
#
#   python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/sandbox-incsearch.py <dir> [--build]
#
# <dir> is a sandbox made by sandbox-fromtree.py.  With --build it is built first from THIS tree (it must be empty
# or absent); without it <dir> must already be built.  Exit 0 every row passed, 1 a row failed, 2 it could not run.
#
# START-HISTORY:
# 16 Oct 26 dm  New.  bcomp: $BASIC.OPTIONS SEARCH names the files an $INCLUDE with no file name looks in (process.include).
# END-HISTORY
#
# Two directory files, the source file zzsrc (programs, and its own $BASIC.OPTIONS) and the include file zzinc.  Each program is run
# and prints the value its include defines, so a verdict is the number that came out, not a compile message.  CONTROLS: no SEARCH (an
# include held only in zzinc is not found, as before), the default order with the record in the source file, and a record that is
# nowhere.

import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.path.join(HERE, "sandbox-fromtree.py")
ANSI = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]")
RUN = "%05d" % (os.getpid() % 100000)
SRC, INC = "zzsr" + RUN, "zzin" + RUN
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
    say("sandbox-incsearch: CANNOT RUN - " + msg)
    sys.exit(2)


def sess(box, *cmds, quiet=False):
    if not quiet:
        say("    > " + " | ".join(cmds))
    p = subprocess.run([sys.executable, TOOL, box, "sess", os.path.join(box, "user_accounts")] + list(cmds),
                       capture_output=True, text=True, errors="replace", timeout=600)
    out = ANSI.sub("", p.stdout + p.stderr)
    return out.split(":TERM 200,9999", 1)[-1]


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) != 1:
        bail("usage: sandbox-incsearch.py <dir> [--build]")
    box = os.path.abspath(args[0])
    sysd = os.path.join(box, "sys")
    bp = os.path.join(sysd, "bp")
    say("sandbox-incsearch: sandbox %s" % box)
    if "--build" in sys.argv:
        if os.path.exists(box) and os.listdir(box):
            bail("%s is not empty" % box)
        r = subprocess.run([sys.executable, TOOL, box, "all"], capture_output=True, text=True, errors="replace", timeout=900)
        if "[FAIL]" in r.stdout or r.returncode != 0 or "[PASS] THIRD.COMPILE" not in r.stdout:
            bail("the sandbox build did not pass:\n" + r.stdout[-800:])
        say("sandbox-incsearch: built, bootstrap passed")
    elif not os.path.isfile(os.path.join(sysd, "bin", "sd")):
        bail("%s holds no built sandbox (use --build, or point it at one)" % box)
    subprocess.run([sys.executable, TOOL, box, "start"], capture_output=True, text=True, errors="replace", timeout=120)

    made = []

    def put(name, text):
        with open(os.path.join(bp, name), "w") as f:
            f.write(text)
        made.append(name)

    prog = lambda v: "   crt 'VALUE ':%s\nend\n" % v
    # records: the include record zzi.h exists in INC (value 11), and also in SRC with value 22 for the order rows
    put("zzh_inc", "equate ZZVAL to 11\n")
    put("zzh_src", "equate ZZVAL to 22\n")
    put("zzp_use", "$include zzi.h\n" + prog("ZZVAL"))
    put("zzp_none", "$include zzi.nowhere\n" + prog("0"))
    put("zzo_inc", "X\nSEARCH %s\n" % INC)
    put("zzo_incsrc", "X\nSEARCH %s,@\n" % INC)
    put("zzo_srcinc", "X\nSEARCH @,%s\n" % INC)
    put("zzo_gone", "X\nSEARCH zznosuchfile%s, %s\n" % (RUN, INC))
    try:
        out = sess(box, "DELETE.FILE %s" % SRC, "DELETE.FILE %s" % INC, "CREATE.FILE %s DIRECTORY" % SRC, "CREATE.FILE %s DIRECTORY" % INC,
                   "COPY FROM BP TO %s zzh_inc,zzi.h" % INC, "COPY FROM BP TO %s zzp_use,zzp_use" % SRC,
                   "COPY FROM BP TO %s zzp_none,zzp_none" % SRC, quiet=True)
        row("setup: the three records were copied", len(re.findall(r"(?m)^1 record\(s\) copied\.", out)) == 3, out[-300:])

        def compile_and_run(name, options=None, own_include=False):
            cmds = []
            if options is not None:
                cmds.append("COPY FROM BP TO %s %s,$BASIC.OPTIONS OVERWRITING" % (SRC, options))
            else:
                cmds.append("DELETE %s $BASIC.OPTIONS" % SRC)
            if own_include:
                cmds.append("COPY FROM BP TO %s zzh_src,zzi.h OVERWRITING" % SRC)
            else:
                cmds.append("DELETE %s zzi.h" % SRC)
            cmds += ["BASIC %s %s" % (SRC, name), "RUN %s %s" % (SRC, name)]
            return sess(box, *cmds)

        say("\n--- no SEARCH list ------------------------------------------------------------------------------------")
        o = compile_and_run("zzp_use")
        row("CONTROL: without SEARCH an include held only in the other file is not found", "not found" in o and not re.search(r"(?m)^VALUE ", o), o[-300:])
        o = compile_and_run("zzp_use", own_include=True)
        row("CONTROL: the default is the source file first: the record in it is used (22)", re.search(r"(?m)^VALUE 22\s*$", o) is not None, o[-300:])

        say("\n--- SEARCH ----------------------------------------------------------------------------------------------")
        o = compile_and_run("zzp_use", options="zzo_inc")
        row("SEARCH names the other file: its record is found and used (11)", re.search(r"(?m)^VALUE 11\s*$", o) is not None, o[-300:])
        o = compile_and_run("zzp_use", options="zzo_inc", own_include=True)
        row("a SEARCH list without @ leaves the source file out: the other file's record wins (11), not the source's", re.search(r"(?m)^VALUE 11\s*$", o) is not None, o[-300:])
        o = compile_and_run("zzp_use", options="zzo_incsrc", own_include=True)
        row("the order is the list's: the other file first, then @ (11)", re.search(r"(?m)^VALUE 11\s*$", o) is not None, o[-300:])
        o = compile_and_run("zzp_use", options="zzo_srcinc", own_include=True)
        row("@ first: the source file's record (22)", re.search(r"(?m)^VALUE 22\s*$", o) is not None, o[-300:])
        o = compile_and_run("zzp_use", options="zzo_srcinc")
        row("@ first and nothing in the source file: the next file in the list has it (11)", re.search(r"(?m)^VALUE 11\s*$", o) is not None, o[-300:])
        o = compile_and_run("zzp_use", options="zzo_gone")
        row("a file in the list that does not exist is passed over when a later one holds the record (11)", re.search(r"(?m)^VALUE 11\s*$", o) is not None, o[-300:])
        o = compile_and_run("zzp_none", options="zzo_inc")
        row("CONTROL: a record in none of the files is reported as not found", "zzi.nowhere" in o and "not found" in o and not re.search(r"(?m)^VALUE ", o), o[-300:])
    finally:
        sess(box, "DELETE.FILE %s" % SRC, "DELETE.FILE %s" % INC, quiet=True)
        for n in made:
            p = os.path.join(bp, n)
            if os.path.exists(p):
                os.remove(p)

    say("")
    say("sandbox-incsearch: %d passed, %d failed" % (passed, failed))
    if passed + failed == 0:
        bail("no row ran - a broken test, not a pass")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
