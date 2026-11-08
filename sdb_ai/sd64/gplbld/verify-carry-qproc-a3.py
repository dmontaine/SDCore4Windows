#!/usr/bin/env python3
#
# sandbox-qproc-a3.py - 1.2-0 bundle A-3 (openQM features after 2.6.6, the query processor): does each
#                       keyword and option do what the release note says, on a real file?  No install, no sudo.
#
#   python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/sandbox-qproc-a3.py <dir> [--build]
#
# <dir> is a sandbox made by sandbox-fromtree.py.  With --build it is built first from THIS tree (it must be
# empty or absent).  Exit 0 every row passed, 1 a row failed, 2 it could not run.
#
# START-HISTORY:
# 27 Oct 26 dm  S.87 batch 4: leg 12 - the query keywords, the noise word THAN, ONLY before the file name, => =< >< and dictionary fields 9998 / 9999 that were
#               removed that day are refused or read as ordinary, each beside its surviving spelling.
# 10 Oct 26 dm  Written for 1.2-0 bundle A-3.
# END-HISTORY
#
# THE INSTRUMENT IS WHAT LIST/SELECT PRINTED for a file of five records whose values are known.  Each leg
# has a CONTROL that shows the old behaviour (or the neighbouring keyword's), so a row cannot pass because
# the command printed nothing.
#
#   1  CSV 3 quotes every item (ref 26)
#   2  ABSENT.IGNORE (25)
#   3  SORTED.SAMPLE (438), with SAMPLE as its control
#   4  COL.HDR.SPACE (467)
#   5  FROM NONE (378)
#   6  BREAK.ON 'N' resets the page number (16), and 'L' with 'U' (40)
#   7  NO.PAGE on SELECT (379)
#   8  SEARCH FOR (190), SEARCH ALL (221)
#   9  REPORTING (416)
#  10  SELECT with a bare field name (39)
#  11  REFORMAT with @RECORD (546)
#  12  the removed second spellings of S.87 batch 4 (the VOC records, THAN, ONLY, => =< ><, fields 9998 and 9999)

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
    say("sandbox-qproc-a3: CANNOT RUN - " + msg)
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


def write(path, text):
    with open(path, "wb") as f:
        f.write(text.encode("ascii"))


