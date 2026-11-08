#!/usr/bin/env python3
#
# sandbox-crlf.py - the line terminator modes of directory files and sequential files: FCONTROL(fvar, FC$CRLF, mode) and the letters
#                   L C B X in field 6 of an F-type VOC entry (QM4 Fixes item 452, openQM 4), measured by the BYTES ON DISK.
#
#   python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/sandbox-crlf.py <dir> [--build]
#
# <dir> is a sandbox made by sandbox-fromtree.py (needs no install, no sudo).  With --build it is built first from THIS tree (it
# must be empty or absent).  Exit 0 every row passed, 1 a row failed, 2 it could not run.
#
# START-HISTORY:
# 16 Oct 26 dm  New.
# END-HISTORY
#
# THE INSTRUMENT.  The expected values are made HERE, in Python, by a reference that reads the whole record at once (ref_lines());
# SD reads it in chunks of up to 31,744 bytes, which is what the boundary cases are for.  Reads: Python puts the record's bytes on
# disk, a BASIC program reads it in each mode and prints its length and MD5; Python compares with the reference.  Writes: a BASIC
# program writes, Python reads the bytes back off the disk.  The first thing every leg does is check that the file it works on is
# where the sandbox says it is (a test that read nothing must not pass).
#
# The modes (openQM manual, "Line Terminator Selection"):
#   0 LF    LF ends a line, CR is data.                         1 CRLF  CR LF ends a line; a lone CR or LF is data.
#   2 BOTH  CR LF or LF ends a line; a lone CR is data.         3 NOCR  LF ends a line; every CR is thrown away.
# Not set at all (no FCONTROL, no letter) is the old behaviour: a directory file READ is mode 0, WRITE ends a line with LF, and
# READSEQ is mode 2.  The last line end of a record is not a field mark ("a" + terminator reads as "a").
#
#   1  FCONTROL(fvar, FC$CRLF, ...): the mode it was in, -1 asks, a value outside 0-3 is STATUS 1 and changes nothing, a hashed file
#   2  directory READ in each mode against the reference: hand cases, 60 random ones, and records that put a CR, an LF, a CR LF and
#      the last line end across the boundary between two chunks
#   3  directory WRITE in each mode: the bytes on disk (CR LF only in mode 1), an empty record, empty fields, a CR in the data
#   4  READSEQ in each mode against the reference, and WRITESEQ bytes on disk
#   5  the letters L C B X (and a lower case one) in the VOC entry: OPEN and OPENSEQ start in that mode; a hashed file ignores them
#   6  MARK.MAPPING OFF (image mode): no mode changes a byte, either way

import hashlib
import os
import random
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.path.join(HERE, "sandbox-fromtree.py")
ANSI = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]")
FM = b"\xfe"
CHUNK = 31744          # op_dio3.c MAX_T1_BUFFER_SIZE: a directory record is read this many bytes at a time
passed = failed = 0


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
    say("sandbox-crlf: CANNOT RUN - " + msg)
    sys.exit(2)


def sess(box, *cmds, quiet=True):
    p = subprocess.run([sys.executable, TOOL, box, "sess", os.path.join(box, "user_accounts")] + list(cmds),
                       capture_output=True, text=True, errors="replace", timeout=900)
    out = ANSI.sub("", p.stdout + p.stderr).split(":TERM 200,9999", 1)[-1]
    if not quiet:
        for line in out.splitlines():
            if line.strip() and not line.startswith(":") and not line.startswith("exit "):
                say("      | " + line.rstrip()[:130])
    return out


def got(out, tag):
    m = re.findall(re.escape(tag) + r"\[([^\]]*)\]", out)
    return m[-1] if m else None


# ---- the reference: a whole record at once -------------------------------------------------------------------------------

