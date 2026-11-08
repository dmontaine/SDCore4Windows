#!/usr/bin/env python3
#
# sandbox-sortwide.py - the sort system takes data and keys of any length, in memory and on disk (QM4 Fixes item 455).
#
#   The disk sort records (gplsrc/op_sort.c) counted their bytes in int16_t, so an item or a key of 32 kb or more wrapped
#   when SORTMEM was exceeded and the sort spilled to disk.  The lengths are int32_t now, every field padded to four bytes.
#
#   python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/sandbox-sortwide.py <dir> [--build]
#
# No install, no sudo.  <dir> is a sandbox made by sandbox-fromtree.py (needs a `make`d bin/sd).  With --build it is built first
# from THIS tree (it must be empty or absent).  Exit 0 every row passed, 1 a row failed, 2 it could not run.
#
# The programs are INTERNAL ones (SORTINIT, SORTADD, SORTNEXT() and SORTDATA() are restricted), run through `sd -internal` as
# sandbox-sys-b2.py runs OSPATH().  SORTMEM is set to 1 (kb) in the sandbox's sd.conf for the disk rows, so every item
# overflows the in-memory tree and goes to a work file, and SORTMRG is the default 4, so the files are also merged.
#
# START-HISTORY:
# 16 Oct 26 dm  New.
# 16 Oct 26 dm  C8: a UNIQUE sort that spills (the merge now drops duplicates that lie in two work files; red on HEAD ac509e4, which
#               returned all 600 items of a 200 key sort).
# END-HISTORY
#
# THE INSTRUMENT.  Each row prints what it read.  The expected values are computed here, in Python, from the same keys: the
# order is the bytewise order of the keys, the digests are MD5 of the field mark joined values (SD's md5() works on bytes).
# CONTROL rows run the same program in memory (SORTMEM as built) and on disk with small items, which were always right.
# C7 compares the disk result to the in-memory result of the same input.  THE SANDBOX MUST BE BUILT FROM THE TREE UNDER TEST.

import hashlib
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.path.join(HERE, "sandbox-fromtree.py")

ANSI = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]")
MARK = "# --- sandbox-sortwide below ---"
passed = failed = 0
made = []


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
    say("sandbox-sortwide: CANNOT RUN - " + msg)
    sys.exit(2)


def tool(box, *args, **kw):
    return subprocess.run([sys.executable, TOOL, box] + list(args), capture_output=True, text=True, errors="replace",
                          timeout=kw.pop("timeout", 900), **kw)


def status(box):
    env = dict(os.environ, SD_CONFIG=os.path.join(box, "sd.conf"))
    p = subprocess.run([os.path.join(box, "sys", "bin", "sd"), "-status"], capture_output=True, text=True,
                       errors="replace", env=env, timeout=60)
    return p.stdout + p.stderr


def restart(box, *extra):
    """Stop the sandbox, put `extra` lines in sd.conf below the marker, start it, and say whether SD is running."""
    conf = os.path.join(box, "sd.conf")
    tool(box, "stop", timeout=120)
    with open(conf) as f:
        base = f.read().split(MARK)[0].rstrip("\n") + "\n"
    with open(conf, "w") as f:
        f.write(base + ((MARK + "\n" + "".join(l + "\n" for l in extra)) if extra else ""))
    tool(box, "start", timeout=180)
    ok = re.search(r"(?m)^Started\s+20\d\d-", status(box)) is not None
    say("  -- sd.conf %s: SD %s" % (("+ " + " ".join(extra)) if extra else "as built", "started" if ok else "NOT STARTED"))
    return ok


def isess(box, *cmds):
    """A session in internal mode (sd -internal), where the restricted sort statements compile."""
    say("    > [sd -internal] %d commands" % len(cmds))
    env = dict(os.environ, SD_CONFIG=os.path.join(box, "sd.conf"))
    body = "\nTERM 200,9999\n" + "".join(c + "\n" for c in cmds) + "OFF\n"
    try:
        p = subprocess.run([os.path.join(box, "sys", "bin", "sd"), "-internal"], input=body, cwd=os.path.join(box, "sys"),
                           env=env, capture_output=True, text=True, errors="replace", timeout=90)
    except subprocess.TimeoutExpired:
        say("    !! the session did not end in 90 seconds (a hang is a failure; the process was killed)")
        return ""
    out = ANSI.sub("", p.stdout + p.stderr)
    return re.sub(r"\x1b\[[0-9;?]*[A-Za-z]|\[[0-9;]*[A-Za-z]", "", out.split(":TERM 200,9999", 1)[-1])


def md5(b):
    return hashlib.md5(b).hexdigest()


FM = b"\xfe"


