#!/usr/bin/env python3
#
# sandbox-mfilepath.py - OPTION INHERIT.MFILE.PATH (openQM 4 release item, sheet 461).  No install, no sudo.
#
#   python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/sandbox-mfilepath.py <dir> [--build]
#
# <dir> is a sandbox made by sandbox-fromtree.py.  With --build it is built first from THIS tree (it must be empty
# or absent); without it <dir> must already be built.  Exit 0 every row passed, 1 a row failed, 2 it could not run.
#
# START-HISTORY:
# 14 Oct 26 dm  New.  createf: a new subfile goes in the directory of the default subfile under the option.
# END-HISTORY
#
# The evidence is the DISK: where the operating system directory of each new subfile ends up.  The default
# subfile is made with PATHNAME into a directory outside the account's own file directory; a second subfile is
# then added with the option off (control: it goes under a directory named for the file), with the option on
# (it goes next to the default subfile), with the option on and PATHNAME (PATHNAME wins), and the option on for a
# file that has no subfile yet (the ordinary default).

import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.path.join(HERE, "sandbox-fromtree.py")
ANSI = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]")
RUN = "%05d" % (os.getpid() % 100000)
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
    say("sandbox-mfilepath: CANNOT RUN - " + msg)
    sys.exit(2)


def sess(box, *cmds):
    say("    > " + " | ".join(cmds))
    p = subprocess.run([sys.executable, TOOL, box, "sess", os.path.join(box, "user_accounts")] + list(cmds),
                       capture_output=True, text=True, errors="replace", timeout=600)
    out = ANSI.sub("", p.stdout + p.stderr)
    return out.split(":TERM 200,9999", 1)[-1]


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) != 1:
        bail("usage: sandbox-mfilepath.py <dir> [--build]")
    box = os.path.abspath(args[0])
    say("sandbox-mfilepath: sandbox %s" % box)
    if "--build" in sys.argv:
        if os.path.exists(box) and os.listdir(box):
            bail("%s is not empty" % box)
        r = subprocess.run([sys.executable, TOOL, box, "all"], capture_output=True, text=True, errors="replace", timeout=900)
        if "[FAIL]" in r.stdout or r.returncode != 0 or "[PASS] THIRD.COMPILE" not in r.stdout:
            bail("the sandbox build did not pass:\n" + r.stdout[-800:])
        say("sandbox-mfilepath: built, bootstrap passed")
    elif not os.path.isfile(os.path.join(box, "sys", "bin", "sd")):
        bail("%s holds no built sandbox (use --build, or point it at one)" % box)
    subprocess.run([sys.executable, TOOL, box, "start"], capture_output=True, text=True, errors="replace", timeout=120)

    acct = os.path.join(box, "user_accounts")

    def found_under(root, name):
        """The directory that holds an entry called name, searching below root (None if there is none)."""
        for d, dirs, files in os.walk(root):
            if name in dirs or name in files:
                return d
        return None

    ext = os.path.join(box, "zzext" + RUN)          # a directory outside every file's own directory
    other = os.path.join(box, "zzother" + RUN)
    os.makedirs(ext)
    os.makedirs(other)
    f_off, f_on, f_path, f_new = ("zzmf%s%s" % (k, RUN) for k in ("off", "on", "path", "new"))

    # the default subfile of each file goes into ext; then the second subfile is added
    # (each file's default subfile has its own name, since all three share the directory)
    for k, f in enumerate((f_off, f_on, f_path)):
        sess(box, "create.file %s,main%d pathname %s no.query" % (f, k, ext))
        if not os.path.exists(os.path.join(ext, "main%d" % k)):
            bail("the default subfile was not created in %s: %s" % (ext, os.listdir(ext)))

    say("")
    say("-- option off (control): the new subfile goes under a directory named for the file")
    sess(box, "option inherit.mfile.path off", "create.file %s,sub1 dynamic no.query" % f_off)
    row("off: subfile is not next to the default subfile", not os.path.exists(os.path.join(ext, "sub1")),
        str(os.listdir(ext)))
    row("off: the subfile was made, in a directory of its own under the account (not under the default subfile's)",
        found_under(box, "sub1") is not None and found_under(box, "sub1") != ext, str(found_under(box, "sub1")))

    say("")
    say("-- option on: the new subfile goes next to the default subfile")
    sess(box, "option inherit.mfile.path on", "create.file %s,sub2 dynamic no.query" % f_on)
    row("on: subfile is next to the default subfile", os.path.exists(os.path.join(ext, "sub2")), str(os.listdir(ext)))
    row("on: no directory made under the account for it", not os.path.isdir(os.path.join(acct, f_on)),
        str(os.listdir(acct)))

    say("")
    say("-- option on and PATHNAME: PATHNAME wins")
    sess(box, "option inherit.mfile.path on", "create.file %s,sub3 dynamic pathname %s no.query" % (f_path, other))
    row("pathname: subfile is in the named directory", os.path.exists(os.path.join(other, "sub3")), str(os.listdir(other)))
    row("pathname: subfile is not next to the default subfile", not os.path.exists(os.path.join(ext, "sub3")),
        str(os.listdir(ext)))

    say("")
    say("-- option on, file with no subfile yet: the ordinary default")
    sess(box, "option inherit.mfile.path on", "create.file %s,first dynamic no.query" % f_new)
    row("new file: the subfile was made under the account, as it always was (not next to anyone's default subfile)",
        found_under(box, "first") is not None and found_under(box, "first") not in (ext, other), str(found_under(box, "first")))

    say("")
    out = sess(box, "option inherit.mfile.path display")
    row("option display names the option", re.search(r"(?m)^\s*inherit\.mfile\.path: (On|Off)", out, re.I) is not None, out[-200:])
    say("\nsandbox-mfilepath: %d passed, %d failed" % (passed, failed))
    sys.exit(1 if failed else 0)


main()
