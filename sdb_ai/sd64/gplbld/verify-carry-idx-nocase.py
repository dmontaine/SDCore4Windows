#!/usr/bin/env python3
#
# sandbox-idx-nocase.py - sheet 54: CREATE.INDEX and MAKE.INDEX take NO.CASE (a case insensitive alternate key index)
#                         No install, no sudo.
#
#   python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/sandbox-idx-nocase.py <dir> [--build]
#
# <dir> is a sandbox made by sandbox-fromtree.py (needs a `make`d bin/sd).  With --build it is built first from
# THIS tree (it must be empty or absent).  Exit 0 every row passed, 1 a row failed, 2 it could not run.
#
# START-HISTORY:
# 14 Oct 26 dm  Written for sheet 54.
# END-HISTORY
#
# THE INSTRUMENT.  Two files hold the same records ('Apple', 'apple', 'APPLE', 'pear' under the field NAME), one indexed
# with NO.CASE and one without.  The evidence is the index itself: the program selects through it with SELECTINDEX /
# SELECTV of the key as typed in another case, and reads LIST.INDEX DETAIL.  Every row has the plain index as control.

import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.path.join(HERE, "sandbox-fromtree.py")
ANSI = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]")
passed = failed = 0
made = []

PROG = ("   for t = 1 to 3\n"
        "      nm = 'zzic':t\n"
        "      execute 'DELETE.FILE ':nm capturing j\n"
        "      execute 'DELETE.FILE DICT ':nm capturing j\n"
        "      execute 'CREATE.FILE ':nm capturing j\n"
        "      open 'DICT', nm to d else stop 'no dict'\n"
        "      write 'D':@fm:'1':@fm:'':@fm:'NAME':@fm:'10':@fm:'S' on d, 'NAME'\n"
        "      open nm to f else stop 'no f'\n"
        "      write 'Apple' on f, 'r1'\n      write 'apple' on f, 'r2'\n      write 'APPLE' on f, 'r3'\n      write 'pear' on f, 'r4'\n"
        "      close f ; close d\n"
        "   next t\n"
        "   execute 'CREATE.INDEX zzic1 NAME NO.CASE' capturing o1\n"
        "   execute 'CREATE.INDEX zzic2 NAME' capturing o2\n"
        "   execute 'MAKE.INDEX zzic3 NAME NO.CASE' capturing o3\n"
        "   crt 'O1[':convert(o1, @fm, '|'):']'\n"
        "   crt 'O2[':convert(o2, @fm, '|'):']'\n"
        "   crt 'O3[':convert(o3, @fm, '|'):']'\n"
        "   execute 'BUILD.INDEX zzic1 NAME' capturing j\n"
        "   execute 'BUILD.INDEX zzic2 NAME' capturing j\n"
        "   for t = 1 to 3\n"
        "      open 'zzic':t to f else stop 'no f'\n"
        "      selectindex 'NAME', 'apple' from f to 1\n"
        "      ids = ''\n      loop\n         readnext id from 1 else exit\n         ids := id : ' '\n      repeat\n"
        "      crt 'K':t:'[':trim(ids):']'\n"
        "      selectindex 'NAME', 'APPLE' from f to 1\n"
        "      ids = ''\n      loop\n         readnext id from 1 else exit\n         ids := id : ' '\n      repeat\n"
        "      crt 'U':t:'[':trim(ids):']'\n"
        "      close f\n"
        "   next t\n"
        "   crt 'DONE54'\nend\n")


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
    say("sandbox-idx-nocase: CANNOT RUN - " + msg)
    sys.exit(2)


def tool(box, *args, **kw):
    return subprocess.run([sys.executable, TOOL, box] + list(args), capture_output=True, text=True, errors="replace",
                          timeout=kw.pop("timeout", 900), **kw)


def sess(box, *cmds):
    say("    > %s" % " | ".join(c if len(c) < 60 else c[:57] + "..." for c in cmds))
    p = subprocess.run([sys.executable, TOOL, box, "sess", os.path.join(box, "user_accounts")] + list(cmds),
                       capture_output=True, text=True, errors="replace", timeout=900)
    return ANSI.sub("", p.stdout + p.stderr).split(":TERM 200,9999", 1)[-1]


def tagged(out, tag):
    m = re.search(r"(?m)^%s\[(.*)\]\s*$" % tag, out)
    return m.group(1) if m else None


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) != 1:
        bail("usage: sandbox-idx-nocase.py <dir> [--build]")
    box = os.path.abspath(args[0])
    sysd = os.path.join(box, "sys")
    say("sandbox-idx-nocase: sandbox %s" % box)
    if "--build" in sys.argv:
        if os.path.exists(box) and os.listdir(box):
            bail("%s is not empty" % box)
        r = tool(box, "all")
        if "[FAIL]" in r.stdout or r.returncode != 0 or "[PASS] THIRD.COMPILE" not in r.stdout:
            bail("the sandbox build did not pass:\n" + r.stdout[-800:])
        say("sandbox-idx-nocase: built, bootstrap passed")
    elif not os.path.isfile(os.path.join(sysd, "bin", "sd")):
        bail("%s holds no built sandbox (use --build, or point it at one)" % box)

    try:
        tool(box, "start", timeout=180)
        with open(os.path.join(sysd, "bp", "zzic"), "w") as f:
            f.write(PROG)
        made.append("zzic")
        out = sess(box, "BASIC bp zzic")
        if "Compiled 1 program(s) with no errors" not in out:
            bail("the program did not compile:\n" + out[-800:])
        out = sess(box, "RUN bp zzic")
        say("    %s" % {t: tagged(out, t) for t in ("O1", "O2", "O3", "K1", "U1", "K2", "U2", "K3", "U3")})
        row("the run reached its end", "DONE54" in out, out[-500:])
        for t in ("O1", "O2", "O3"):
            row("%s: CREATE.INDEX / MAKE.INDEX did not refuse its words" % t,
                not re.search(r"(?i)unexpected|illegal|not found|syntax", tagged(out, t) or ""), tagged(out, t) or "")
        row("CONTROL: the plain index finds only 'apple' for 'apple' (r2)", tagged(out, "K2") == "r2", "got %r" % tagged(out, "K2"))
        row("CONTROL: ... and only 'APPLE' for 'APPLE' (r3)", tagged(out, "U2") == "r3", "got %r" % tagged(out, "U2"))
        for t, how in (("1", "CREATE.INDEX NO.CASE"), ("3", "MAKE.INDEX NO.CASE")):
            k, u = tagged(out, "K" + t), tagged(out, "U" + t)
            want = {"r1", "r2", "r3"}
            row("54: %s finds all three spellings for 'apple'" % how, k is not None and set(k.split()) == want, "got %r" % k)
            row("54: %s finds the same three for 'APPLE'" % how, u is not None and set(u.split()) == want, "got %r" % u)
    finally:
        tool(box, "stop", timeout=120)
        for nm in made:
            for d in ("bp", "bp.out"):
                pth = os.path.join(sysd, d, nm)
                if os.path.exists(pth):
                    os.remove(pth)

    say("\nsandbox-idx-nocase: %d passed, %d failed" % (passed, failed))
    sys.exit(0 if failed == 0 else 1)


if __name__ == "__main__":
    main()
