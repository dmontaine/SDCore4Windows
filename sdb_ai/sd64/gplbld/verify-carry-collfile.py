#!/usr/bin/env python3
#
# sandbox-collfile.py - the programs that handle whole records work on a data collection file.  No install, no sudo.
#
#   python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/sandbox-collfile.py <dir> [--build]
#
# <dir> is a sandbox made by sandbox-fromtree.py.  With --build it is built first from THIS tree (it must be empty
# or absent); without it <dir> must already be built, which is how the same script is run against an OLD tree to
# prove it can fail.  Exit 0 every row passed, 1 a row failed, 2 it could not run.
#
# START-HISTORY:
# 11 Oct 26 dm  Written when ED, COPY and COMPARE.FILES were found to stop with "Data cannot be converted to a
#               string" on a collection file.  A record of such a file is a collection when a BASIC program reads it,
#               so a program that treats a record as text must turn it into its JSON text first (ED: the pretty
#               layout, one element to a line, and the lines go back as text; COPY into a file that is not a
#               collection file and COMPARE.FILES: the compact text).  The verbs that were already right
#               (CONFIGURE.FILE, CLEAR.FILE, DELETE, COUNT, LIST.ITEM, DUMP, CT) are rows too, as controls.
#               Triggers: the pre-write trigger was given the text when a program wrote text, and the
#               post-write trigger was given a descriptor read as a string, so that touching the record
#               in it stopped the process (Fault type 11).  op_dio3.c now makes the collection before any
#               trigger sees it and passes the post-write trigger the collection.
# END-HISTORY
#
# THE INSTRUMENT.  The commands sent and what came back are read from the session's output, and the state of the
# files is read again by a BASIC probe (the file's collection flag, the dictionary's flag, the type and JSON text of
# each record), not inferred from a message.  The ED rows send the editor's own commands as the session's next lines;
# an answer the editor waits for is sent too (its "OK to quit?" is Y), because a prompt at the end of the input
# would otherwise wait for ever.

import json
import os
import re
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.path.join(HERE, "sandbox-fromtree.py")
ANSI = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]")
RUN = "%05d" % (os.getpid() % 100000)
A, O, B, D = "zzfa" + RUN, "zzfo" + RUN, "zzfb" + RUN, "zzfd" + RUN
DR = "zzfr" + RUN                                        # a directory file, whose records are files on disk
G, TS, PV = "zzfg" + RUN, "zztg" + RUN, "zzfv" + RUN       # a collection file with a trigger, the trigger, its driver
PW, PP, PX = "zzfw" + RUN, "zzfp" + RUN, "zzfx" + RUN
H, PF = "zzfh" + RUN, "zzfq" + RUN                       # a collection file for elements with no JSON form, its program
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
    say("sandbox-collfile: CANNOT RUN - " + msg)
    sys.exit(2)


def sess(box, *cmds):
    say("    > " + " | ".join(cmds))
    p = subprocess.run([sys.executable, TOOL, box, "sess", os.path.join(box, "user_accounts")] + list(cmds),
                       capture_output=True, text=True, errors="replace", timeout=300)
    out = ANSI.sub("", p.stdout + p.stderr)
    out = out.split(":TERM 200,9999", 1)[-1]
    for line in out.splitlines():
        if line.strip() and not line.startswith(":") and not line.startswith("exit "):
            say("      | " + line.rstrip()[:140])
    return out


# The probe: the file's collection flag, its dictionary's, and each record's kind and JSON text.
PROBE = """$include keys.h
   open '%(a)s' to f else crt 'P not open' ; stop
   open 'DICT %(a)s' to d else crt 'P no dict' ; stop
   crt 'P flags data=':fileinfo(f, FL$COLLECTION):' dict=':fileinfo(d, FL$COLLECTION)
   select f to 9
   readlist ids from 9 else ids = ''
   crt 'P ids=':change(ids, @fm, ',')
   for i = 1 to dcount(ids, @fm)
      id = ids<i>
      read c from f, id then crt 'P rec ':id:' ':jtype(c):' ':jbuild(c) else crt 'P rec ':id:' unreadable'
   next i
   crt 'P end'
end
""" % {"a": A}