def lines_of(mode, data):
    """(lines ended by a terminator, the unfinished last line, whether the data ends in a terminator)"""
    out, cur, ended = [], bytearray(), False
    i, n = 0, len(data)
    while i < n:
        c = data[i]
        if mode == 0:
            if c == 10:
                out.append(bytes(cur)); cur = bytearray(); ended = True
            else:
                cur.append(c); ended = False
            i += 1
        elif mode == 1:
            if c == 13 and i + 1 < n and data[i + 1] == 10:
                out.append(bytes(cur)); cur = bytearray(); ended = True; i += 2
            else:
                cur.append(c); ended = False; i += 1
        elif mode == 2:
            if c == 10:
                if cur.endswith(b"\r"):
                    cur = cur[:-1]
                out.append(bytes(cur)); cur = bytearray(); ended = True
            else:
                cur.append(c); ended = False
            i += 1
        else:
            if c == 13:
                pass
            elif c == 10:
                out.append(bytes(cur)); cur = bytearray(); ended = True
            else:
                cur.append(c); ended = False
            i += 1
    return out, bytes(cur), ended


def ref_read(mode, data):
    """The record a READ gives for these bytes: lines joined by field marks, the last line end not a field mark."""
    out, cur, ended = lines_of(mode, data)
    if cur or not ended:
        out.append(cur)
    return FM.join(out)


def ref_seq(mode, data):
    """The lines READSEQ gives, one after another, until it runs out."""
    if mode == 3:
        data = data.replace(b"\r", b"")  # every CR is thrown away, so "a LF CR" is "a LF" and "CR" is an empty file
        mode = 0
    if not data:
        return []
    out, cur, ended = lines_of(mode, data)
    if cur or not ended:
        out.append(cur)
    return out


def esc(b):
    return b.replace(b"\r", b"<CR>").replace(b"\n", b"<LF>").decode("latin-1")


# ---- the cases -----------------------------------------------------------------------------------------------------------

HAND = [b"", b"abc", b"abc\n", b"abc\r\n", b"a\nb", b"a\r\nb\r\n", b"a\rb", b"a\r", b"\r", b"\n", b"\r\n", b"\r\r\n", b"a\n\n",
        b"a\r\n\r\n", b"a\n\r\nb\n", b"a\r\n\rb", b"a\n\r", b"a\r\n\r", b"x\ry\nz\r\nw", b"\r\n\r\n\r\n", b"\n\r\n", b"one\r\ntwo\r\n",
        b"one\ntwo\n", b"a\r\r\nb", b"\r\rx"]


def random_cases(count=60):
    rnd = random.Random(452)
    alphabet = [b"a", b"b", b"\r", b"\n", b"\r\n"]
    cases = []
    for _ in range(count):
        cases.append(b"".join(rnd.choice(alphabet) for _ in range(rnd.randint(0, 24))))
    return cases


def boundary_cases():
    """Records over 31,744 bytes whose first chunk ends at a CR / LF / CR LF / terminator and whose second chunk goes on."""
    cases = []
    for pad in (CHUNK - 3, CHUNK - 2, CHUNK - 1, CHUNK):
        for tail in (b"\r\nz", b"\nz", b"\rz", b"\r\r\nz", b"\n\rz", b"\r\n", b"\n", b"\r", b"\n\n", b"\r\n\r\n", b"\n\r", b"\r\n\r",
                     b"zz\r\nyy\r\n"):
            cases.append(b"x" * pad + tail)
    # a record of many chunks with a line end every 77 bytes, and one with a line end only at the very end
    cases.append(b"".join(b"line%05d" % i + b"." * 60 + (b"\r\n" if i % 2 else b"\n") for i in range(1500)))
    cases.append(b"y" * (3 * CHUNK + 5) + b"\r\n")
    return cases


# ---- the BASIC programs --------------------------------------------------------------------------------------------------

def p_read(ids):
    return ("$include keys.h\n"
            "   open 'zzcl' to f else stop 'no file'\n"
            "   ids = '%s'\n   n = dcount(ids, ',')\n"
            "   for i = 1 to n\n      id = field(ids, ',', i)\n"
            "      read r from f, id else r = '*NOREC*'\n"
            "      crt 'RU ':id:' ':len(r):' ':digest(r, 0, 'MD5')\n   next i\n"
            "   for m = 0 to 3\n      void fcontrol(f, FC$CRLF, m)\n"
            "      for i = 1 to n\n         id = field(ids, ',', i)\n"
            "         read r from f, id else r = '*NOREC*'\n"
            "         crt 'R':m:' ':id:' ':len(r):' ':digest(r, 0, 'MD5')\n      next i\n   next m\nend\n" % ",".join(ids))


