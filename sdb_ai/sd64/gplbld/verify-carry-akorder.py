#!/usr/bin/env python3
#
# sandbox-akorder.py - the keys of a RIGHT JUSTIFIED index are in one total order (the empty key, numbers by value, text), BUILD.INDEX loses no id, and an index
# made before the change keeps working.  No install, no sudo.
#
#   python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/sandbox-akorder.py <dir> [--build]
#
# <dir> is a sandbox made by sandbox-fromtree.py.  With --build it is built first from THIS tree (it must be empty or absent); without it <dir> must already be built,
# which is how the same script is run against an OLD tree to prove it can fail.  Exit 0 every row passed, 1 a row failed, 2 it could not run.
#
# START-HISTORY:
# 25 Oct 26 dm  Written for the "total order for right justified index keys" (the owner: fix the four "your decision" items of the audit evaluation).  Until then a
#               right justified index (gplsrc/dh_ak.c compare()) took an empty key for 0 and a number of more than 9 digits or with a decimal point for TEXT, compared
#               a number with text as text (so "0010" < "11" < "1x" < "0010": the order depended on the order the keys were written in), and BUILD.INDEX
#               (sdsys/gpl.bp/mkindx) wrote the keys 1, 01 and 001 as three AKWRITEs of one key, each replacing the last: ids were lost.
#               A new right justified index now has the magic DH_INDEX2 and the flag AK_V2; an old one is left as it is.
# END-HISTORY
#
# WHAT IT MEASURES.  Every fixture is an index AMT on field 1 with the justification R (the dictionary format 10R); a left justified one is the control.
#   M  a MIXED list of 19 values - null, -4, 0, 0.5, 1 in four spellings (1.0, 1, 01, +1), 2, 3.14159, " 7", 9.5, 12.50, 21.5, 100, 1000.25, 1x, N/A, abc - written one
#      at a time into an index that already exists (WRITTEN) and built from the file (BUILT); both must give the same groups of ids in the same order:
#      [null] [-4] [0] [0.5] [1 in four spellings] [2] [3.14159] [7] [9.5] [12.50] [21.5] [100] [1000.25] [1x] [N/A] [abc]
#   N  numbers only (decimals included): SELECT ... WITH AMT > / >= / < / <= / = through the index (REQUIRE.INDEX, so that it IS the index) must equal the same
#      query with NO.INDEX, which reads the records, for both a WRITTEN and a BUILT index
#   C  the cyclic triple 0010, 11, 1x written in each of the six orders, one fixture each: every order gives 0010 11 1x (the old comparator gave three different
#      orders, the tree's shape deciding)
#   L  an index of the OLD kind (a new empty one with its magic and flag put back by this script, as an index made before the change has them): 1, 01 and +1 are
#      one key, the empty key and 0 are one key, and it works as before; and a LEFT justified index is of the old kind too (magic 209C) and keeps byte order
#   The magic number and flag are read from the index subfile ON DISK, not assumed.  Row S0 is the control that the printing works.

import glob
import os
import re
import struct
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.path.join(HERE, "sandbox-fromtree.py")
ANSI = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]")
RUN = "%05d" % (os.getpid() % 100000)
passed = failed = 0
made = []

MAGIC_OLD, MAGIC_NEW, AK_V2 = 0x209C, 0x209E, 0x0100

# id, value
MIXED = [("r1", "21.5"), ("r2", "3.14159"), ("r3", "100"), ("r4", "9.5"), ("r5", "2"), ("r6", "1000.25"), ("r7", "-4"), ("r8", "0.5"), ("r9", "12.50"), ("r10", "0"),
         ("r11", ""), ("r12", "abc"), ("r13", "N/A"), ("r14", "1x"), ("r15", " 7"), ("r16", "1.0"), ("r17", "1"), ("r18", "01"), ("r19", "+1")]
MIXED_GROUPS = [["r11"], ["r7"], ["r10"], ["r8"], ["r16", "r17", "r18", "r19"], ["r5"], ["r2"], ["r15"], ["r4"], ["r9"], ["r1"], ["r3"], ["r6"], ["r14"], ["r13"], ["r12"]]
NUMERIC = [("r1", "21.5"), ("r2", "3.14159"), ("r3", "100"), ("r4", "9.5"), ("r5", "2"), ("r6", "1000.25"), ("r7", "-4"), ("r8", "0.5"), ("r9", "12.50"), ("r10", "0"),
           ("r11", "10"), ("r12", "3")]
