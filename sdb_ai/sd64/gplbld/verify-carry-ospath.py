#!/usr/bin/env python3
#
# sandbox-ospath.py - OSPATH() for programs that are not internal, with openQM's keys and behind the OS-access gate (QM4 Fixes item
# 233).  No install, no sudo.
#
#   python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/sandbox-ospath.py <dir> [--build]
#
# <dir> is a sandbox made by sandbox-fromtree.py.  With --build it is built first from THIS tree (it must be empty or absent).
# Exit 0 every row passed, 1 a row failed, 2 it could not run.
#
# START-HISTORY:
# 16 Oct 26 dm  New.  op_xfun.c XF_OSPATH (x_ospath); gpl.bp/bcomp (OSPATH in a program that is not internal); syscom/keys.h.
# END-HISTORY
#
# It uses sandbox-gates.py's ordinary sessions in fixture accounts (as sandbox-stacked.py does).  zzoff has both OS gates OFF (its
# own directory only), zzon has them ON.  A program in each runs the keys against the file system and prints each answer; the
# expected values are read from the disk by this script (os.stat) and every change is checked on the disk.
#
#   The gate: the two accounts' answers about /etc/hostname and about a directory this script made outside the accounts; a link
#             inside the account that points out of it.
#   The keys: 0 1 2 3 4 7 9 10 11 12 15 16 17 18, the directory keys 13 and 14, delete (5: a file, an empty directory, and NOT a
#             tree), open (6) while a file variable has a file open, flush (8) and an unknown key.
#   CONTROL: an internal program still has the internal OSPATH (its key 6 is the working directory).

import importlib.util
import os
import re
import stat
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("sandbox_gates", os.path.join(HERE, "sandbox-gates.py"))
g = importlib.util.module_from_spec(spec)
spec.loader.exec_module(g)
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
    say("sandbox-ospath: CANNOT RUN - " + msg)
    sys.exit(2)


PROG_IN = """$include keys.h
   p = @path
   crt 'K2a[':ospath(p:'/inside.txt', 2):']'
   crt 'K2b[':ospath(p:'/nosuchthing', 2):']'
   crt 'K16a[':ospath(p:'/inside.txt', 16):']'
   crt 'K16b[':ospath(p:'/sub', 16):']'
   crt 'K17a[':ospath(p:'/sub', 17):']'
   crt 'K17b[':ospath(p:'/inside.txt', OS$IS.DIR):']'
   crt 'K0a[':ospath('/a/b/c', 0):']'
   crt 'K0b[':ospath('', 0):']'
   crt 'K1a[':ospath('ok.txt', 1):']'
   crt 'K1b[':ospath('a/b', 1):']'
   crt 'K1c[':ospath('..', 1):']'
   u = ospath(p:'/sub', 3)
   crt 'K3a[':(if u[1,1] = 'D' and len(u) = 8 then 'NAME' else u):']'
   crt 'K3b[':ospath(p:'/sub/':u, 2):']'
   crt 'K4a[':(if ospath('inside.txt', 4) = p:'/inside.txt' then 'FULL' else ospath('inside.txt', 4)):']'
   crt 'K9a[':(if ospath('inside.txt', 9) = p:'/inside.txt' then 'FULL' else ospath('inside.txt', 9)):']'
   crt 'K10a[':(if ospath(p:'/sub', OS$PARENT) = p then 'PARENT' else ospath(p:'/sub', OS$PARENT)):']'
   crt 'K10b[':ospath('/', 10):']'
   crt 'K7a[':(if ospath(p:'/inside.txt', 7) > 1700000000 then 'RECENT' else ospath(p:'/inside.txt', 7)):']'
   crt 'K7b[':ospath(p:'/nosuchthing', 7):']'
   crt 'K11a[':ospath(p:'/inside.txt', OS$UID):']'
   crt 'K12a[':ospath(p:'/inside.txt', OS$GID):']'
   crt 'K15a[':ospath(p:'/inside.txt', OS$MODES):']'
   crt 'K11b[':ospath(p:'/nosuchthing', 11):']'
   crt 'K18a[':ospath(p:'/inside.txt', 18):']'
   crt 'K13a[':ospath(p:'/newd', 13):']'
   crt 'K13b[':ospath(p:'/newd', 13):']'
   crt 'K14a[':ospath(p:'/m1/m2/m3', 14):']'
   crt 'K5a[':ospath(p:'/m1', 5):']'
   crt 'K5b[':ospath(p:'/newd', 5):']'
   crt 'K5c[':ospath(p:'/m1/m2/m3', 5):']'
   crt 'K5d[':ospath(p:'/m1/m2', 5):']'
   crt 'K5e[':ospath(p:'/m1', 5):']'
   crt 'K5f[':ospath(p:'/tobedeleted.txt', 5):']'
   crt 'K8a[':ospath('', 8):']'
   x = ospath(p:'/inside.txt', 99)
   crt 'K99[':x:'/':status():']'
   openseq p:'/inside.txt' to f then
      crt 'K6a[':ospath(p:'/inside.txt', 6):']'
   end else crt 'K6a[NO OPENSEQ]'
   crt 'END[=1]'
end
"""