P_WRITE = """$include keys.h
   open 'zzcl' to f else stop 'no file'
   for m = -1 to 3
      if m >= 0 then void fcontrol(f, FC$CRLF, m)
      tag = if m < 0 then 'U' else m
      write 'a':@fm:'b':@fm:'c' to f, 'wa':tag
      write 'x':@fm:@fm:'y' to f, 'wb':tag
      write '' to f, 'wc':tag
      write 'p':char(13):'q':@fm:'r' to f, 'wd':tag
      write 'z':@fm to f, 'we':tag
   next m
   crt 'WRITE.DONE'
end
"""

P_FCON = """$include keys.h
   open 'zzcl' to f else stop 'no file'
   crt 'F1[':fcontrol(f, FC$CRLF, -1):'/':status():']'
   crt 'F2[':fcontrol(f, FC$CRLF, 3):'/':status():']'
   crt 'F3[':fcontrol(f, FC$CRLF, -1):'/':status():']'
   crt 'F4[':fcontrol(f, FC$CRLF, 1):'/':status():']'
   crt 'F5[':fcontrol(f, FC$CRLF, 4):'/':status():']'
   crt 'F6[':fcontrol(f, FC$CRLF, -2):'/':status():']'
   crt 'F7[':fcontrol(f, FC$CRLF, -1):'/':status():']'
   open 'zzcl' to g else stop 'no file again'
   crt 'F8[':fcontrol(g, FC$CRLF, -1):']'
   open 'zzclh' to h else stop 'no hashed'
   crt 'F9[':fcontrol(h, FC$CRLF, -1):'/':status():']'
   openseq 'zzcl', 'sqnew' to s then null else
      create s else stop 'no create'
   end
   crt 'F10[':fcontrol(s, FC$CRLF, -1):'/':status():']'
   crt 'F11[':fcontrol(s, FC$CRLF, 0):'/':status():']'
   crt 'F12[':fcontrol(s, FC$CRLF, -1):'/':status():']'
   crt 'F13[':fcontrol(s, FC$CRLF, 7):'/':status():']'
   close s
end
"""


def p_readseq(ids):
    return ("$include keys.h\n"
            "   ids = '%s'\n   n = dcount(ids, ',')\n"
            "   for m = -1 to 3\n"
            "      for i = 1 to n\n         id = field(ids, ',', i)\n"
            "         openseq 'zzcl', id to s else stop 'no seq ':id\n"
            "         if m >= 0 then void fcontrol(s, FC$CRLF, m)\n"
            "         tag = if m < 0 then 'U' else m\n"
            "         k = 0\n"
            "         loop\n            readseq line from s else exit\n            k += 1\n"
            "            line = change(change(line, char(13), '<CR>'), char(10), '<LF>')\n"
            "            crt 'S':tag:' ':id:' ':k:' ':line\n         repeat\n"
            "         crt 'SN':tag:' ':id:' ':k\n         close s\n"
            "      next i\n   next m\nend\n" % ",".join(ids))


P_WRITESEQ = """$include keys.h
   for m = -1 to 3
      tag = if m < 0 then 'U' else m
      openseq 'zzcl', 'sw':tag to s then null else
         create s else stop 'no create'
      end
      weofseq s
      if m >= 0 then void fcontrol(s, FC$CRLF, m)
      writeseq 'one' to s else stop 'w1'
      writeseq '' to s else stop 'w2'
      writeseq 'three':char(13):'x' to s else stop 'w3'
      close s
   next m
   crt 'WRITESEQ.DONE'
end
"""

P_VOCSET = """   read v from @voc, 'zzcl' else stop 'no voc entry'
   v<6> = '%s'
   write v to @voc, 'zzcl'
   crt 'VOC6 ':v<1>:' ':'%s'
end
"""