QUERIES = ['AMT > "10"', 'AMT >= "9.5"', 'AMT < "3"', 'AMT <= "2"', 'AMT = "12.5"', 'AMT > "-4"', 'AMT < "0.5"']
CYCLE = [("r1", "0010"), ("r2", "11"), ("r3", "1x")]
CYCLE_ORDERS = [(0, 1, 2), (0, 2, 1), (1, 0, 2), (1, 2, 0), (2, 0, 1), (2, 1, 0)]
LEGACY = [("l1", "1"), ("l2", "01"), ("l3", "+1"), ("l4", ""), ("l5", "0"), ("l6", "2"), ("l7", "10"), ("l8", "9")]
LEFT = [("a1", "b"), ("a2", "a"), ("a3", "B"), ("a4", "10"), ("a5", "9"), ("a6", "")]


def say(s=""):
    print(s, flush=True)


def row(name, ok, detail=""):
    global passed, failed
    if ok:
        passed += 1
        say("  [PASS] " + name)
    else:
        failed += 1
        say("  [FAIL] " + name + ("   <- " + detail if detail else ""))


def bail(msg):
    say("sandbox-akorder: CANNOT RUN - " + msg)
    sys.exit(2)


def sess(box, *cmds):
    say("    > " + " | ".join(cmds))
    p = subprocess.run([sys.executable, TOOL, box, "sess", os.path.join(box, "user_accounts")] + list(cmds),
                       capture_output=True, text=True, errors="replace", timeout=900)
    out = ANSI.sub("", p.stdout + p.stderr)
    return out.split(":TERM 200,9999", 1)[-1]


def fname(tag):
    return "zzao%s%s" % (tag, RUN)


def prog_write(tag, items, justify="R"):
    """the dictionary item AMT, then the records one at a time (written before the index exists they are what BUILD.INDEX reads; written after it they are kept by the writes)"""
    out = "   open '%s' to f else stop 'no file'\n   open 'DICT %s' to d else stop 'no dict'\n" % (fname(tag), fname(tag))
    out += "   write 'D':@fm:'1':@fm:'':@fm:'Amt':@fm:'10%s':@fm:'S' on d, 'AMT'\n" % justify
    for i, v in items:
        out += "   write '%s' on f, '%s'\n" % (v, i)
    out += "end\n"
    return out


def prog_show(tag, name):
    """prints every key of the index in the index's own order with the ids of each: SC[key=id,id|key=id...]"""
    return ("   open '%s' to f else stop 'no file'\n"
            "   selectindex 'AMT' from f to 5\n   readlist keys from 5 else keys = ''\n   x = ''\n"
            "   for i = 1 to dcount(keys, @fm)\n      k = keys<i>\n      selectindex 'AMT', k from f to 6\n      readlist l from 6 else l = ''\n"
            "      x := k:'=':change(l, @fm, ','):'|'\n   next i\n   crt 'SC[':x:']'\n   crt 'NK[':dcount(keys, @fm):']'\nend\n" % fname(tag))


def prog_queries(tag, queries):
    out = "   open '%s' to f else stop 'no file'\n" % fname(tag)
    for n, q in enumerate(queries):
        for variant, extra in (("I", " REQUIRE.INDEX"), ("N", " NO.INDEX")):
            out += "   execute 'SELECT %s WITH %s%s' capturing junk\n   readlist l from 0 else l = ''\n   crt 'Q%s%d[':change(l, @fm, ','):']'\n   crt 'M%s%d[':oconv(junk, 'MCP'):']'\n" % (
                fname(tag), q.replace("'", ""), extra, variant, n, variant, n)
    out += "end\n"
    return out


def parse_sc(out):
    m = re.search(r"(?m)^SC\[(.*)\]\s*$", out)
    if not m:
        return None
    groups = []
    for part in m.group(1).split("|"):
        if "=" in part:
            k, v = part.split("=", 1)
            groups.append((k, sorted(i for i in v.split(",") if i)))
    return groups


SEEN = []   # what read_ak_header looked at last: (path, first four bytes in hex), for the detail of a row that finds nothing