def key5(i):
    return "%05d" % ((i * 7919 + 13) % 10007)


# ---- the programs.  {RET} is the retrieval loop of each case; TAG is C0n. -----------------------------------------------

PROLOGUE = "$internal\n   dim modes(%d)\n   dim keys(%d)\n"

# C1/C2: 300 small items, one key plus data, by SORTNEXT()
P_SMALL = PROLOGUE % (1, 1) + """   modes(1) = 8
   sortinit 1, modes
   for i = 1 to 300
      k = mod(i * 7919 + 13, 10007)
      keys(1) = str('0', 5 - len(k)):k
      sortadd keys, 'D':i
   next i
   all = ''; allk = ''; n = 0
   loop
      d = sortnext(keys)
   until status() do
      all := d:@fm; allk := keys(1):@fm; n += 1
   repeat
   sortclear
   crt '%s[=N=':n:' MD=':digest(all, 0, 'MD5'):' MK=':digest(allk, 0, 'MD5'):' MEM=':config('SORTMEM'):']'
end
"""

# C3: 12 items of 40 kb and more, one key plus data, by SORTNEXT()
P_WIDEDATA = PROLOGUE % (1, 1) + """   modes(1) = 8
   sortinit 1, modes
   for i = 1 to 12
      keys(1) = 'K':('0':mod(i * 5, 13))[2]
      sortadd keys, str(char(64 + i), 40000 + 137 * i)
   next i
   all = ''; lens = ''; n = 0
   loop
      d = sortnext(keys)
   until status() do
      all := d:@fm; lens := len(d):','; n += 1
   repeat
   sortclear
   crt '%s[=N=':n:' LENS=':lens:' MD=':digest(all, 0, 'MD5'):']'
end
"""

# C4: two keys, the first of 40 kb and more, differing only at the end
P_WIDEKEY = PROLOGUE % (2, 2) + """   modes(1) = 8
   modes(2) = 0
   sortinit 2, modes
   for i = 1 to 12
      keys(1) = str('x', 40000):('0':mod(i * 5, 13))[2]
      keys(2) = 'z':i
      sortadd keys, 'W':i
   next i
   order = ''; k1 = ''; k2 = ''; n = 0
   loop
      d = sortnext(keys)
   until status() do
      order := d:','; k1 := keys(1):@fm; k2 := keys(2):@fm; n += 1
   repeat
   sortclear
   crt '%s[=N=':n:' ORDER=':order:' K1=':digest(k1, 0, 'MD5'):' K1LEN=':len(keys(1)):' K2=':digest(k2, 0, 'MD5'):']'
end
"""

# C5: the same data as C3, taken with SORTDATA()
P_WIDEDATA_ALL = PROLOGUE % (1, 1) + """   modes(1) = 8
   sortinit 1, modes
   for i = 1 to 12
      keys(1) = 'K':('0':mod(i * 5, 13))[2]
      sortadd keys, str(char(64 + i), 40000 + 137 * i)
   next i
   all = sortdata()
   n = status()
   sortclear
   crt '%s[=N=':n:' LEN=':len(all):' MD=':digest(all, 0, 'MD5'):']'
end
"""

# C6: a key of 35 kb with no data element: SORTDATA() returns the first key
P_WIDEKEY_ONLY = PROLOGUE % (1, 1) + """   modes(1) = 0
   sortinit 1, modes
   for i = 1 to 12
      keys(1) = str('y', 35000):right('0':mod(i * 5, 13), 2)
      sortadd keys
   next i
   all = sortdata()
   n = status()
   sortclear
   crt '%s[=N=':n:' LEN=':len(all):' MD=':digest(all, 0, 'MD5'):']'
end
"""

# C7: null keys among others, no data element, by SORTDATA(), and by SORTNEXT() with a null key and null data
P_NULLS = PROLOGUE % (1, 1) + """   modes(1) = 0
   sortinit 1, modes
   keys(1) = ''; sortadd keys
   keys(1) = 'b'; sortadd keys
   keys(1) = 'a'; sortadd keys
   keys(1) = ''; sortadd keys
   keys(1) = 'ccc'; sortadd keys
   all = sortdata()
   n = status()
   sortclear
   convert @fm to '|' in all
   crt '%s[=N=':n:' DATA=':all:']'
   modes(1) = 8
   sortinit 1, modes
   keys(1) = ''; sortadd keys, ''
   keys(1) = 'q'; sortadd keys, 'dq'
   keys(1) = 'p'; sortadd keys, ''
   r = ''
   loop
      d = sortnext(keys)
   until status() do
      r := keys(1):'/':d:';'
   repeat
   sortclear
   crt '%sN[=':r:']'
end
"""