def ids_in(out):
    """Record ids (r1..r5) in the order printed."""
    return re.findall(r"(?m)^(r[1-9])\b", out)


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) != 1:
        bail("usage: sandbox-qproc-a3.py <dir> [--build]")
    box = os.path.abspath(args[0])
    sysd = os.path.join(box, "sys")
    bp = os.path.join(sysd, "bp")
    say("sandbox-qproc-a3: sandbox %s" % box)
    if "--build" in sys.argv:
        if os.path.exists(box) and os.listdir(box):
            bail("%s is not empty" % box)
        r = subprocess.run([sys.executable, TOOL, box, "all"], capture_output=True, text=True, errors="replace", timeout=900)
        if "[FAIL]" in r.stdout or r.returncode != 0 or "[PASS] THIRD.COMPILE" not in r.stdout:
            bail("the sandbox build did not pass:\n" + r.stdout[-800:])
        say("sandbox-qproc-a3: built, bootstrap passed")
    elif not os.path.isfile(os.path.join(sysd, "bin", "sd")):
        bail("%s holds no built sandbox (use --build, or point it at one)" % box)
    subprocess.run([sys.executable, TOOL, box, "start"], capture_output=True, text=True, errors="replace", timeout=120)

    made = []

    def prog(name, text):
        write(os.path.join(bp, name), text)
        made.append(name)

    try:
        say("\n--- setup ---------------------------------------------------------------------")
        # r1..r5: F1 = name, F2 = number (50 40 30 20 10), F3 = group (a a b b b)
        data = [("r1", "alpha", "50", "a"), ("r2", "bravo", "40", "a"), ("r3", "charlie", "30", "b"),
                ("r4", "delta", "20", "b"), ("r5", "echo", "10", "b")]
        for rid, n, num, g in data:
            prog("zzq3" + rid, "%s\n%s\n%s\n" % (n, num, g))
        for i, nm in ((1, "name"), (2, "num"), (3, "grp")):
            prog("zzq3d%d" % i, "D\n%d\n\n%s\n10L\nS\n" % (i, nm))
        cmds = ["DELETE.FILE DICT zzq3", "DELETE.FILE zzq3", "CREATE.FILE zzq3"]
        for rid, *_ in data:
            cmds.append("COPY FROM BP TO zzq3 zzq3%s,%s" % (rid, rid))
        for i, nm in ((1, "name"), (2, "num"), (3, "grp")):
            cmds.append("COPY FROM BP TO DICT zzq3 zzq3d%d,%s" % (i, nm))
        out = sess(box, *cmds, quiet=True)
        copied = len(re.findall(r"(?m)^1 record\(s\) copied\.", out))
        row("setup: all 8 COPY commands each copied one record", copied == 8, "copied lines: %d" % copied)

        say("\n--- leg 1: CSV 3 (ref 26) -------------------------------------------------------")
        out = sess(box, "LIST zzq3 name num CSV 1 ID.SUP", "LIST zzq3 name num CSV 3 ID.SUP")
        parts = out.split("LIST zzq3 name num CSV 3")
        row("CONTROL: CSV 1 leaves a number unquoted", re.search(r'(?m)^alpha,50\s*$', parts[0]) is not None, "no alpha,50")
        row("THE ROW: CSV 3 quotes the name and the number", len(parts) > 1 and re.search(r'(?m)^"alpha","50"\s*$', parts[1]) is not None,
            "no \"alpha\",\"50\" line")

        say("\n--- leg 2: ABSENT.IGNORE (ref 25) ---------------------------------------------")
        out = sess(box, "LIST zzq3 name WITH name = 'zzz' ID.SUP", "LIST zzq3 'r1' 'nosuch' name",
                   "LIST zzq3 'r1' 'nosuch' name ABSENT.IGNORE")
        parts = re.split(r"(?m)^LIST zzq3 'r1' 'nosuch' name", out)
        row("CONTROL: without it the unfound id is reported", len(parts) > 1 and "'nosuch' not found" in parts[1], "no report")
        row("THE ROW: with ABSENT.IGNORE it is not", len(parts) > 2 and "not found" not in parts[2] and "alpha" in parts[2],
            "report still there, or the record missing")

        say("\n--- leg 3: SORTED.SAMPLE (ref 438) ---------------------------------------------")
        out = sess(box, "LIST zzq3 name BY num SAMPLE 2", "LIST zzq3 name BY num SORTED.SAMPLE 2")
        parts = re.split(r"(?m)^LIST zzq3 name BY num SORTED\.SAMPLE 2", out)
        a, b = ids_in(parts[0]), ids_in(parts[1]) if len(parts) > 1 else []
        row("CONTROL: SAMPLE 2 takes the first two records and then sorts them: r2 r1", a == ["r2", "r1"], "got %r" % a)
        row("THE ROW: SORTED.SAMPLE 2 sorts and then takes two: r5 r4", b == ["r5", "r4"], "got %r" % b)

        say("\n--- leg 4: (COL.HDR.SPACE, ref 467, was retired 27 Oct 26 - S.87 batch 10) ---------")

        say("\n--- leg 5: FROM NONE (ref 378) ------------------------------------------------")
        out = sess(box, "SELECT zzq3 WITH num > 25", "LIST zzq3 name ID.SUP FROM NONE")
        row("THE ROW: FROM NONE ignores the active list and lists all five",
            len(re.findall(r"(?m)^(alpha|bravo|charlie|delta|echo)\s*$", out)) == 5, "wrong count")
        out = sess(box, "SELECT zzq3 WITH num > 25", "LIST zzq3 name ID.SUP")
        row("CONTROL: without it the active list (three records) is used",
            len(re.findall(r"(?m)^(alpha|bravo|charlie)\s*$", out)) == 3 and "delta" not in out, "wrong records")

        say("\n--- leg 6: BREAK.ON 'N' (ref 16) --------------------------------------------------")
        # the new page asks "Action (Abort/Quit/Next/Suppress pagination)"; an empty line answers it
        out = sess(box, "LIST zzq3 BY grp BREAK.ON \"'P'\" grp name HEADING \"Page 'P'\"", "", "",
                   "LIST zzq3 BY grp BREAK.ON \"'N'\" grp name HEADING \"Page 'P'\"", "", "")
        parts = re.split(r"(?m)^:LIST zzq3 BY grp BREAK\.ON \"'N'\" grp name", out)
        pages0 = re.findall(r"(?m)(?:^|: )Page\s+(\d+)\s*$", parts[0])
        pages1 = re.findall(r"(?m)(?:^|: )Page\s+(\d+)\s*$", parts[1]) if len(parts) > 1 else []
        row("CONTROL: 'P' starts a new page and the numbers run on: 1 2", pages0 == ["1", "2"], "got %r" % pages0)
        row("THE ROW: 'N' starts a new page numbered 1 again: 1 1", pages1 == ["1", "1"], "got %r" % pages1)

        say("\n--- leg 7: NO.PAGE on SELECT (ref 379) ----------------------------------------")
        out = sess(box, "SELECT zzq3 WITH num > 25 NO.PAGE")
        row("SELECT accepts NO.PAGE", re.search(r"(?i)3 record\(s\) selected", out) is not None, "no 'selected' line")

        say("\n--- leg 8: SEARCH FOR (ref 190) and SEARCH ALL (ref 221) ---------------------------")
        out = sess(box, 'SEARCH zzq3 FOR "alp" "ech"', 'SEARCH zzq3 FOR "r3"', 'SEARCH zzq3 ALL FOR "r3"')
        sel = re.findall(r"(?m)^(\d+) record\(s\) selected to list 0", out)
        row("SEARCH FOR with two strings selects alpha and echo: 2 records", sel[:1] == ["2"], "selected lines: %r" % sel)
        row("CONTROL: 'r3' occurs only in a record id, so without ALL nothing matches: 0", sel[1:2] == ["0"], "selected lines: %r" % sel)
        row("THE ROW: with ALL the id is searched too: 1", sel[2:3] == ["1"], "selected lines: %r" % sel)

        say("\n--- leg 9: REPORTING on COUNT (ref 416) -------------------------------------------")
        prog("zzq3mk", "   open 'zzq3r' to f else stop 'no file'\n   for i = 1 to 2500\n      write 'x' to f, 'k':i\n   next i\nend\n")
        out = sess(box, "CREATE.FILE zzq3r", "BASIC bp zzq3mk", "RUN bp zzq3mk", "COUNT zzq3r", "COUNT zzq3r WITH @ID > 'a' REPORTING")
        row("setup: 2500 records were written", re.search(r"(?m)^2500 record\(s\) counted", out) is not None, "no 2500 line")
        parts = out.split("COUNT zzq3r WITH @ID > 'a' REPORTING")
        tail = parts[-1]
        ex = re.findall(r"(?m)^(\d+) record\(s\) examined", tail)
        row("THE ROW: REPORTING says 1000 and 2000 records examined", ex == ["1000", "2000"], "examined lines: %r" % ex)
        row("CONTROL: and the plain COUNT before it printed none", "examined" not in parts[0].split("COUNT zzq3r WITH")[0].split("COUNT zzq3r")[-1], "examined seen early")
        sess(box, "DELETE.FILE DICT zzq3r", "DELETE.FILE zzq3r", quiet=True)

        say("\n--- leg 10: SELECT with a bare field name is SAVING MULTIVALUED (ref 39) ------------")
        prog("zzq3ls", "   loop\n      readnext x else exit\n      crt 'L[':x:']'\n   repeat\nend\n")
        out = sess(box, "BASIC bp zzq3ls", "SELECT zzq3 WITH num > 25", "RUN bp zzq3ls", "SELECT zzq3 WITH num > 25 name", "RUN bp zzq3ls")
        parts = out.split("SELECT zzq3 WITH num > 25 name")
        ctl = re.findall(r"(?m)^L\[(.*)\]\s*$", parts[0])
        got = re.findall(r"(?m)^L\[(.*)\]\s*$", parts[-1])
        row("CONTROL: a plain SELECT leaves the record ids on the list: r1 r2 r3", ctl == ["r1", "r2", "r3"], "got %r" % ctl)
        row("THE ROW: SELECT ... name leaves the values of name: alpha bravo charlie", got == ["alpha", "bravo", "charlie"], "got %r" % got)

        say("\n--- leg 11: REFORMAT with @RECORD (ref 546) -------------------------------------------")
        out = sess(box, "CREATE.FILE zzq3o", "REFORMAT zzq3 name @RECORD TO zzq3o",
                   "COPY FROM zzq3o TO BP alpha", "DELETE.FILE DICT zzq3o", "DELETE.FILE zzq3o")
        cp = os.path.join(bp, "alpha")
        made.append("alpha")
        body = open(cp, "rb").read().decode("ascii", "replace").splitlines() if os.path.exists(cp) else None
        row("THE ROW: the first item is the new record's id (alpha); @RECORD supplies its fields: alpha 50 a",
            body == ["alpha", "50", "a"], "got %r" % (body,))

        say("\n--- leg 12: 27 Oct 26 (S.87 batch 4) second spellings of keywords, THAN, ONLY before the file, => =< >< and fields 9998 / 9999 ---")
        # A new account's VOC is the tree's NEWVOC, which no longer holds the fourteen records; the thirteen spellings that stay are all there.
        # (THAN, the noise word, is NOT in this batch: removing it turned "greater than 25" into a sentence with two values, see the survey's D-010.)
        gone = ["col.spcs", "display.name", "evaluate", "calculate", "intersection", "difference", "margin", "stats", "supp", "only",
                "=>", "=<", "><"]
        kept = ["col.spaces", "col.hdg", "eval", "calc", "intersect", "diff", "left.margin", "statistics", "hdr.sup", "id.only", "than", ">=", "<=", "<>"]
        # A program reads each id from the VOC.  The record ids of the comparison symbols are the symbols themselves; only their FILE names in newvoc spell them %E%G (=>), %E%L (=<),
        # %G%L (><), %G%E (>=), %L%E (<=) and %L%G (<>).  A COUNT sentence with the quoted file-name spelling found none of them, which would have passed the removed side for nothing.
        prog("zzq3v", "   open 'VOC' to v else stop 'no voc'\n   ids = '" + "':@fm:'".join(gone + kept) + "'\n"
             "   for i = 1 to dcount(ids, @fm)\n      read r from v, ids<i> then crt 'Y[':ids<i>:']' else crt 'N[':ids<i>:']'\n   next i\nend\n")
        out = sess(box, "BASIC bp zzq3v", "RUN bp zzq3v", quiet=True)
        found = re.findall(r"(?m)^Y\[(.*)\]\s*$", out)
        absent = re.findall(r"(?m)^N\[(.*)\]\s*$", out)
        row("CONTROL: the fourteen surviving spellings (THAN among them) are all in the VOC", sorted(found) == sorted(kept), "found %r" % found)
        row("THE ROW: none of the thirteen removed records is", sorted(absent) == sorted(gone), "absent %r" % absent)

        # sentences: each removed word beside the surviving one.  A sentence the query processor cannot read lists nothing.
        names = lambda seg: re.findall(r"(?m)^(alpha|bravo|charlie|delta|echo)\b", seg)
        pairs = [("GE 30", "=> 30", ["alpha", "bravo", "charlie"], "=>"),
                 ("LE 30", "=< 30", ["charlie", "delta", "echo"], "=<"),
                 ("NE 30", ">< 30", ["alpha", "bravo", "delta", "echo"], "><")]
        sentences = []
        for good, bad, _w, _n in pairs:
            sentences += ["LIST zzq3 name WITH num %s ID.SUP" % good, "LIST zzq3 name WITH num %s ID.SUP" % bad]
        sentences += ["LIST zzq3 name COL.SPACES 3 ID.SUP", "LIST zzq3 name COL.SPCS 3 ID.SUP", "LIST zzq3 name HDR.SUP ID.SUP", "LIST zzq3 name SUPP ID.SUP",
                      "LIST zzq3 name COL.HDG \"Nm\" ID.SUP", "LIST zzq3 name DISPLAY.NAME \"Nm\" ID.SUP",
                      "LIST zzq3 ID.ONLY", "LIST ID.ONLY zzq3", "LIST ONLY zzq3", "LIST zzq3 ONLY"]
        out = sess(box, *sentences, quiet=True)
        seg, pos = {}, 0
        for s in sentences:
            i = out.find(s, pos)
            seg[s] = (i, None)
            pos = i + len(s) if i >= 0 else pos
        order = [(seg[s][0], s) for s in sentences]
        text = {}
        for k, (i, s) in enumerate(order):
            j = order[k + 1][0] if k + 1 < len(order) else len(out)
            text[s] = out[i:j] if i >= 0 else ""
        for good, bad, want, nm in pairs:
            g, bd = text["LIST zzq3 name WITH num %s ID.SUP" % good], text["LIST zzq3 name WITH num %s ID.SUP" % bad]
            row("CONTROL: WITH num %s lists %s (in the file's order)" % (good, " ".join(want)), sorted(names(g)) == sorted(want), "got %r" % names(g))
            row("THE ROW: WITH num %s lists nothing (%s is not a comparison any more)" % (bad, nm), names(bd) == [], "got %r" % names(bd))
        for good, bad in (("COL.SPACES 3", "COL.SPCS 3"), ("HDR.SUP", "SUPP"), ("COL.HDG \"Nm\"", "DISPLAY.NAME \"Nm\"")):
            g, bd = text["LIST zzq3 name %s ID.SUP" % good], text["LIST zzq3 name %s ID.SUP" % bad]
            row("CONTROL: %s lists the five names" % good, len(names(g)) == 5, "got %r" % names(g))
            row("THE ROW: %s lists nothing (it is not a keyword in a new account)" % bad, names(bd) == [], "got %r" % names(bd))
        ctl = ids_in(text["LIST zzq3 ID.ONLY"])
        row("CONTROL: LIST zzq3 ID.ONLY lists the five ids", sorted(ctl) == ["r1", "r2", "r3", "r4", "r5"], "got %r" % ctl)
        for s in ("LIST ID.ONLY zzq3", "LIST ONLY zzq3", "LIST zzq3 ONLY"):
            row("THE ROW: %s lists no record" % s, ids_in(text[s]) == [], "got %r" % ids_in(text[s]))

        # THAN, measured: with the record there it is ignored; with the record taken out it is read as a value, so LESS THAN 25 means "less than THAN or less than 25".
        # This is why D-010 was held back (the survey said the sentence would be an error).  Nothing puts the record back: the sandbox is disposable.
        lt = "LIST zzq3 name WITH num LESS THAN 25 ID.SUP"
        out = sess(box, lt, "DELETE VOC than", lt, quiet=True)
        i1 = out.find(lt)
        i2 = out.find("DELETE VOC than")
        i3 = out.find(lt, i2)
        with_than, without = names(out[i1:i2]), names(out[i3:])
        row("CONTROL: with the than record LESS THAN 25 lists delta and echo", sorted(with_than) == ["delta", "echo"], "got %r" % with_than)
        row("MEASURED: with the than record deleted LESS THAN 25 lists all five (than is a value)", sorted(without) == ["alpha", "bravo", "charlie", "delta", "echo"],
            "got %r" % without)

        # dictionary items whose field location is 9998 or 9999: an ordinary (empty) field now, not the item count and the record length
        prog("zzq3d8", "D\n9998\n\nni9998\n10R\nS\n")
        prog("zzq3d9", "D\n9999\n\nlen9999\n10R\nS\n")
        out = sess(box, "COPY FROM BP TO DICT zzq3 zzq3d8,ni9998", "COPY FROM BP TO DICT zzq3 zzq3d9,len9999",
                   "LIST zzq3 num ID.SUP", "LIST zzq3 ni9998 ID.SUP", "LIST zzq3 len9999 ID.SUP", quiet=True)
        s1, s2, s3 = out.find("LIST zzq3 num ID.SUP"), out.find("LIST zzq3 ni9998 ID.SUP"), out.find("LIST zzq3 len9999 ID.SUP")
        numbers = lambda seg: re.findall(r"(?m)^\s*(\d+)\s*$", seg)
        row("CONTROL: the number column lists 50 40 30 20 10", sorted(numbers(out[s1:s2])) == ["10", "20", "30", "40", "50"], "got %r" % numbers(out[s1:s2]))
        row("THE ROW: field 9998 is empty: no number is listed (it used to be the item count)", s2 > 0 and numbers(out[s2:s3]) == [], "got %r" % numbers(out[s2:s3]))
        row("THE ROW: field 9999 is empty: no number is listed (it used to be the record length)", s3 > 0 and numbers(out[s3:]) == [], "got %r" % numbers(out[s3:]))
    finally:
        for n in made:
            for d in ("bp", "bp.out"):
                p = os.path.join(sysd, d, n)
                if os.path.exists(p):
                    os.remove(p)
        sess(box, "DELETE.FILE DICT zzq3", "DELETE.FILE zzq3", quiet=True)

    say("\nsandbox-qproc-a3: %d passed, %d failed" % (passed, failed))
    sys.exit(0 if failed == 0 else 1)


if __name__ == "__main__":
    main()