WRITER = """   open '%(a)s' to f else crt 'W not open' ; stop
   write jparse('{"city":"Paris","n":3}') on f, 'r1'
   write jparse('{"city":"Rome","n":10}') on f, 'r2'
   write jparse('{"city":"Oslo","n":7,"tags":["a","b"]}') on f, 'r3'
   crt 'W wrote 3'
end
""" % {"a": A}

# Text records in the ordinary file: one that is JSON, one that is not.
TEXTS = """   open '%(o)s' to f else crt 'X not open' ; stop
   write '{"copied":"from text"}' on f, 'good1'
   write '{"second":"text"}' on f, 'good2'
   write 'this is not json' on f, 'bad1'
   crt 'X wrote good1 and bad1'
end
""" % {"o": O}


# A trigger on a collection file.  It says what it was given, stamps every collection it is given before a write, and
# refuses (a non-zero @TRIGGER.RETURN.CODE) one that carries "reject".  The arguments are (mode, id, record, on error).
TRIGGER = """subroutine %(ts)s(mode, id, rec, onerr)
   t = jtype(rec)
   crt 'TRG mode=':mode:' id=':id:' type=':t
   if mode = 1 and t = 'collection' then
      rec{'stamp'} = 'trg'
      if rec{'reject'} # '' then @trigger.return.code = 7
   end
   if mode = 4 and t = 'collection' then crt 'TRG   post-write city=':rec{'city'}:' stamp=':rec{'stamp'}
   return
end
""" % {"ts": TS}

# Elements of a type a file cannot hold (the manual: a file variable) are stored as SQL style nulls.  The write used
# to fail with 1019 (ER$BUILD.ERROR).  A collection that contains itself still cannot be written: it is not a type,
# it is an unbounded depth.
FVPROG = """   open '%(h)s' to f else crt 'F not open' ; stop
   open 'voc' to v else crt 'F no voc' ; stop
   c = jparse('{"a":1}')
   c{'fv'} = v
   x = ''
   write c on f, 'ok1' on error x = 'status=':status()
   crt 'F write fv: [':x:']'
   read r from f, 'ok1' then crt 'F read ok1: ':jbuild(r):' type=':jtype(r) else crt 'F ok1 missing'
   c2 = jparse('{"b":2}')
   c2{'me'} = c2
   y = ''
   write c2 on f, 'cyc' on error y = 'status=':status()
   crt 'F write cycle: [':y:']'
   read r from f, 'cyc' then crt 'F cyc is there' else crt 'F cyc missing'
end
""" % {"h": H}

TRIGGER_DRIVER = """   open '%(g)s' to f else crt 'V not open' ; stop
   write jparse('{"city":"Paris"}') on f, 'r1'
   crt 'V wrote r1 (a collection)'
   write '{"city": "Rome"}' on f, 'r2'
   crt 'V wrote r2 (text)'
   c = jparse('{"city":"Oslo","reject":1}')
   write c on f, 'r3' on error crt 'V r3 refused, status=':status()
   write 'this is not json' on f, 'r4' on error crt 'V r4 refused, status=':status()
   read c from f, 'r1' then crt 'V read r1: ':jbuild(c) else crt 'V r1 missing'
   read c from f, 'r2' then crt 'V read r2: ':jbuild(c) else crt 'V r2 missing'
   delete f, 'r2'
   crt 'V deleted r2'
   select f to 9
   readlist ids from 9 else ids = ''
   crt 'V ids=':change(ids, @fm, ',')
end
""" % {"g": G}