P_VOCMODE = """$include keys.h
   open 'zzcl' to f else stop 'no file'
   crt 'V1[':fcontrol(f, FC$CRLF, -1):']'
   openseq 'zzcl', 'sqvoc' to s then null else
      create s else stop 'no create'
   end
   weofseq s
   crt 'V2[':fcontrol(s, FC$CRLF, -1):']'
   writeseq 'k' to s else stop 'w'
   close s
   write 'u':@fm:'v' to f, 'vocdir'
   crt 'V3 done'
end
"""

P_VOCHASH = """$include keys.h
   open 'zzclh' to h else stop 'no hashed'
   crt 'VH[':fcontrol(h, FC$CRLF, -1):'/':status():']'
end
"""

P_IMAGE = """$include keys.h
   open 'zzcl' to f else stop 'no file'
   for m = 0 to 3
      void fcontrol(f, FC$CRLF, m)
      mark.mapping f, off
      write 'a':@fm:'b':char(13):char(10):'c' to f, 'im':m
      read r from f, 'imr' else r = '*NOREC*'
      crt 'IM':m:' ':len(r):' ':digest(r, 0, 'MD5')
      mark.mapping f, on
   next m
end
"""


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) != 1:
        bail("usage: sandbox-crlf.py <dir> [--build]")
    box = os.path.abspath(args[0])
    sysd = os.path.join(box, "sys")
    bp = os.path.join(sysd, "bp")
    acct = sysd  # the session runs in the SDSYS account (the sandbox user plays sdsys): that is where CREATE.FILE puts a file
    say("sandbox-crlf: sandbox %s" % box)
    if "--build" in sys.argv:
        if os.path.exists(box) and os.listdir(box):
            bail("%s is not empty" % box)
        r = subprocess.run([sys.executable, TOOL, box, "all"], capture_output=True, text=True, errors="replace", timeout=900)
        if "[FAIL]" in r.stdout or r.returncode != 0 or "[PASS] THIRD.COMPILE" not in r.stdout:
            bail("the sandbox build did not pass:\n" + r.stdout[-800:])
        say("sandbox-crlf: built, bootstrap passed")
    elif not os.path.isfile(os.path.join(sysd, "bin", "sd")):
        bail("%s holds no built sandbox (use --build, or point it at one)" % box)
    subprocess.run([sys.executable, TOOL, box, "start"], capture_output=True, text=True, errors="replace", timeout=120)

    made = []

    def prog(name, text):
        with open(os.path.join(bp, name), "w") as f:
            f.write(text)
        made.append(name)

    def compile_ok(names):
        out = sess(box, *["BASIC bp " + n for n in names])
        n = len(re.findall(r"(?m)^Compiled 1 program\(s\) with no errors", out))
        return n == len(names), out

    try:
        sess(box, "DELETE.FILE zzcl", "DELETE.FILE zzclh", "CREATE.FILE zzcl DIRECTORY", "CREATE.FILE zzclh")
        d = os.path.join(acct, "zzcl")
        if not os.path.isdir(d):
            bail("CREATE.FILE zzcl DIRECTORY did not make %s (the instrument would read nothing)" % d)

        cases = HAND + random_cases() + boundary_cases()
        ids = ["c%03d" % i for i in range(len(cases))]
        for i, data in zip(ids, cases):
            with open(os.path.join(d, i), "wb") as f:
                f.write(data)
        small = [i for i, c in zip(ids, cases) if len(c) < 200]
        say("sandbox-crlf: %d records on disk (%d under 200 bytes, %d of %d or more bytes)"
            % (len(cases), len(small), len(cases) - len(small), 200))

        # --- leg 1 ---------------------------------------------------------------------------------------------------------
        say("\n--- leg 1: FCONTROL(fvar, FC$CRLF, ...) ---------------------------------------------------------------")
        prog("zzcl_fc", P_FCON)
        ok, o = compile_ok(["zzcl_fc"])
        if not ok:
            bail("zzcl_fc does not compile:\n" + o[-600:])
        out = sess(box, "RUN bp zzcl_fc")
        row("a directory file starts in mode 0 (LF), STATUS 0", got(out, "F1") == "0/0", "got %r" % got(out, "F1"))
        row("setting 3 gives the mode it was in, 0", got(out, "F2") == "0/0", "got %r" % got(out, "F2"))
        row("-1 asks and says 3 now", got(out, "F3") == "3/0", "got %r" % got(out, "F3"))
        row("setting 1 gives the 3 it was in", got(out, "F4") == "3/0", "got %r" % got(out, "F4"))
        row("a mode of 4 changes nothing: it gives the 1 it is in, with STATUS 1", got(out, "F5") == "1/1", "got %r" % got(out, "F5"))
        row("so does -2", got(out, "F6") == "1/1", "got %r" % got(out, "F6"))
        row("and the mode is still 1", got(out, "F7") == "1/0", "got %r" % got(out, "F7"))
        row("a second file variable of the same file has its own mode (0)", got(out, "F8") == "0", "got %r" % got(out, "F8"))
        row("a hashed file gives 0 with STATUS 3004 (no line terminators)", got(out, "F9") == "0/3004", "got %r" % got(out, "F9"))
        row("a sequential file starts in mode 2 (BOTH: what READSEQ has always done)", got(out, "F10") == "2/0", "got %r" % got(out, "F10"))
        row("and takes a mode: 0 gives the 2 it was in, then asks 0", got(out, "F11") == "2/0" and got(out, "F12") == "0/0",
            "got %r %r" % (got(out, "F11"), got(out, "F12")))
        row("a mode of 7 on a sequential file: STATUS 1, mode kept", got(out, "F13") == "0/1", "got %r" % got(out, "F13"))

        # --- leg 2 ---------------------------------------------------------------------------------------------------------
        say("\n--- leg 2: directory READ, each mode against the reference ----------------------------------------------")
        prog("zzcl_rd", p_read(ids))
        ok, o = compile_ok(["zzcl_rd"])
        if not ok:
            bail("zzcl_rd does not compile:\n" + o[-600:])
        out = sess(box, "RUN bp zzcl_rd")
        seen = {}
        for m in re.finditer(r"(?m)^R(\w) (c\d+) (\d+) ([0-9a-f]{32})\s*$", out):
            seen[(m.group(1), m.group(2))] = (int(m.group(3)), m.group(4))
        row("the instrument: %d of %d reads came back (5 passes of %d records)" % (len(seen), 5 * len(ids), len(ids)),
            len(seen) == 5 * len(ids), "got %d" % len(seen))
        for label, mode in (("U", 0), ("0", 0), ("1", 1), ("2", 2), ("3", 3)):
            bad = []
            for i, data in zip(ids, cases):
                want = ref_read(mode, data)
                if seen.get((label, i)) != (len(want), hashlib.md5(want).hexdigest()):
                    bad.append("%s(%d bytes: got %r wanted len %d)" % (i, len(data), seen.get((label, i)), len(want)))
            name = {"U": "no mode set (the old reads: same as mode 0)", "0": "mode 0 (LF)", "1": "mode 1 (CRLF)", "2": "mode 2 (BOTH)",
                    "3": "mode 3 (NOCR)"}[label]
            row("READ, %s: all %d records as the reference" % (name, len(ids)), not bad, "; ".join(bad[:4]) + (" ... %d wrong" % len(bad) if len(bad) > 4 else ""))
        bnd = [i for i, c in zip(ids, cases) if len(c) > CHUNK]
        row("(the %d records over one chunk are the boundary cases, and are in every row above)" % len(bnd), len(bnd) >= 30, "got %d" % len(bnd))

        # --- leg 3 ---------------------------------------------------------------------------------------------------------
        say("\n--- leg 3: directory WRITE, the bytes on disk -------------------------------------------------------------")
        prog("zzcl_wr", P_WRITE)
        ok, o = compile_ok(["zzcl_wr"])
        if not ok:
            bail("zzcl_wr does not compile:\n" + o[-600:])
        out = sess(box, "RUN bp zzcl_wr")
        row("the writing program ran to its end", "WRITE.DONE" in out, out[-300:])

        def disk(name):
            p = os.path.join(d, name)
            return open(p, "rb").read() if os.path.exists(p) else None

        for tag, nl in (("U", b"\n"), ("0", b"\n"), ("1", b"\r\n"), ("2", b"\n"), ("3", b"\n")):
            want = {"wa": b"a" + nl + b"b" + nl + b"c" + nl, "wb": b"x" + nl + nl + b"y" + nl, "wc": b"",
                    "wd": b"p\rq" + nl + b"r" + nl, "we": b"z" + nl + nl}
            bad = ["%s got %r wanted %r" % (k, disk(k + tag), v) for k, v in want.items() if disk(k + tag) != v]
            name = {"U": "no mode set", "0": "mode 0 (LF)", "1": "mode 1 (CRLF)", "2": "mode 2 (BOTH)", "3": "mode 3 (NOCR)"}[tag]
            row("WRITE, %s: field marks become %s, one more at the end of the record, an empty record is an empty file, a CR in "
                "the data stays" % (name, "CR LF" if nl == b"\r\n" else "LF"), not bad, "; ".join(bad))

        # --- leg 4 ---------------------------------------------------------------------------------------------------------
        say("\n--- leg 4: READSEQ and WRITESEQ ---------------------------------------------------------------------------")
        sq = [i for i, c in zip(ids, cases) if len(c) < 200]
        prog("zzcl_rs", p_readseq(sq))
        prog("zzcl_ws", P_WRITESEQ)
        ok, o = compile_ok(["zzcl_rs", "zzcl_ws"])
        if not ok:
            bail("zzcl_rs / zzcl_ws do not compile:\n" + o[-600:])
        out = sess(box, "RUN bp zzcl_rs")
        got_lines = {}
        counts = {}
        for m in re.finditer(r"(?m)^S(\w) (c\d+) (\d+)(?: (.*))?$", out):
            got_lines.setdefault((m.group(1), m.group(2)), {})[int(m.group(3))] = (m.group(4) or "").rstrip("\r")
        for m in re.finditer(r"(?m)^SN(\w) (c\d+) (\d+)\s*$", out):
            counts[(m.group(1), m.group(2))] = int(m.group(3))
        row("the instrument: %d of %d READSEQ passes finished" % (len(counts), 5 * len(sq)), len(counts) == 5 * len(sq), "got %d" % len(counts))
        for label, mode in (("U", 2), ("0", 0), ("1", 1), ("2", 2), ("3", 3)):
            bad = []
            for i, data in zip(ids, cases):
                if i not in sq:
                    continue
                want = ref_seq(mode, data)
                have = [got_lines.get((label, i), {}).get(k + 1) for k in range(counts.get((label, i), 0))]
                if have != [esc(w) for w in want]:
                    bad.append("%s %r got %r wanted %r" % (i, data, have, [esc(w) for w in want]))
            name = {"U": "no mode set (the old READSEQ: same as mode 2)", "0": "mode 0 (LF)", "1": "mode 1 (CRLF)", "2": "mode 2 (BOTH)",
                    "3": "mode 3 (NOCR)"}[label]
            row("READSEQ, %s: the lines of all %d files as the reference" % (name, len(sq)), not bad,
                "; ".join(bad[:3]) + (" ... %d wrong" % len(bad) if len(bad) > 3 else ""))
        out = sess(box, "RUN bp zzcl_ws")
        row("the WRITESEQ program ran to its end", "WRITESEQ.DONE" in out, out[-300:])
        for tag, nl in (("U", b"\n"), ("0", b"\n"), ("1", b"\r\n"), ("2", b"\n"), ("3", b"\n")):
            want = b"one" + nl + nl + b"three\rx" + nl
            row("WRITESEQ, %s: %s ends each line" % ({"U": "no mode set", "0": "mode 0", "1": "mode 1 (CRLF)", "2": "mode 2", "3": "mode 3"}[tag],
                                                      "CR LF" if nl == b"\r\n" else "LF"), disk("sw" + tag) == want,
                "got %r wanted %r" % (disk("sw" + tag), want))

        # --- leg 5 ---------------------------------------------------------------------------------------------------------
        say("\n--- leg 5: the letters in field 6 of the VOC entry ---------------------------------------------------------")
        prog("zzcl_vm", P_VOCMODE)
        prog("zzcl_vh", P_VOCHASH)
        for letter, want_mode, nl in (("L", 0, b"\n"), ("C", 1, b"\r\n"), ("B", 2, b"\n"), ("X", 3, b"\n"), ("c", 1, b"\r\n"), ("", 0, b"\n")):
            prog("zzcl_vs", P_VOCSET % (letter, letter))
            ok, o = compile_ok(["zzcl_vs", "zzcl_vm"])
            if not ok:
                bail("the VOC programs do not compile:\n" + o[-600:])
            out = sess(box, "RUN bp zzcl_vs", "RUN bp zzcl_vm")
            seqmode = {"": 2}.get(letter, want_mode)
            what = "no letter" if letter == "" else "letter %s" % letter
            row("%s: OPEN starts in mode %d and OPENSEQ in mode %d" % (what, want_mode, seqmode),
                got(out, "V1") == str(want_mode) and got(out, "V2") == str(seqmode), "got %r %r" % (got(out, "V1"), got(out, "V2")))
            row("%s: WRITESEQ ends the line with %s, WRITE the same" % (what, "CR LF" if nl == b"\r\n" else "LF"),
                disk("sqvoc") == b"k" + nl and disk("vocdir") == b"u" + nl + b"v" + nl,
                "got %r %r" % (disk("sqvoc"), disk("vocdir")))
        # a hashed file with a letter in its entry ignores it
        prog("zzcl_vs", ("   read v from @voc, 'zzclh' else stop 'no voc entry'\n   v<6> = 'C'\n   write v to @voc, 'zzclh'\n   crt 'HV set'\nend\n"))
        ok, o = compile_ok(["zzcl_vs", "zzcl_vh"])
        out = sess(box, "RUN bp zzcl_vs", "RUN bp zzcl_vh")
        row("a hashed file with the letter C in its entry: FCONTROL says 0 with STATUS 3004 (the letter is ignored)", got(out, "VH") == "0/3004",
            "got %r" % got(out, "VH"))

        # --- leg 6 ---------------------------------------------------------------------------------------------------------
        say("\n--- leg 6: MARK.MAPPING OFF (image mode) ------------------------------------------------------------------")
        prog("zzcl_im", P_IMAGE)
        ok, o = compile_ok(["zzcl_im"])
        if not ok:
            bail("zzcl_im does not compile:\n" + o[-600:])
        raw = b"a" + FM + b"b\r\nc"
        with open(os.path.join(d, "imr"), "wb") as f:
            f.write(b"a\nb\r\nc\n")
        out = sess(box, "RUN bp zzcl_im")
        for m in range(4):
            have = disk("im%d" % m)
            row("image mode, mode %d: the bytes written are the bytes given (field mark and all), no line end added" % m, have == raw,
                "got %r wanted %r" % (have, raw))
        rd = {int(a): (int(b), c) for a, b, c in re.findall(r"(?m)^IM(\d) (\d+) ([0-9a-f]{32})\s*$", out)}
        want_raw = b"a\nb\r\nc\n"
        row("image mode, every mode: a READ gives the file's bytes as they are (%d bytes)" % len(want_raw),
            all(rd.get(m) == (len(want_raw), hashlib.md5(want_raw).hexdigest()) for m in range(4)), "got %r" % rd)
    finally:
        for n in made:
            for dd in ("bp", "bp.out"):
                p = os.path.join(sysd, dd, n)
                if os.path.exists(p):
                    os.remove(p)
        sess(box, "DELETE.FILE zzcl", "DELETE.FILE zzclh")

    say("\nsandbox-crlf: %d passed, %d failed" % (passed, failed))
    sys.exit(0 if failed == 0 else 1)


if __name__ == "__main__":
    main()