def read_ak_header(box, tag):
    """(magic, flags) of the first index subfile of fixture `tag`, read from the disk; None when it cannot be found"""
    del SEEN[:]
    # the session's own account is where CREATE.FILE puts the fixture: SDSYS's directory (sys) as the administrator, user_accounts otherwise.
    # File names are lower case on disk whatever case CREATE.FILE was given.
    for d in ("sys", "user_accounts"):
        acct = os.path.join(box, d)
        low = fname(tag).lower()
        for path in sorted(glob.glob(os.path.join(acct, low, "*")) + glob.glob(os.path.join(acct, low + "*"))):
            if os.path.isfile(path):
                with open(path, "rb") as fh:
                    head = fh.read(4)
                SEEN.append((path[len(box) + 1:], head.hex()))
                if len(head) == 4:
                    magic, flags = struct.unpack("<HH", head)
                    if magic in (MAGIC_OLD, MAGIC_NEW):
                        return path, magic, flags
    if not SEEN:
        SEEN.append(("no file named for the fixture under sys or user_accounts; sys holds", sorted(f for f in os.listdir(os.path.join(box, "sys")) if f.startswith("zz"))[:12]))
    return None


def patch_ak_header(path, magic, flags_clear):
    with open(path, "r+b") as fh:
        head = fh.read(4)
        mg, fl = struct.unpack("<HH", head)
        fh.seek(0)
        fh.write(struct.pack("<HH", magic, fl & ~flags_clear))


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) != 1:
        bail("usage: sandbox-akorder.py <dir> [--build]")
    box = os.path.abspath(args[0])
    sysd = os.path.join(box, "sys")
    say("sandbox-akorder: sandbox %s" % box)
    say("sandbox-akorder: tree    %s" % os.path.dirname(HERE))
    if "--build" in sys.argv:
        if os.path.exists(box) and os.listdir(box):
            bail("%s is not empty" % box)
        r = subprocess.run([sys.executable, TOOL, box, "all"], capture_output=True, text=True, errors="replace", timeout=1800)
        if "[FAIL]" in r.stdout or r.returncode != 0 or "[PASS] THIRD.COMPILE" not in r.stdout:
            bail("the sandbox build did not pass:\n" + r.stdout[-800:])
        say("sandbox-akorder: built, bootstrap passed")
    elif not os.path.isfile(os.path.join(sysd, "bin", "sd")):
        bail("%s holds no built sandbox (use --build, or point it at one)" % box)
    subprocess.run([sys.executable, TOOL, box, "start"], capture_output=True, text=True, errors="replace", timeout=120)

    files = []
    progs = {}

    def prog(name, text):
        progs[name] = text

    def fixture(tag):
        files.append(fname(tag))

    # --- the programs -------------------------------------------------------------------------------------------------
    for tag in ("M1", "M2", "N1", "N2", "L1", "R1", "A1"):
        fixture(tag)
    prog("zzaow_m1", prog_write("M1", MIXED))                # the dictionary item and the records; the index is built from them
    prog("zzaow_m2", prog_write("M2", []))                   # the dictionary item only: the records are written after the index exists
    prog("zzaos_m1", prog_show("M1", "AMT"))
    prog("zzaos_m2", prog_show("M2", "AMT"))
    prog("zzaow_n1", prog_write("N1", NUMERIC))
    prog("zzaow_n2", prog_write("N2", []))
    prog("zzaoq_n1", prog_queries("N1", QUERIES))
    prog("zzaoq_n2", prog_queries("N2", QUERIES))
    prog("zzaow_l1", prog_write("L1", []))
    prog("zzaos_l1", prog_show("L1", "AMT"))
    prog("zzaow_r1", prog_write("R1", []))
    prog("zzaos_r1", prog_show("R1", "AMT"))
    prog("zzaow_a1", prog_write("A1", [], "L"))
    prog("zzaos_a1", prog_show("A1", "AMT"))
    for k, order in enumerate(CYCLE_ORDERS):
        tag = "C%d" % k
        fixture(tag)
        prog("zzaow_c%d" % k, prog_write(tag, []))
        prog("zzaos_c%d" % k, prog_show(tag, "AMT"))
    # online writers: a separate program that only writes records (the dictionary item is written by the zzaow_* above, which has no records)
    def only_records(tag, items):
        return ("   open '%s' to f else stop 'no file'\n" % fname(tag)) + "".join("   write '%s' on f, '%s'\n" % (v, i) for i, v in items) + "end\n"
    prog("zzaor_m2", only_records("M2", MIXED))
    prog("zzaor_n2", only_records("N2", NUMERIC))
    prog("zzaor_l1", only_records("L1", LEGACY))
    prog("zzaor_r1", only_records("R1", [("e1", "1"), ("e2", "01"), ("e3", ""), ("e4", "0")]))
    prog("zzaor_a1", only_records("A1", LEFT))
    for k, order in enumerate(CYCLE_ORDERS):
        prog("zzaor_c%d" % k, only_records("C%d" % k, [CYCLE[j] for j in order]))
    for nm, body in progs.items():
        with open(os.path.join(sysd, "bp", nm), "w") as fh:
            fh.write(body)
        made.append(nm)

    try:
        say("\n--- the fixtures --------------------------------------------------------------------------------------------")
        cmds = ["DELETE.FILE %s" % f for f in files] + ["CREATE.FILE %s" % f for f in files] + ["BASIC bp %s" % nm for nm in progs]
        out = sess(box, *cmds)
        clean = len(re.findall(r"(?m)^Compiled 1 program\(s\) with no errors", out))
        row("setup: the %d programs compiled with no errors" % len(progs), clean == len(progs), "clean compiles: %d of %d" % (clean, len(progs)))
        if clean != len(progs):
            bail("the programs did not compile:\n" + out[-800:])

        # M1: records first, then the index built from them.  M2: the index first (dictionary item only), then the records written one at a time.
        sess(box, "RUN bp zzaow_m1", "CREATE.INDEX %s AMT" % fname("M1"), "BUILD.INDEX %s AMT" % fname("M1"))
        sess(box, "RUN bp zzaow_m2", "CREATE.INDEX %s AMT" % fname("M2"), "BUILD.INDEX %s AMT" % fname("M2"), "RUN bp zzaor_m2")
        built = parse_sc(sess(box, "RUN bp zzaos_m1"))
        written = parse_sc(sess(box, "RUN bp zzaos_m2"))
        for nm, g in (("BUILT", built), ("WRITTEN", written)):
            say("    %s: %r" % (nm, g))
        if built is None or written is None or len(built) < 3:
            bail("S0 control: the index scan printed nothing usable - the fixture or the printing is wrong, so no verdict would mean anything")
        row("S0 (control): the scan lists keys with ids for both fixtures", True)
        want = [tuple(g) for g in MIXED_GROUPS]
        row("M1: a BUILT index of a mixed list holds the groups of ids in the total order", built is not None and [tuple(i) for _, i in built] == want,
            "got %r" % [i for _, i in built or []])
        row("M2: a WRITTEN index of a mixed list holds the same groups in the same order", written is not None and [tuple(i) for _, i in written] == want,
            "got %r" % [i for _, i in written or []])
        row("M3: BUILT and WRITTEN are the same (no id lost by the build)", built is not None and written is not None and [i for _, i in built] == [i for _, i in written])
        hdr = read_ak_header(box, "M2")
        row("M4: the index subfile on disk has the new magic number 209E and the AK_V2 flag", hdr is not None and hdr[1] == MAGIC_NEW and (hdr[2] & AK_V2) != 0,
            "header %r, files seen %r" % (hdr, SEEN))

        say("\n--- numbers only: the query through the index equals the query on the records -------------------------------------")
        sess(box, "RUN bp zzaow_n1", "CREATE.INDEX %s AMT" % fname("N1"), "BUILD.INDEX %s AMT" % fname("N1"))
        sess(box, "RUN bp zzaow_n2", "CREATE.INDEX %s AMT" % fname("N2"), "BUILD.INDEX %s AMT" % fname("N2"), "RUN bp zzaor_n2")
        for tag, nm in (("N1", "BUILT"), ("N2", "WRITTEN")):
            out = sess(box, "RUN bp zzaoq_%s" % tag.lower())
            for n, q in enumerate(QUERIES):
                mi = re.search(r"(?m)^QI%d\[(.*)\]\s*$" % n, out)
                mn = re.search(r"(?m)^QN%d\[(.*)\]\s*$" % n, out)
                msg = re.search(r"(?m)^MI%d\[(.*)\]\s*$" % n, out)
                if not mi or not mn:
                    row("N %s %s: the query printed its lists" % (nm, q), False, out[-300:])
                    continue
                a = sorted(x for x in mi.group(1).split(",") if x)
                b = sorted(x for x in mn.group(1).split(",") if x)
                row("N %-7s %-14s through the index %s, on the records %s" % (nm, q, a, b), a == b and len(b) > 0,
                    "index %s records %s  (what REQUIRE.INDEX printed: %s)" % (a, b, msg.group(1)[:80] if msg else "-"))

        say("\n--- the cyclic triple 0010 / 11 / 1x in every order of writing -------------------------------------------------")
        orders = []
        for k, order in enumerate(CYCLE_ORDERS):
            tag = "C%d" % k
            sess(box, "RUN bp zzaow_c%d" % k, "CREATE.INDEX %s AMT" % fname(tag), "BUILD.INDEX %s AMT" % fname(tag), "RUN bp zzaor_c%d" % k)
            g = parse_sc(sess(box, "RUN bp zzaos_c%d" % k))
            orders.append([i for _, i in g] if g else None)
            say("    written in the order %s: %r" % ([CYCLE[j][1] for j in order], orders[-1]))
        wantc = [["r1"], ["r2"], ["r3"]]
        row("C: every order of writing gives 0010, 11, 1x", all(o == wantc for o in orders), "orders %r" % orders)

        say("\n--- an index of the OLD kind keeps working ------------------------------------------------------------------------")
        sess(box, "RUN bp zzaow_l1", "CREATE.INDEX %s AMT" % fname("L1"), "BUILD.INDEX %s AMT" % fname("L1"))
        h = read_ak_header(box, "L1")
        if h is None:
            row("L0: the new empty index of the legacy fixture can be found on disk", False, "files seen %r" % (SEEN,))
        else:
            path, mg, fl = h
            patch_ak_header(path, MAGIC_OLD, AK_V2)
            h2 = read_ak_header(box, "L1")
            row("L0: its magic is put back to 209C and AK_V2 cleared, as the disk shows", h2 is not None and h2[1] == MAGIC_OLD and (h2[2] & AK_V2) == 0, "header %r" % (h2,))
            sess(box, "RUN bp zzaor_l1")
            g = parse_sc(sess(box, "RUN bp zzaos_l1"))
            say("    old kind: %r" % g)
            groups = [tuple(i) for _, i in g or []]
            row("L1: in the old kind 1, 01 and +1 are one key", ("l1", "l2", "l3") in groups, "groups %r" % groups)
            row("L2: in the old kind the empty key and 0 are one key (the old behaviour, kept for an index made before)", ("l4", "l5") in groups, "groups %r" % groups)
            row("L3: in the old kind the order is by value: 0, 1, 2, 9, 10", groups == [("l4", "l5"), ("l1", "l2", "l3"), ("l6",), ("l8",), ("l7",)], "groups %r" % groups)
        sess(box, "RUN bp zzaow_r1", "CREATE.INDEX %s AMT" % fname("R1"), "BUILD.INDEX %s AMT" % fname("R1"), "RUN bp zzaor_r1")
        g = parse_sc(sess(box, "RUN bp zzaos_r1"))
        groups = [tuple(i) for _, i in g or []]
        say("    new kind: %r" % g)
        row("L4: in the new kind the empty key and 0 are two keys, and 1 and 01 are one", ("e3",) in groups and ("e4",) in groups and ("e1", "e2") in groups, "groups %r" % groups)
        sess(box, "RUN bp zzaow_a1", "CREATE.INDEX %s AMT" % fname("A1"), "BUILD.INDEX %s AMT" % fname("A1"), "RUN bp zzaor_a1")
        h = read_ak_header(box, "A1")
        g = parse_sc(sess(box, "RUN bp zzaos_a1"))
        say("    left justified: %r" % g)
        keys = [k for k, _ in g or []]
        row("L5: a LEFT justified index keeps the old magic 209C and sorts by bytes", h is not None and h[1] == MAGIC_OLD and keys == ["", "10", "9", "B", "a", "b"], "header %r keys %r, files seen %r" % (h, keys, SEEN))
    finally:
        say("\n--- cleanup -------------------------------------------------------------------------------------")
        sess(box, *["DELETE.FILE %s" % f for f in files])
        for nm in made:
            for d in ("bp", "bp.out"):
                pth = os.path.join(sysd, d, nm)
                if os.path.exists(pth):
                    os.remove(pth)
        left = [f for f in files if any(os.path.exists(os.path.join(box, d, f)) for d in ("sys", "user_accounts"))]
        row("cleanup: the fixture files are gone", not left, " ".join(left))

    say("\nsandbox-akorder: %d passed, %d failed" % (passed, failed))
    if passed + failed == 0:
        bail("no row ran - a broken test, not a pass")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