def probe(text):
    """({id: (kind, json)}, [ids], (data_flag, dict_flag)) from the probe's lines."""
    recs = {m.group(1): (m.group(2), m.group(3)) for m in re.finditer(r"(?m)^P rec (\S+) (\S+) (.*?)\s*$", text)}
    ids = re.search(r"(?m)^P ids=(.*?)\s*$", text)
    fl = re.search(r"(?m)^P flags data=(\S+) dict=(\S+)", text)
    return recs, (sorted(i for i in ids.group(1).split(",") if i) if ids else None), ((fl.group(1), fl.group(2)) if fl else None)


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) != 1:
        bail("usage: sandbox-collfile.py <dir> [--build]")
    box = os.path.abspath(args[0])
    sysd = os.path.join(box, "sys")
    say("sandbox-collfile: sandbox %s" % box)
    say("sandbox-collfile: tree    %s" % os.path.dirname(HERE))
    say("sandbox-collfile: files   %s (collection) %s (ordinary) %s (collection) %s (refused)" % (A, O, B, D))
    if "--build" in sys.argv:
        if os.path.exists(box) and os.listdir(box):
            bail("%s is not empty" % box)
        r = subprocess.run([sys.executable, TOOL, box, "all"], capture_output=True, text=True, errors="replace", timeout=900)
        if "[FAIL]" in r.stdout or r.returncode != 0 or "[PASS] THIRD.COMPILE" not in r.stdout:
            bail("the sandbox build did not pass:\n" + r.stdout[-800:])
        say("sandbox-collfile: built, bootstrap passed")
    elif not os.path.isfile(os.path.join(sysd, "bin", "sd")):
        bail("%s holds no built sandbox (use --build, or point it at one)" % box)
    subprocess.run([sys.executable, TOOL, box, "start"], capture_output=True, text=True, errors="replace", timeout=120)

    for nm, body in ((PW, WRITER), (PP, PROBE), (PX, TEXTS)):
        with open(os.path.join(sysd, "bp", nm), "w") as f:
            f.write(body)
    try:
        say("\n--- setup: a collection file with three records, an ordinary file, a second collection file -------")
        out = sess(box, "DELETE.FILE %s" % A, "DELETE.FILE %s" % O, "DELETE.FILE %s" % B,
                   "CREATE.FILE %s COLLECTION" % A, "CREATE.FILE %s" % O, "CREATE.FILE %s COLLECTION" % B,
                   "BASIC bp %s" % PW, "BASIC bp %s" % PP, "BASIC bp %s" % PX, "RUN bp %s" % PW, "RUN bp %s" % PX, "RUN bp %s" % PP)
        clean = len(re.findall(r"(?m)^Compiled 1 program\(s\) with no errors", out))
        recs, ids, fl = probe(out)
        row("setup: the three programs compiled with no errors", clean == 3, "clean compiles: %d of 3" % clean)
        if clean != 3 or "W wrote 3" not in out or ids != ["r1", "r2", "r3"]:
            bail("the fixture is not what the rows assume:\n" + out[-600:])
        row("setup: the data part is a collection file and its dictionary is an ordinary file", fl == ("1", "0"), repr(fl))
        row("setup: its records read back as collections", all(k == "collection" for k, _ in recs.values()) and len(recs) == 3, repr(recs))

        say("\n--- the administration verbs keep the file a collection file (controls: they were right) ----------")
        out = sess(box, "CONFIGURE.FILE %s MINIMUM.MODULUS 11 IMMEDIATE" % A, "RUN bp %s" % PP)
        recs, ids, fl = probe(out)
        row("CONFIGURE.FILE MINIMUM.MODULUS ... IMMEDIATE (a rebuild) leaves the flag and all three records",
            fl == ("1", "0") and ids == ["r1", "r2", "r3"] and all(k == "collection" for k, _ in recs.values()), repr((fl, ids)))
        out = sess(box, "CONFIGURE.FILE %s GROUP.SIZE 2 IMMEDIATE" % A, "RUN bp %s" % PP)
        recs, ids, fl = probe(out)
        row("CONFIGURE.FILE GROUP.SIZE 2 IMMEDIATE leaves the flag and all three records",
            fl == ("1", "0") and ids == ["r1", "r2", "r3"] and all(k == "collection" for k, _ in recs.values()), repr((fl, ids)))
        out = sess(box, "CREATE.FILE %s DIRECTORY COLLECTION" % D)
        row("CREATE.FILE ... DIRECTORY COLLECTION is refused and makes no file",
            "Unexpected token (COLLECTION)" in out and not os.path.exists(os.path.join(sysd, D)) and not os.path.exists(os.path.join(box, "user_accounts", D)),
            out[-200:])

        say("\n--- COPY ------------------------------------------------------------------------------------------")
        out = sess(box, "COPY FROM %s TO %s r1 r2 OVERWRITING" % (A, O), "CT %s r1" % O, "COUNT %s" % O)
        row("COPY from a collection file to an ordinary file copies the records (it stopped with 'Data cannot be converted')",
            "2 record(s) copied." in out and "cannot be converted" not in out, out[-300:])
        row("...and the ordinary record holds the JSON text of the collection", re.search(r'(?m)^1: \{"city":"Paris","n":3\}\s*$', out) is not None, out[-300:])
        out = sess(box, "RUN bp %s" % PX, "COPY FROM %s TO %s good1" % (O, B), "CT %s good1" % B)
        row("COPY from an ordinary file to a collection file: text that is a JSON object becomes a collection",
            "1 record(s) copied." in out and re.search(r'(?m)^  "copied": "from text"\s*$', out) is not None, out[-300:])
        out = sess(box, "COPY FROM %s TO %s bad1" % (O, B), "COUNT %s" % B)
        row("...text that is not JSON is refused (error 1020), and no record is made",
            "Error 1020 writing record 'bad1'" in out and "1 record(s) counted" in out, out[-300:])
        out = sess(box, "COPY FROM %s TO %s r3" % (A, B), "COUNT %s" % B)
        row("CONTROL: COPY from a collection file to another collection file", "1 record(s) copied." in out and "2 record(s) counted" in out, out[-300:])

        say("\n--- COMPARE.FILES ---------------------------------------------------------------------------------")
        out = sess(box, "COMPARE.FILES %s %s" % (A, A))
        row("a collection file compared with itself: 3 the same, none differ (it stopped with 'Value not found')",
            "Records that are the same: 3" in out and "Records in both that differ: 0" in out and "Value not found" not in out, out[-300:])
        out = sess(box, "COMPARE.FILES %s %s DETAIL" % (A, O))
        row("with its ordinary copy: r1 and r2 are the same, r3 only in the collection file, none differ",
            "Records that are the same: 2" in out and "Records in both that differ: 0" in out and re.search(r"Records only in %s: 1\s+r3" % A, out) is not None,
            out[-400:])
        with open(os.path.join(sysd, "bp", PX), "w") as f:
            f.write("   open '%s' to f else stop 'no file'\n   write jparse('{\"city\":\"Berlin\",\"n\":3}') on f, 'r1'\n   crt 'X changed r1'\nend\n" % A)
        out = sess(box, "BASIC bp %s" % PX, "RUN bp %s" % PX, "COMPARE.FILES %s %s DETAIL" % (A, O))
        row("a record changed in the collection file is reported as differing", "Records in both that differ: 1" in out and "Records that are the same: 1" in out, out[-400:])


        say("\n--- a collection file and a directory file (records that are files on disk) -------------------------")
        out = sess(box, "CREATE.FILE %s DIRECTORY" % DR, "COPY FROM %s TO %s r2" % (A, DR))
        ondisk = os.path.join(sysd, DR, "r2")          # the sandbox session's account is the sys directory
        try:
            with open(ondisk, "rb") as fh:
                text = fh.read().decode("latin-1")
        except OSError:
            text = None
        try:
            on_disk_ok = text is not None and json.loads(text.strip()) == {"city": "Rome", "n": 10}
        except ValueError:
            on_disk_ok = False
        row("COPY from a collection file to a directory file writes the record as a JSON file on disk",
            "1 record(s) copied." in out and on_disk_ok, "%r  %s" % (text, out[-200:]))
        try:
            with open(os.path.join(sysd, DR, "fromdisk"), "w") as fh:
                fh.write('{"loaded": ["a", 1, true]}')
        except OSError:
            pass                                       # the next row fails by itself, with the output
        out = sess(box, "COPY FROM %s TO %s fromdisk" % (DR, B), "CT %s fromdisk" % B)
        row("COPY from a directory file to a collection file loads a JSON file from disk as a collection",
            "1 record(s) copied." in out and re.search(r'(?m)^  "loaded": \[\s*$', out) is not None, out[-300:])

        say("\n--- ED, the line editor ---------------------------------------------------------------------------")
        out = sess(box, "ED %s r2" % A, "P9", "Q")
        row("ED opens a collection record (it stopped with 'Data cannot be converted') as the JSON, one element to a line: 4 lines",
            "4 line(s)" in out and "cannot be converted" not in out and re.search(r'(?m)^0002:   "city": "Rome",\s*$', out) is not None, out[-400:])
        out = sess(box, "EDIT %s r2" % A, "P9", "Q")
        row("EDIT is the same editor: it opens the record as 4 lines of JSON as well",
            "4 line(s)" in out and "cannot be converted" not in out, out[-300:])
        out = sess(box, "ED %s r2" % A, "G2", 'R   "city": "Lyon",', "FI", "RUN bp %s" % PP)
        recs, ids, fl = probe(out)
        row("a line changed and filed: the record is a collection again, with the change",
            "'r2' filed in %s" % A in out and recs.get("r2") == ("collection", '{"city":"Lyon","n":10}'), repr(recs.get("r2")))
        out = sess(box, "ED %s r3" % A, "G2", "R   not json at all", "FI", "Q", "Y", "RUN bp %s" % PP)
        recs, ids, fl = probe(out)
        row("lines that are not JSON are refused: 'Write error 1020 ... Data not saved'",
            "Write error 1020" in out and "Data not saved" in out, out[-400:])
        row("...and the record in the file is the one it was", recs.get("r3") == ("collection", '{"city":"Oslo","n":7,"tags":["a","b"]}'), repr(recs.get("r3")))
        out = sess(box, "ED %s newrec" % A, "I {", 'I   "k": 1', "I }", "FI", "RUN bp %s" % PP)
        recs, ids, fl = probe(out)
        row("a new record typed in the editor and filed is a collection", recs.get("newrec") == ("collection", '{"k":1}'), repr(recs.get("newrec")))
        out = sess(box, "ED %s lt" % O, "I first line", "LOAD %s r1" % A, "2", "3", "P9", "Q", "Y")
        row("LOAD of part of a collection record: the lines of its JSON",
            "2 lines loaded from %s r1" % A in out and re.search(r'(?m)^0002:   "city": "Berlin",\s*$', out) is not None, out[-400:])
        out = sess(box, "ED %s ut" % O, "I {", 'I   "u": 2', "I }", "UNLOAD %s unl1" % A, "1", "3", "Q", "Y", "RUN bp %s" % PP)
        recs, ids, fl = probe(out)
        row("UNLOAD of JSON lines into a collection file makes a collection", recs.get("unl1") == ("collection", '{"u":2}'), repr(recs.get("unl1")))
        out = sess(box, "ED %s ut2" % O, "I plain text", "UNLOAD %s unl2" % A, "1", "1", "Q", "Y", "RUN bp %s" % PP)
        recs, ids, fl = probe(out)
        row("UNLOAD of lines that are not JSON is refused with the write error, and makes no record",
            "Write error 1020" in out and "unl2" not in (ids or []), out[-400:])

        say("\n--- the verbs that read a record for display (controls: they were right) ------------------------")
        out = sess(box, "LIST.ITEM %s r1" % A, "DUMP %s r1" % A, "DELETE %s unl1" % A, "COUNT %s" % A)
        row("CONTROL: LIST.ITEM shows the JSON text of a collection record",
            re.search(r'(?m)^001: \{"city":"Berlin","n":3\}\s*$', out) is not None, out[-400:])
        row("CONTROL: DUMP shows it laid out", re.search(r'(?m)^  "city": "Berlin",\s*$', out) is not None, out[-400:])
        row("CONTROL: DELETE removes a record of a collection file and COUNT sees it go",
            "1 record(s) deleted" in out and "4 record(s) counted" in out, out[-300:])
        out = sess(box, "CLEAR.FILE %s" % A, "RUN bp %s" % PP)
        recs, ids, fl = probe(out)
        row("CONTROL: CLEAR.FILE leaves an empty collection file (the flag stays)", fl == ("1", "0") and ids == [], repr((fl, ids)))

        say("\n--- triggers on a collection file -----------------------------------------------------------------")
        with open(os.path.join(sysd, "bp", TS), "w") as f:
            f.write(TRIGGER)
        with open(os.path.join(sysd, "bp", PV), "w") as f:
            f.write(TRIGGER_DRIVER)
        out = sess(box, "DELETE.FILE %s" % G, "CREATE.FILE %s COLLECTION" % G, "BASIC bp %s" % TS, "CATALOG bp %s LOCAL" % TS,
                   "BASIC bp %s" % PV, "SET.TRIGGER %s %s ALL" % (G, TS))
        clean = len(re.findall(r"(?m)^Compiled 1 program\(s\) with no errors", out))
        row("setup: the trigger and its driver compiled, the trigger is catalogued and set on the file",
            clean == 2 and ("%s added to local catalogue" % TS) in out and "3003" not in out, out[-400:])
        if clean != 2:
            bail("the trigger fixture did not compile:\n" + out[-500:])
        out = sess(box, "RUN bp %s" % PV)
        trg = lambda mode, ident, kind: ("TRG mode=%d id=%s type=%s" % (mode, ident, kind)) in out
        row("a pre-write trigger is given the collection the program wrote", trg(1, "r1", "collection"), out[-700:])
        row("...and a collection when the program wrote TEXT (it was given the text)", trg(1, "r2", "collection"), out[-700:])
        row("the post-write trigger is given the collection, and the program runs on (it stopped with Fault type 11)",
            trg(4, "r1", "collection") and "Fault type" not in out and "V deleted r2" in out, out[-700:])
        row("...with the change the pre-write trigger made: it saw the stamp", "TRG   post-write city=Paris stamp=trg" in out, out[-700:])
        row("a trigger that refuses stops the write (status 3022), the post-write trigger does not run for it",
            "V r3 refused, status=3022" in out and not trg(4, "r3", "collection"), out[-700:])
        row("text that is not JSON is refused (1020) BEFORE the trigger, which never sees it",
            "V r4 refused, status=1020" in out and "id=r4" not in out, out[-700:])
        row("the read trigger is given a collection", trg(16, "r1", "collection"), out[-700:])
        row("the change a trigger made is stored: the record reads back with its stamp",
            'V read r1: {"city":"Paris","stamp":"trg"}' in out, out[-700:])
        row("text written with its own layout is held as the compact JSON of the collection",
            'V read r2: {"city":"Rome","stamp":"trg"}' in out, out[-700:])
        row("the delete triggers run (modes 2 and 8)", "TRG mode=2 id=r2" in out and "TRG mode=8 id=r2" in out, out[-700:])
        row("the refused records are not in the file; the deleted one is gone", "V ids=r1" in out and "V ids=r1," not in out, out[-700:])

        say("\n--- an element a file cannot hold (a file variable) ------------------------------------------------")
        with open(os.path.join(sysd, "bp", PF), "w") as f:
            f.write(FVPROG)
        out = sess(box, "DELETE.FILE %s" % H, "CREATE.FILE %s COLLECTION" % H, "BASIC bp %s" % PF, "RUN bp %s" % PF)
        row("setup: the program compiled and ran to its end", "Compiled 1 program(s) with no errors" in out and "F cyc " in out, out[-500:])
        row("a collection holding a file variable is written (the write failed with 1019 before)",
            "F write fv: []" in out, out[-500:])
        row("...and the element is stored as a JSON null, the others intact",
            'F read ok1: {"a":1,"fv":null} type=collection' in out, out[-500:])
        row("CONTROL: a collection that contains itself is still refused (1019) and makes no record",
            "F write cycle: [status=1019]" in out and "F cyc missing" in out, out[-500:])
    finally:
        say("\n--- cleanup ---------------------------------------------------------------------------------------")
        sess(box, "DELETE.FILE %s" % A, "DELETE.FILE %s" % O, "DELETE.FILE %s" % B, "DELETE.FILE %s" % G,
             "DELETE.FILE %s" % H, "DELETE.FILE %s FORCE" % DR, "DELETE.CATALOG %s LOCAL" % TS)
        # a directory file is a directory of files, which DELETE.FILE may leave if it holds a file it did not make
        for dpath in (os.path.join(box, "user_accounts", DR), os.path.join(box, "user_accounts", DR + ".dic"),
                      os.path.join(sysd, DR), os.path.join(sysd, DR + ".dic")):
            if os.path.isdir(dpath):
                shutil.rmtree(dpath)
        for nm in (PW, PP, PX, TS, PV, PF):
            for d in ("bp", "bp.out"):
                pth = os.path.join(sysd, d, nm)
                if os.path.exists(pth):
                    os.remove(pth)
        left = [n for n in (A, O, B, D, G, DR, H) if any(os.path.exists(os.path.join(box, d, n)) for d in ("sys", "user_accounts"))]
        row("cleanup: no fixture file is left", not left, " ".join(left))

    say("\nsandbox-collfile: %d passed, %d failed" % (passed, failed))
    if passed + failed == 0:
        bail("no row ran - a broken test, not a pass")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
