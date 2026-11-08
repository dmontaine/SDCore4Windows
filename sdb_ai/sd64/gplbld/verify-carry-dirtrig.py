#!/usr/bin/env python3
#
# sandbox-dirtrig.py - triggers on directory files (QM4 Fixes item 177, openQM 4): SET.TRIGGER of a directory file, the trigger
#                      function called by READ, WRITE, DELETE and CLEARFILE, the %header% file that holds it, and what must NOT
#                      call it.
#
#   python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/sandbox-dirtrig.py <dir> [--build]
#
# <dir> is a sandbox made by sandbox-fromtree.py (needs no install, no sudo).  With --build it is built first from THIS tree (it
# must be empty or absent).  Exit 0 every row passed, 1 a row failed, 2 it could not run.
#
# START-HISTORY:
# 16 Oct 26 dm  New.
# END-HISTORY
#
# THE INSTRUMENT.  The trigger function (zzdttrg) prints a line for every call it gets - TRG mode|id|data - and the programs print
# markers between the operations, so the output is the sequence of calls in the order they happened.  The disk is read directly for
# what a trigger changed or refused, and for the %header% file.  The first thing the suite checks is that the header is where the
# sandbox says the directory file is (a test that looked at nothing must not pass).
#
# The trigger refuses a pre-write of the id "bad" and a pre-delete of "nodel" (@TRIGGER.RETURN.CODE), changes the data of a pre-write
# of "upper" to capitals, and adds "+read" to what a READ gives back.
#
#   1  SET.TRIGGER on a directory file: the header on disk, the report, FILEINFO(FL$TRIGGER) and (FL$TRG.MODES), LIST.TRIGGERS
#   2  every mode in turn, in order: pre-write 1, post-write 4, read 16, pre-delete 2, post-delete 8, pre-clear 32, post-clear 64
#   3  what a trigger can do: refuse a write and a delete (STATUS 3022, the record not written / still there), change the data
#   4  a mode subset, and the default (pre-write and pre-delete)
#   5  %header% is not a record: SELECT, COUNT and CLEAR.FILE leave it out; the id %header% does not reach it
#   6  what does not call the trigger: WRITESEQ
#   7  a header naming a function that is not catalogued, one with a name no function can have, no header, and removing a trigger

import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.path.join(HERE, "sandbox-fromtree.py")
ANSI = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]")
passed = failed = 0

TRG = """subroutine zzdttrg(mode, id, data, on.error, fvar)
   crt 'TRG ':mode:'|':id:'|':change(data, @fm, '~')
   if mode = 1 and id = 'bad' then @trigger.return.code = 1
   if mode = 2 and id = 'nodel' then @trigger.return.code = 2
   if mode = 1 and id = 'upper' then data = upcase(data)
   if mode = 16 then data = data : '+read'
end
"""

OPS = """$include keys.h
   open 'zzdt' to f else stop 'no zzdt'
   crt 'FI[':fileinfo(f, FL$TRIGGER):'/':fileinfo(f, FL$TRG.MODES):']'
   crt 'STEP write'
   write 'a':@fm:'b' to f, 'r1' on error crt 'WERR[':status():']'
   crt 'STEP read'
   read r from f, 'r1' then crt 'READ[':change(r, @fm, '~'):']' else crt 'READ miss'
   crt 'STEP upper'
   write 'abc' to f, 'upper' on error crt 'UERR[':status():']'
   crt 'STEP bad'
   write 'x' to f, 'bad' on error crt 'BADST[':status():']'
   crt 'STEP delete'
   delete f, 'r1' on error crt 'DERR[':status():']'
   crt 'STEP nodel'
   write 'keep' to f, 'nodel' on error crt 'KERR[':status():']'
   delete f, 'nodel' on error crt 'NODELST[':status():']'
   crt 'STEP end'
end
"""

CLEAR = """   open 'zzdt' to f else stop 'no zzdt'
   crt 'STEP clear'
   clearfile f on error crt 'CERR[':status():']'
   crt 'STEP end'
end
"""

WRITES = """$include keys.h
   open 'zzdt' to f else stop 'no zzdt'
   crt 'FI[':fileinfo(f, FL$TRIGGER):'/':fileinfo(f, FL$TRG.MODES):']'
   crt 'STEP w'
   write 'one' to f, 'w1' on error crt 'WERR[':status():']'
   crt 'STEP r'
   read r from f, 'w1' then crt 'READ[':r:']' else crt 'READ miss'
   crt 'STEP d'
   delete f, 'w1' on error crt 'DERR[':status():']'
   crt 'STEP end'
end
"""