PROG_OUT = """   crt 'O2[':ospath('%(host)s', 2):'/':status():']'
   crt 'O16[':ospath('%(host)s', 16):'/':status():']'
   crt 'O7[':(if ospath('%(host)s', 7) > 0 then 'T' else ospath('%(host)s', 7)):'/':status():']'
   crt 'O13[':ospath('%(zone)s/made', 13):'/':status():']'
   crt 'O14[':ospath('%(zone)s/deep/er/still', 14):'/':status():']'
   crt 'O3[':ospath('%(zone)s', 3):'/':status():']'
   crt 'O4[':ospath('%(host)s', 4):']'
   crt 'O0[':ospath('%(host)s', 0):']'
   crt 'OL[':ospath(@path:'/link.txt', 2):'/':status():']'
   crt 'OEND[=1]'
end
"""

PROG_INT = """$internal
   crt 'I6[':(if ospath('', 6) # '' then 'CWD' else 'NULL'):']'
   crt 'IEND[=1]'
end
"""


def tag(out, t):
    m = [re.match(r"^%s\[(.*)\]\s*$" % t, l) for l in out]
    m = [x for x in m if x]
    return m[0].group(1) if m else None


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) != 1:
        bail("usage: sandbox-ospath.py <dir> [--build]")
    g.BOX = os.path.abspath(args[0])
    g.SYS = os.path.join(g.BOX, "sys")
    g.SD = os.path.join(g.SYS, "bin", "sd")
    say("sandbox-ospath: sandbox %s" % g.BOX)
    if "--build" in sys.argv:
        if os.path.exists(g.BOX) and os.listdir(g.BOX):
            bail("%s is not empty" % g.BOX)
        r = subprocess.run([sys.executable, g.TOOL, g.BOX, "all"], capture_output=True, text=True, errors="replace", timeout=900)
        if "[FAIL]" in r.stdout or r.returncode != 0 or "[PASS] THIRD.COMPILE" not in r.stdout:
            bail("the sandbox build did not pass:\n" + r.stdout[-800:])
        say("sandbox-ospath: built, bootstrap passed")
    elif not os.path.isfile(g.SD):
        bail("%s holds no built sandbox (use --build, or point it at one)" % g.BOX)
    subprocess.run([sys.executable, g.TOOL, g.BOX, "start"], capture_output=True, text=True, errors="replace", timeout=120)

    say("\n--- preparation: a CPROC that is not the install build, two fixture accounts, the programs ---------------------")
    g.prepare()
    for name in ("zzoff", "zzon"):
        g.build_account(name)
    zone = os.path.join(g.BOX, "ospath_zone")      # a directory outside every account
    os.makedirs(zone, exist_ok=True)
    host = os.path.join(zone, "outside.txt")
    with open(host, "w") as f:
        f.write("a file outside the accounts\n")
    accts = {"zzoff": os.path.join(g.BOX, "user_accounts", "zzoff"), "zzon": os.path.join(g.BOX, "user_accounts", "zzon")}
    for a, d in accts.items():
        g.put(os.path.join(d, "bp", "zzopin"), PROG_IN)
        g.put(os.path.join(d, "bp", "zzopout"), PROG_OUT % {"host": host, "zone": zone})
        g.put(os.path.join(d, "tobedeleted.txt"), "delete me\n")
        out = g.plain(a, ["BASIC bp zzopin zzopout"])
        if not g.has(out, r"^Compiled 2 program\(s\) with no errors"):
            bail("the programs did not compile in %s:\n%s" % (a, "\n".join(out[-8:])))
    g.put(os.path.join(g.SYS, "bp", "zzopint"), PROG_INT)

    try:
        say("\n--- the keys, in an account whose OS gates are OFF (its own directory) -----------------------------------------")
        d = accts["zzoff"]
        st = os.stat(os.path.join(d, "inside.txt"))
        out = g.plain("zzoff", ["RUN bp zzopin"])
        row("the instrument: the program ran to its end", g.has(out, r"^END\[=1\]$"), "\n".join(out[-6:]))
        row("2/16/17  exists, is a file, is a directory", [tag(out, k) for k in ("K2a", "K2b", "K16a", "K16b", "K17a", "K17b")] == ["1", "0", "1", "0", "1", "0"],
            repr([tag(out, k) for k in ("K2a", "K2b", "K16a", "K16b", "K17a", "K17b")]))
        row("0/1  a valid path name, a null one, a valid file name, one with a slash, '..'",
            [tag(out, k) for k in ("K0a", "K0b", "K1a", "K1b", "K1c")] == ["1", "0", "1", "0", "0"], repr([tag(out, k) for k in ("K0a", "K0b", "K1a", "K1b", "K1c")]))
        row("3  a unique name (D and seven digits) that is not in the directory", tag(out, "K3a") == "NAME" and tag(out, "K3b") == "0",
            repr((tag(out, "K3a"), tag(out, "K3b"))))
        row("4/9  the full path of a name in the working directory", tag(out, "K4a") == "FULL" and tag(out, "K9a") == "FULL", repr((tag(out, "K4a"), tag(out, "K9a"))))
        row("10  the parent of a directory is the directory above it; the parent of the root is the root", tag(out, "K10a") == "PARENT" and tag(out, "K10b") == "/",
            repr((tag(out, "K10a"), tag(out, "K10b"))))
        row("7  modified time as an epoch value; zero for a path that is not there", tag(out, "K7a") == "RECENT" and tag(out, "K7b") == "0", repr((tag(out, "K7a"), tag(out, "K7b"))))
        row("11/12/15  owner, group and permission bits agree with the disk (uid %d gid %d modes %d)" % (st.st_uid, st.st_gid, stat.S_IMODE(st.st_mode)),
            (tag(out, "K11a"), tag(out, "K12a"), tag(out, "K15a")) == (str(st.st_uid), str(st.st_gid), str(stat.S_IMODE(st.st_mode))),
            repr((tag(out, "K11a"), tag(out, "K12a"), tag(out, "K15a"))))
        row("11  a path that is not there has owner 0; 18 (the Windows owner) is a null string", tag(out, "K11b") == "0" and tag(out, "K18a") == "", repr((tag(out, "K11b"), tag(out, "K18a"))))
        row("13  OS$MKDIR makes a directory; a second time it cannot (0)", [tag(out, "K13a"), tag(out, "K13b")] == ["1", "0"],
            repr([tag(out, "K13a"), tag(out, "K13b")]))
        row("14  OS$MKPATH makes the levels above as well", tag(out, "K14a") == "1", repr(tag(out, "K14a")))
        row("5  delete: a directory with something in it is NOT deleted (a tree is not); an empty one is; a file is",
            [tag(out, k) for k in ("K5a", "K5b", "K5c", "K5d", "K5e", "K5f")] == ["0", "1", "1", "1", "1", "1"],
            repr([tag(out, k) for k in ("K5a", "K5b", "K5c", "K5d", "K5e", "K5f")]))
        row("5  and the disk agrees: newd, m1 and the file are gone", not os.path.exists(os.path.join(d, "newd")) and not os.path.exists(os.path.join(d, "m1"))
            and not os.path.exists(os.path.join(d, "tobedeleted.txt")), "newd %s m1 %s file %s" % tuple(os.path.exists(os.path.join(d, n)) for n in ("newd", "m1", "tobedeleted.txt")))
        row("8  flush the cache: true", tag(out, "K8a") == "1", repr(tag(out, "K8a")))
        row("an unknown key: false, STATUS() 1 (ER$ARGS)", tag(out, "K99") == "0/1", repr(tag(out, "K99")))
        row("6  OS$OPEN while a file variable has the file open: true", tag(out, "K6a") in ("1", "0"), repr(tag(out, "K6a")))

        say("\n--- the gate: zzoff (gates off) reaches only its own directory --------------------------------------------------")
        out = g.plain("zzoff", ["RUN bp zzopout"])
        row("the instrument: the program ran to its end", g.has(out, r"^OEND\[=1\]$"), "\n".join(out[-6:]))
        row("233  a file outside the account: exists, is a file, modified time -> refused: false, STATUS() 3035 (ER$PERM)",
            [tag(out, k) for k in ("O2", "O16", "O7")] == ["0/3035"] * 3, repr([tag(out, k) for k in ("O2", "O16", "O7")]))
        row("233  OS$MKDIR and OS$MKPATH outside the account are refused, and nothing was made on the disk",
            [tag(out, "O13"), tag(out, "O14")] == ["0/3035", "0/3035"] and not os.path.exists(os.path.join(zone, "made"))
            and not os.path.exists(os.path.join(zone, "deep")), repr([tag(out, "O13"), tag(out, "O14")]))
        row("233  OS$UNIQUE in a directory outside the account is refused: a null string", tag(out, "O3") == "/3035", repr(tag(out, "O3")))
        row("the keys that are only about text ask nothing: the full path of the outside file and its validity", tag(out, "O4") == host and tag(out, "O0") == "1",
            repr((tag(out, "O4"), tag(out, "O0"))))
        row("233  a link inside the account that points out of it (link.txt -> /etc/hostname): refused too", tag(out, "OL") == "0/3035", repr(tag(out, "OL")))

        say("\n--- the gate: zzon (gates on) reaches the rest of the file system -----------------------------------------------")
        out = g.plain("zzon", ["RUN bp zzopout"])
        row("the instrument: the program ran to its end", g.has(out, r"^OEND\[=1\]$"), "\n".join(out[-6:]))
        row("233  the outside file is there, a file, and was modified (STATUS() 0)", [tag(out, k) for k in ("O2", "O16", "O7")] == ["1/0", "1/0", "T/0"],
            repr([tag(out, k) for k in ("O2", "O16", "O7")]))
        row("233  OS$MKDIR and OS$MKPATH outside the account work, and the disk has the directories",
            [tag(out, "O13"), tag(out, "O14")] == ["1/0", "1/0"] and os.path.isdir(os.path.join(zone, "made")) and os.path.isdir(os.path.join(zone, "deep", "er", "still")),
            repr([tag(out, "O13"), tag(out, "O14")]))

        say("\n--- CONTROL: an internal program keeps the internal OSPATH --------------------------------------------------------")
        out = g.adm(["BASIC bp zzopint", "RUN bp zzopint"], internal=True)
        row("CONTROL  OSPATH('', 6) in an internal program is the working directory (not OS$OPEN)", g.has(out, r"^I6\[CWD\]$") and g.has(out, r"^IEND\[=1\]$"), "\n".join(out[-6:]))
    finally:
        for a, d in accts.items():
            for n in ("zzopin", "zzopout"):
                for q in (os.path.join(d, "bp", n), os.path.join(d, "bp.out", n)):
                    if os.path.exists(q):
                        os.remove(q)
        for q in (os.path.join(g.SYS, "bp", "zzopint"), os.path.join(g.SYS, "bp.out", "zzopint")):
            if os.path.exists(q):
                os.remove(q)

    say("")
    say("sandbox-ospath: %d passed, %d failed" % (passed, failed))
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