# C8: a UNIQUE sort (flag 4) of 600 items with 200 distinct keys.  On disk the duplicates lie in different work files; the old
# merge had no UNIQUE test and gave back all 600 (measured on HEAD ac509e4, 16 Oct 26; 200 in memory).
P_UNIQUE = PROLOGUE % (1, 1) + """   modes(1) = 8 + 4
   sortinit 1, modes
   for i = 1 to 600
      keys(1) = 'K':right('00':mod(i, 200), 3)
      sortadd keys, 'D':i
   next i
   allk = ''; n = 0
   loop
      d = sortnext(keys)
   until status() do
      allk := keys(1):@fm; n += 1
   repeat
   sortclear
   crt '%s[=N=':n:' MK=':digest(allk, 0, 'MD5'):']'
end
"""


def sorted_wide(n, keyfn):
    return sorted(range(1, n + 1), key=keyfn)


def expected():
    e = {}
    order = sorted(range(1, 301), key=lambda i: key5(i))
    data = [("D%d" % i).encode() for i in order]
    keys = [key5(i).encode() for i in order]
    e["small"] = "N=300 MD=%s MK=%s" % (md5(b"".join(d + FM for d in data)), md5(b"".join(k + FM for k in keys)))

    suffix = lambda i: "%02d" % ((i * 5) % 13)
    o12 = sorted(range(1, 13), key=lambda i: "K" + suffix(i))
    wd = [(chr(64 + i) * (40000 + 137 * i)).encode() for i in o12]
    e["widedata"] = "N=12 LENS=%s MD=%s" % ("".join("%d," % len(d) for d in wd), md5(b"".join(d + FM for d in wd)))
    e["widedata_all"] = "N=12 LEN=%d MD=%s" % (sum(len(d) for d in wd) + 11, md5(FM.join(wd)))

    ok = sorted(range(1, 13), key=lambda i: suffix(i))
    k1 = [("x" * 40000 + suffix(i)).encode() for i in ok]
    k2 = [("z%d" % i).encode() for i in ok]
    e["widekey"] = "N=12 ORDER=%s K1=%s K1LEN=%d K2=%s" % (
        "".join("W%d," % i for i in ok), md5(b"".join(k + FM for k in k1)), 40002, md5(b"".join(k + FM for k in k2)))

    ky = [("y" * 35000 + suffix(i)).encode() for i in ok]
    e["widekey_only"] = "N=12 LEN=%d MD=%s" % (sum(len(k) for k in ky) + 11, md5(FM.join(ky)))
    e["unique"] = "N=200 MK=%s" % md5(b"".join(("K%03d" % v).encode() + FM for v in range(200)))
    return e


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) != 1:
        bail("usage: sandbox-sortwide.py <dir> [--build]")
    box = os.path.abspath(args[0])
    sysd = os.path.join(box, "sys")
    say("sandbox-sortwide: sandbox %s" % box)
    if "--build" in sys.argv:
        if os.path.exists(box) and os.listdir(box):
            bail("%s is not empty" % box)
        r = tool(box, "all")
        if "[FAIL]" in r.stdout or r.returncode != 0 or "[PASS] THIRD.COMPILE" not in r.stdout:
            bail("the sandbox build did not pass:\n" + r.stdout[-800:])
        say("sandbox-sortwide: built, bootstrap passed")
    elif not os.path.isfile(os.path.join(sysd, "bin", "sd")):
        bail("%s holds no built sandbox (use --build, or point it at one)" % box)

    progs = [("zzsw1", P_SMALL % "C01"), ("zzsw3", P_WIDEDATA % "C03"), ("zzsw4", P_WIDEKEY % "C04"),
             ("zzsw5", P_WIDEDATA_ALL % "C05"), ("zzsw6", P_WIDEKEY_ONLY % "C06"), ("zzsw7", P_NULLS % ("C07", "C07")),
             ("zzsw8", P_UNIQUE % "C08")]
    cmds = []
    for nm, text in progs:
        with open(os.path.join(sysd, "bp", nm), "w") as f:
            f.write(text)
        made.append(nm)
        cmds += ["BASIC bp %s" % nm]
    runs = ["RUN bp %s" % nm for nm, _ in progs]
    exp = expected()

    def tag(out, t):
        m = re.search(r"(?m)^%s\[=(.*)\]\s*$" % t, out)
        return m.group(1) if m else None

    try:
        say("\n--- SORTMEM as built (the sort stays in memory) ---------------------------------------")
        if not restart(box):
            bail("SD does not start with the sandbox's own sd.conf")
        out = isess(box, *(cmds + runs))
        n = len(re.findall(r"(?m)^Compiled 1 program\(s\) with no errors", out))
        if n != len(progs):
            bail("%d of %d programs compiled:\n%s" % (n, len(progs), out[-1500:]))
        mem = {t: tag(out, t) for t in ("C01", "C03", "C04", "C05", "C06", "C07", "C08")}
        mem7n = tag(out, "C07N")
        say("    in memory, SORTMEM: %s" % (re.search(r"MEM=(\d+)", mem["C01"] or "") or [None, "?"])[1])
        row("CONTROL 1  300 small items, in memory", mem["C01"] is not None and mem["C01"].startswith(exp["small"]),
            "got %r wanted %r" % (mem["C01"], exp["small"]))
        row("CONTROL 3  12 items of 40 kb, in memory", mem["C03"] == exp["widedata"], "got %r" % mem["C03"])
        row("CONTROL 4  12 keys of 40 kb, in memory", mem["C04"] == exp["widekey"], "got %r" % mem["C04"])
        row("CONTROL 5  12 items of 40 kb by SORTDATA(), in memory", mem["C05"] == exp["widedata_all"], "got %r" % mem["C05"])
        row("CONTROL 6  12 keys of 35 kb, no data element, by SORTDATA(), in memory", mem["C06"] == exp["widekey_only"],
            "got %r" % mem["C06"])
        row("CONTROL 8  UNIQUE sort of 600 items with 200 distinct keys, in memory", mem["C08"] == exp["unique"],
            "got %r wanted %r" % (mem["C08"], exp["unique"]))

        say("\n--- SORTMEM=1 (every item goes to a work file, and the files are merged) ----------------")
        if not restart(box, "SORTMEM=1"):
            bail("SD does not start with SORTMEM=1")
        # one session per program: a build that hangs on one of them (the int16 lengths made it spin) must not hide the rest
        out = ""
        for r in runs:
            out += isess(box, r) + "\n"
        dsk = {t: tag(out, t) for t in ("C01", "C03", "C04", "C05", "C06", "C07", "C08")}
        dsk7n = tag(out, "C07N")
        say("    on disk, SORTMEM: %s" % (re.search(r"MEM=(\d+)", dsk["C01"] or "") or [None, "?"])[1])
        row("the instrument: SORTMEM=1 reached the process (so the rows below ran on disk)",
            dsk["C01"] is not None and "MEM=1" in dsk["C01"], "got %r" % dsk["C01"])
        row("CONTROL 2  300 small items, on disk (many work files merged)",
            dsk["C01"] is not None and dsk["C01"].startswith(exp["small"]), "got %r wanted %r" % (dsk["C01"], exp["small"]))
        row("455  12 items of 40 kb and more by SORTNEXT(), on disk", dsk["C03"] == exp["widedata"], "got %r" % dsk["C03"])
        row("455  12 keys of 40 kb with a differing tail, on disk: order and the keys read back whole", dsk["C04"] == exp["widekey"],
            "got %r" % dsk["C04"])
        row("455  12 items of 40 kb by SORTDATA(), on disk", dsk["C05"] == exp["widedata_all"], "got %r" % dsk["C05"])
        row("455  12 keys of 35 kb, no data element, by SORTDATA(), on disk", dsk["C06"] == exp["widekey_only"],
            "got %r" % dsk["C06"])
        row("UNIQUE sort of 600 items with 200 distinct keys, on disk: the duplicates in different work files are dropped by the merge "
            "(HEAD ac509e4 gave all 600 back)", dsk["C08"] == exp["unique"], "got %r wanted %r" % (dsk["C08"], exp["unique"]))
        row("null keys and null data: the disk sort gives what the memory sort gives (SORTDATA())",
            dsk["C07"] is not None and dsk["C07"] == mem["C07"], "disk %r memory %r" % (dsk["C07"], mem["C07"]))
        row("null keys and null data: the disk sort gives what the memory sort gives (SORTNEXT())",
            dsk7n is not None and dsk7n == mem7n, "disk %r memory %r" % (dsk7n, mem7n))
        say("    null rows read: memory %r / %r" % (mem["C07"], mem7n))

        left = []
        for dp, _dn, fn in os.walk(box):
            left += [os.path.join(dp, f) for f in fn if f.startswith("~SDS")]
        row("no sort work file is left behind (%d found)" % len(left), not left, ", ".join(left[:3]))
    finally:
        restart(box)
        for nm in made:
            for d in ("bp", "bp.out"):
                p = os.path.join(sysd, d, nm)
                if os.path.exists(p):
                    os.remove(p)

    say("\nsandbox-sortwide: %d passed, %d failed" % (passed, failed))
    sys.exit(0 if failed == 0 else 1)


if __name__ == "__main__":
    main()