HIDE = """$include keys.h
   open 'zzdt' to f else stop 'no zzdt'
   write 'p' to f, 'rec1'
   write 'q' to f, 'rec2'
   write 'mine' to f, '%header%'
   read h from f, '%header%' else h = '*NONE*'
   crt 'USERREAD[':h:']'
   select f to 1
   ids = ''
   loop
      readnext id from 1 else exit
      ids<-1> = id
   repeat
   crt 'SEL[':dcount(ids, @fm):']'
end
"""

SEQ = """$include keys.h
   open 'zzdt' to f else stop 'no zzdt'
   crt 'STEP seq'
   openseq 'zzdt', 'sq1' to s then null else
      create s else stop 'no create'
   end
   weofseq s
   writeseq 'line' to s else stop 'ws'
   close s
   crt 'STEP end'
end
"""

PLAIN = """   open 'zzdt' to f else stop 'no zzdt'
   crt 'FI[':fileinfo(f, 1002):'/':fileinfo(f, 1007):']'
   write 'v' to f, 'plain1' on error crt 'WERR[':status():']'
   crt 'WROTE'
end
"""


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
    say("sandbox-dirtrig: CANNOT RUN - " + msg)
    sys.exit(2)


def sess(box, *cmds):
    p = subprocess.run([sys.executable, TOOL, box, "sess", os.path.join(box, "user_accounts")] + list(cmds),
                       capture_output=True, text=True, errors="replace", timeout=900)
    return ANSI.sub("", p.stdout + p.stderr).split(":TERM 200,9999", 1)[-1]


def got(out, tag):
    m = re.findall(re.escape(tag) + r"\[([^\]]*)\]", out)
    return m[-1] if m else None


def calls(out):
    """The marked sequence of one run: STEP names and TRG lines, in order."""
    return [m.group(0).strip() for m in re.finditer(r"(?m)^(?:STEP \w+|TRG \d+\|[^|\n]*\|.*)$", out)]


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) != 1:
        bail("usage: sandbox-dirtrig.py <dir> [--build]")
    box = os.path.abspath(args[0])
    sysd = os.path.join(box, "sys")
    bp = os.path.join(sysd, "bp")
    d = os.path.join(sysd, "zzdt")      # the session runs in the SDSYS account (the sandbox user plays sdsys)
    hdr = os.path.join(d, "%header%")
    say("sandbox-dirtrig: sandbox %s" % box)
    if "--build" in sys.argv:
        if os.path.exists(box) and os.listdir(box):
            bail("%s is not empty" % box)
        r = subprocess.run([sys.executable, TOOL, box, "all"], capture_output=True, text=True, errors="replace", timeout=900)
        if "[FAIL]" in r.stdout or r.returncode != 0 or "[PASS] THIRD.COMPILE" not in r.stdout:
            bail("the sandbox build did not pass:\n" + r.stdout[-800:])
        say("sandbox-dirtrig: built, bootstrap passed")
    elif not os.path.isfile(os.path.join(sysd, "bin", "sd")):
        bail("%s holds no built sandbox (use --build, or point it at one)" % box)
    subprocess.run([sys.executable, TOOL, box, "start"], capture_output=True, text=True, errors="replace", timeout=120)

    made = []

    def prog(name, text):
        with open(os.path.join(bp, name), "w") as f:
            f.write(text)
        made.append(name)

    def readfile(p):
        return open(p, "rb").read() if os.path.exists(p) else None

    try:
        prog("zzdttrg", TRG)
        prog("zzdt_ops", OPS)
        prog("zzdt_clr", CLEAR)
        prog("zzdt_wr", WRITES)
        prog("zzdt_hide", HIDE)
        prog("zzdt_seq", SEQ)
        prog("zzdt_plain", PLAIN)
        sess(box, "CATALOG bp zzdttrg LOCAL", "DELETE.CATALOG zzdttrg LOCAL")
        out = sess(box, "DELETE.FILE zzdt", "CREATE.FILE zzdt DIRECTORY", "BASIC bp zzdttrg", "CATALOG bp zzdttrg LOCAL",
                   "BASIC bp zzdt_ops", "BASIC bp zzdt_clr", "BASIC bp zzdt_wr", "BASIC bp zzdt_hide", "BASIC bp zzdt_seq",
                   "BASIC bp zzdt_plain")
        n = len(re.findall(r"(?m)^Compiled 1 program\(s\) with no errors", out))
        if n != 7:
            bail("%d of 7 programs compiled:\n%s" % (n, out[-1200:]))
        if not os.path.isdir(d):
            bail("CREATE.FILE zzdt DIRECTORY did not make %s (the instrument would read nothing)" % d)

        # ---- leg 1 ---------------------------------------------------------------------------------------------------
        say("\n--- leg 1: SET.TRIGGER on a directory file ---------------------------------------------------------------")
        out = sess(box, "SET.TRIGGER zzdt zzdttrg ALL")
        row("SET.TRIGGER reports the function and all seven modes", "zzdttrg" in out and "PRE.WRITE" in out and "POST.CLEAR" in out
            and "READ" in out, out[-300:])
        row("%header% is on disk and says so: trigger=zzdttrg, modes=127 (ALL)", readfile(hdr) == b"trigger=zzdttrg\nmodes=127\n",
            "got %r" % readfile(hdr))
        out = sess(box, "SET.TRIGGER zzdt", "LIST.TRIGGERS NO.PAGE")
        row("SET.TRIGGER with no function reports it", re.search(r"zzdttrg", out) is not None, out[-300:])
        row("LIST.TRIGGERS lists the directory file with its function and modes",
            re.search(r"(?m)^zzdt\s+zzdttrg\s+.*POST.CLEAR", out) is not None, out[-400:])

        # ---- leg 2 and 3 ---------------------------------------------------------------------------------------------
        say("\n--- legs 2 and 3: every mode in order; refusing and changing --------------------------------------------")
        out = sess(box, "RUN bp zzdt_ops")
        want = ["STEP write", "TRG 1|r1|a~b", "TRG 4|r1|a~b",
                "STEP read", "TRG 16|r1|a~b",
                "STEP upper", "TRG 1|upper|abc", "TRG 4|upper|ABC",
                "STEP bad", "TRG 1|bad|x",
                "STEP delete", "TRG 2|r1|", "TRG 8|r1|",
                "STEP nodel", "TRG 1|nodel|keep", "TRG 4|nodel|keep", "TRG 2|nodel|",
                "STEP end"]
        have = calls(out)
        row("FILEINFO(FL$TRIGGER) and (FL$TRG.MODES) of the open directory file: zzdttrg and 127", got(out, "FI") == "zzdttrg/127",
            "got %r" % got(out, "FI"))
        row("THE ROW: the calls, in order - pre-write 1 and post-write 4, read 16, pre-delete 2 and post-delete 8 - with the id and "
            "the data each time", have == want, "got %r" % have)
        row("a READ gives back what the read trigger did to the data (the trigger added +read)", got(out, "READ") == "a~b+read",
            "got %r" % got(out, "READ"))
        row("a pre-write trigger that returns a code refuses the write: STATUS 3022 (ER$TRIGGER), and the record is not on disk",
            got(out, "BADST") == "3022" and not os.path.exists(os.path.join(d, "bad")), "got %r, bad on disk: %r"
            % (got(out, "BADST"), os.path.exists(os.path.join(d, "bad"))))
        row("a pre-write trigger that changes the data: the capitals are what is on disk", readfile(os.path.join(d, "upper")) == b"ABC\n",
            "got %r" % readfile(os.path.join(d, "upper")))
        row("a pre-delete trigger that returns a code refuses the delete: STATUS 3022 and the record is still there",
            got(out, "NODELST") == "3022" and readfile(os.path.join(d, "nodel")) == b"keep\n",
            "got %r, on disk %r" % (got(out, "NODELST"), readfile(os.path.join(d, "nodel"))))
        row("an ordinary pre-delete and post-delete: r1 is gone", not os.path.exists(os.path.join(d, "r1")))
        on_disk = sorted(os.listdir(d))
        row("the directory holds %header%, upper and nodel and nothing else", on_disk == ["%header%", "nodel", "upper"], "got %r" % on_disk)
        out = sess(box, "RUN bp zzdt_clr")
        have = calls(out)
        row("CLEARFILE calls the pre-clear (32) and post-clear (64) triggers, with a null id and null data", have == [
            "STEP clear", "TRG 32||", "TRG 64||", "STEP end"], "got %r" % have)
        row("CLEARFILE removed every record and left %header% (and so the trigger)",
            sorted(os.listdir(d)) == ["%header%"] and readfile(hdr) == b"trigger=zzdttrg\nmodes=127\n", "got %r" % sorted(os.listdir(d)))

        # ---- leg 4 ---------------------------------------------------------------------------------------------------
        say("\n--- leg 4: a mode subset, and the default -------------------------------------------------------------------")
        sess(box, "SET.TRIGGER zzdt zzdttrg POST.WRITE")
        out = sess(box, "RUN bp zzdt_wr")
        have = calls(out)
        row("POST.WRITE only: the write calls the trigger once (4), the read and the delete not at all",
            have == ["STEP w", "TRG 4|w1|one", "STEP r", "STEP d", "STEP end"], "got %r" % have)
        row("the header says modes=4", readfile(hdr) == b"trigger=zzdttrg\nmodes=4\n", "got %r" % readfile(hdr))
        sess(box, "SET.TRIGGER zzdt zzdttrg")
        out = sess(box, "RUN bp zzdt_wr")
        have = calls(out)
        row("no modes given: pre-write (1) and pre-delete (2), the defaults of a hashed file too",
            have == ["STEP w", "TRG 1|w1|one", "STEP r", "STEP d", "TRG 2|w1|", "STEP end"] and got(out, "FI") == "zzdttrg/3",
            "got %r %r" % (have, got(out, "FI")))

        # ---- leg 5 ---------------------------------------------------------------------------------------------------
        say("\n--- leg 5: %header% is not a record ------------------------------------------------------------------------")
        sess(box, "SET.TRIGGER zzdt zzdttrg PRE.CLEAR")
        head_before = readfile(hdr)
        out = sess(box, "RUN bp zzdt_hide", "COUNT zzdt", "ANALYZE.FILE zzdt STATISTICS")
        row("ANALYZE.FILE ... STATISTICS says 3 total records, not 4", os.path.exists(hdr) and re.search(r"Total records\s*:\s*3\b", out) is not None,
            out[-300:])
        row("SELECT gives the three records that were written (rec1, rec2 and one the program named %header%) and not the header file "
            "(that would make four); the instrument: the header IS in the directory", got(out, "SEL") == "3" and os.path.exists(hdr),
            "got %r, header there: %r" % (got(out, "SEL"), os.path.exists(hdr)))
        row("the id %header% is a record like any other: READ gives what was written, not the trigger file",
            got(out, "USERREAD") == "mine", "got %r" % got(out, "USERREAD"))
        row("and the header file on disk is as it was", readfile(hdr) == head_before, "got %r" % readfile(hdr))
        row("COUNT counts the three records and not the header", os.path.exists(hdr) and (re.search(r"\b3 record\(s\) counted", out) is not None
            or re.search(r"(?m)^3\b.*record", out) is not None), out[-300:])
        mine = [n for n in os.listdir(d) if readfile(os.path.join(d, n)) == b"mine\n"]
        row("the user's record named %header% is on disk under another name (the % is mapped)", len(mine) == 1 and mine[0] != "%header%",
            "got %r" % mine)
        out = sess(box, "CLEAR.FILE zzdt")
        row("CLEAR.FILE removed the records and kept the header", sorted(os.listdir(d)) == ["%header%"], "got %r" % sorted(os.listdir(d)))

        # ---- leg 6 ---------------------------------------------------------------------------------------------------
        say("\n--- leg 6: WRITESEQ does not call the trigger ------------------------------------------------------------------")
        sess(box, "SET.TRIGGER zzdt zzdttrg ALL")
        out = sess(box, "RUN bp zzdt_seq")
        row("WRITESEQ to a record of the file: no TRG line (the manual's limit), and the line is on disk",
            calls(out) == ["STEP seq", "STEP end"] and readfile(os.path.join(d, "sq1")) == b"line\n",
            "got %r, on disk %r" % (calls(out), readfile(os.path.join(d, "sq1"))))

        # ---- leg 7 ---------------------------------------------------------------------------------------------------
        say("\n--- leg 7: bad headers, and taking the trigger away ----------------------------------------------------------")
        with open(hdr, "wb") as f:
            f.write(b"trigger=zznosuch\nmodes=1\n")
        out = sess(box, "RUN bp zzdt_wr")
        row("a header that names a function that is not catalogued: the first call that needs it says so (message 1409)",
            "not loaded for" in out and "zznosuch" in out, out[-300:])
        for text, label in ((b"trigger=Bad Name!\nmodes=3\n", "a name no function can have"), (b"garbage\n", "text that is not a header"),
                            (b"", "an empty header")):
            with open(hdr, "wb") as f:
                f.write(text)
            out = sess(box, "RUN bp zzdt_plain")
            row("%s: the file opens with no trigger and a write goes through" % label,
                got(out, "FI") == "/0" and "WROTE" in out and "TRG " not in out, out[-300:])
        os.remove(hdr)
        out = sess(box, "RUN bp zzdt_plain")
        row("no header at all: no trigger", got(out, "FI") == "/0" and "TRG " not in out, out[-300:])
        sess(box, "SET.TRIGGER zzdt zzdttrg ALL")
        out = sess(box, "SET.TRIGGER zzdt ''", "RUN bp zzdt_plain")
        row("SET.TRIGGER zzdt '' takes the trigger away: the header file is gone and the next OPEN has none",
            not os.path.exists(hdr) and got(out, "FI") == "/0" and "TRG " not in out, "header %r, out %r" % (os.path.exists(hdr), out[-300:]))
    finally:
        for n in made:
            for dd in ("bp", "bp.out"):
                p = os.path.join(sysd, dd, n)
                if os.path.exists(p):
                    os.remove(p)
        sess(box, "DELETE.CATALOG zzdttrg LOCAL", "DELETE.FILE zzdt")

    say("\nsandbox-dirtrig: %d passed, %d failed" % (passed, failed))
    sys.exit(0 if failed == 0 else 1)


if __name__ == "__main__":
    main()
