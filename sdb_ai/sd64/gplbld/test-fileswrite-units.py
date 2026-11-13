#!/usr/bin/env python3
"""test-fileswrite-units.py - the server-side WRITE GROUP of the files-only (SDNet) login, S.65, as invariants read off the source.

  python sdb_ai/sd64/gplbld/test-fileswrite-units.py
  python sdb_ai/sd64/gplbld/test-fileswrite-units.py --selftest
  (13 Nov 26 Windows port - from Linux 44807a43, RELEASE_1.1 254: message ids are Linux's + 1005; the groups are Windows local groups, made by
  gplbld/sync-route-groups.ps1 (run by sd.iss) and removed by sd.iss RemoveSdGroups, changed through !os_group (Windows has no sd-elevate, so its
  whitelist rows are out); apisrvr's session works out the write and administration flags for itself after the K$HANDOFF and a group that cannot be read
  is "no write" (fail closed) where Linux refuses the login; modify.account dispatches on upcase(action) with no RETURN.  The text below is Linux's.)

No sudo, no install, no sd.  Exit 0 every check passed, 1 a check failed, 2 it could not run.  Written 18 Oct 26.

20 Oct 26 (S.72b, RECORDLOCKED() of a remote file becomes write-governed; the owner's decision of that day): request 34 JOINS THE CHANGE SET, so a files-only login without sdfileswrite that sends
request 34 is refused by the generic gate of apisrvr (message 12526, the audit line `api refused request=34 route=sdfiles write=off ...`), exactly as for 32 and 33, and a login with the group is served as before.  The
reads (6, 40, 41 with flag 0 ...) and release (15) still need sdfiles alone.  Written BEFORE the code and shown red on the unchanged tree.  CHANGE gains 34 (F1 and F2a follow); F17 flips (34 stays in the allow table AND
is now in the change set with 32 and 33); the old mutant `recordlocked (34) joins the change set` is the baseline reality now and is replaced by `recordlocked (34) leaves the change set`; F2d is new (the model of
apisrvr's whole decision for a files-only login - served or refused, and which text - printed for request 34 and its neighbours, with the null case that a model which refuses everything or serves everything fails
it), F18 is new (request 34 is refused by the SAME generic gate and by no code of its own: no request number in the gate block, no gate in vb.recordlocked, the dispatch slot is still vb.recordlocked), with 6 new
mutants and one replaced (77 in all, selftest ~7 s): the change set loses 34, the allow table loses 34, the change set holds 34 twice, the gate of apisrvr has an exception for 34, vb.recordlocked refuses on its own, the
dispatch loses an entry before slot 34.  F18 passes on the unchanged tree on purpose: it pins "apisrvr is not changed", it does not flip.

20 Oct 26 (S.72, QMNet parity, tiers A and B): F16 and F17 and 9 more mutants (72 in all). The SDNet client now sends requests 32, 33 and 34 for FILELOCK, FILEUNLOCK and RECORDLOCKED(), so apisrvr's
vb.filelock (both branches: the waiting one and the no-wait one with the LOCKED clause), vb.fileunlock and vb.recordlocked are held to the file number the request NAMED (files(fno), never the stale files(i) of the
last open - the K8a fault of 19 Oct, whose blocking branch had no row and a mutant that survived: the runtime rows are sandbox-req29.py F10-F19) and to handing STATUS() back; 32 and 33 stay in the change set
(and 34 stayed out in this sitting - S.72b above, the same day, put it in).

19 Oct 26 (finish 2, verifier): F11 follows set.files after its failure path learned to say what happened - when the write group went and the step after it failed, the audit line for THAT removal
(modify.account files-write-off, not the action asked for) and the write group's line (write.removed.line, the routine the success path prints it with too) come before the failure message - with
3 new mutants for it (and the one for the success path's line rewritten for the new text).  The anchor of the mutant that moves the write block after the group change (write_group_last) is
the start of the failure block, which now begins with the write.removed lines: without that the --selftest stopped on it (found 19 Oct 26 by running the selftest; 63 of 63 mutants killed after).
19 Oct 26 (K1, K4a): F15 bounds message 12526 at 100 characters (the SDNet client shows an ON ERROR reply's text cut there); F11 is rewritten for set.files after K4a - the write
group is read before the 'already had it' answer, FILES-OFF has nothing to do only for a person in neither group, the write group goes out FIRST and every group change is
change.files.group, which reads the membership back - with 13 new mutants (60 in all), one of which moves the write block after the group change (the 18 Oct order).  The
program itself is RUN by sandbox-filesgrp.py against a scratch group file.

THE RULE (owner, 18 Oct 2026, "yes"): a files-only login (the Linux group sdfiles) may CHANGE files on this server and take record or file locks only if
the user is ALSO in the Linux group sdfileswrite, which is off for a new account and given by SDSYS (modify.account <account> files-write-on).  The change
set is requests 7 to 10 (the locking reads), 16 to 19 (write, writeu, delete, deleteu), 30 (lock record), 31 (clearfile), 32 (filelock), 33 (fileunlock),
34 (recordlocked, since S.72b: it tells who holds a lock, by his user number on this server) and any nonzero flag of 41 (readv takes a lock with flags 1, 2, 5 and 6).
Reads, selects, readv with flag 0, fileinfo, the indices and release (15) need sdfiles alone.  A member of sdapi has the whole API as before.  And the
dictionary open: apisrvr's vb.open takes "dict <file>" in any case.

***WHAT THIS IS, AND WHAT IT IS NOT.***  It reads the BASIC and shell sources as text with the comments removed, so a gate that survives only in a comment
does not count.  IT RUNS NOTHING, so it cannot say that the gate refuses anybody: sandbox-net.py (the REAL !apifilesok compiled and asked about every number
with the write flag 0 and 1; the words where no root is needed), sandbox-netfile.py section wgroup and netfake.py --selftest (the refusal and its evidence, on
the fake), sandbox-qmclient.py rows H0a to H0d (the dictionary open on a REAL API server) and the VM witness (a real files-only login refused on the wire).
What a text check is for here is ORDER and EXACT NAMES: the group name is spelt the same in nine places, the write flag is read in the one place that reads
the other group, the gate passes the login's own flag and not a constant, and the dictionary branch comes before the plain open.

--selftest runs every check on the real sources and then on a copy of them with one deliberate fault at a time: each must make a check fail.
"""

import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SD64 = os.path.normpath(os.path.join(HERE, ".."))
ROOT = os.path.normpath(os.path.join(SD64, "..", ".."))
GPL = os.path.join(SD64, "sdsys", "gpl.bp")
SDSYS = os.path.join(SD64, "sdsys")

BP = ("apifilesok", "apisrvr", "modifya", "createa", "create_account", "acc_os_info", "restorea")
# 13 Nov 26 Windows port: Linux's installsdcore.sh, deletesdcore.sh and sd-elevate.  The groups are made by sync-route-groups.ps1 (sd.iss runs it) and
# removed by sd.iss; there is no sd-elevate (the SDSYS session changes a group itself through !os_group), so nothing here stands for it.
SH = {"sync-route-groups.ps1": HERE, "sd.iss": HERE}

CHANGE = (7, 8, 9, 10, 16, 17, 18, 19, 30, 31, 32, 33, 34)    # written here from the spec, not read from the program (34, recordlocked: S.72b, 20 Oct 26)
ADMIN = (68, 69, 70, 71)    # the administration set (21 Oct 26, S.73 item 3): in the allow table, and needing the write flag AND the administration flag, each exactly 1
ALLOWED = (1, 2, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 26, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 49, 68, 69, 70, 71)


def strip_bas(src):
    out = []
    for line in src.split("\n"):
        s = line.lstrip()
        if s.startswith("*") or s.startswith("!"):
            out.append("")
            continue
        cut = line.find(";*")
        out.append(line if cut < 0 else line[:cut])
    return "\n".join(out)


def strip_sh(src):
    return "\n".join("" if l.lstrip().startswith("#") else l for l in src.split("\n"))


def strip_strings(src):
    return re.sub(r"'[^'\n]*'|\"[^\"\n]*\"", "''", src)


def ordered(text, *needles):
    pos = -1
    for n in needles:
        p = text.find(n, pos + 1)
        if p < 0:
            return False
        pos = p
    return True


def routine_body(text, label):
    """From the line `label:` to the next line that starts a label (a word and a colon in column 1) or the end."""
    m = re.search(r"^%s:\s*$" % re.escape(label), text, re.M)
    if not m:
        return ""
    n = re.search(r"^[A-Za-z][A-Za-z0-9.$_]*:\s*$", text[m.end():], re.M)
    return text[m.start(): m.end() + (n.start() if n else len(text))]


def load():
    raw = {}
    for n in BP:
        with open(os.path.join(GPL, n), encoding="utf-8", errors="replace") as f:
            raw[n] = f.read()
    for n, d in SH.items():
        with open(os.path.join(d, n), encoding="utf-8", errors="replace") as f:
            raw[n] = f.read()
    with open(os.path.join(SDSYS, "syscom", "createacc.h"), encoding="utf-8", errors="replace") as f:
        raw["createacc.h"] = f.read()
    for num in (12485, 12526, 12527, 12528, 12529, 12530, 12531):
        try:
            with open(os.path.join(SDSYS, "messages", str(num)), encoding="utf-8", errors="replace") as f:
                raw["msg:%d" % num] = f.read()
        except OSError:
            raw["msg:%d" % num] = ""          # a message that is not there is a failed check (F15), not a program that cannot run
    return raw


def strip_iss(src):
    """sd.iss with its comments taken out: `;` lines, `//` lines and `{ ... }` blocks (a `{` right after a quote is an Inno constant such as '{sys}', kept)."""
    src = "\n".join("" if l.lstrip().startswith((";", "//")) else l for l in src.split("\n"))
    return re.sub(r"(?<!')\{[^}]*\}", "", src)


def code(name, text):
    if name == "sd.iss":
        return strip_iss(text)
    if name in SH:
        return strip_sh(text)
    if name.startswith("msg:") or name == "createacc.h":
        return text if name.startswith("msg:") else strip_bas(text)
    return strip_bas(text)


def model_filesok(fo, action, entered, writeok, adminok=0):
    """What !apifilesok answers, run in Python on the tables read from its source (the tests after them are held to this order by F2)."""
    ok = ",".join([""] + re.findall(r"^files\.ok := '(\d+),'", fo, re.M)) + ","
    chg = ",".join([""] + re.findall(r"^files\.chg := '(\d+),'", fo, re.M)) + ","
    adm = ",".join([""] + re.findall(r"^files\.adm := '(\d+),'", fo, re.M)) + ","
    if action == "":
        return 0
    if not re.fullmatch(r"[+-]?(?:\d+\.?\d*|\.\d+)", action):
        return 0
    if float(action) == 3:
        return 0 if entered else 1
    if ("," + action + ",") not in ok:
        return 0
    if writeok != 1 and ("," + action + ",") in chg:
        return 0
    if ("," + action + ",") in adm and (writeok != 1 or adminok != 1):
        return 0
    return 1


def model_gate(fo, action, files_write, files_admin=0):
    """What apisrvr's gate does with request ACTION for a files-only login (the account entered) whose write flag is FILES_WRITE and administration flag FILES_ADMIN (0 or 1): the tests of the gate
    block, run on the tables of !apifilesok (the text of the block is held to exactly these tests by F6): `served`, or `refused <message> write=<on|off> admin=<on|off>` - 12526 when the write flag is
    false and the request WOULD be allowed with it, 12529 when the administration flag is false and the request would be allowed with it (or when both are false and it would be allowed with both),
    12485 otherwise.  (20 Oct 26, S.72b; 21 Oct 26, S.73 item 3)"""
    if model_filesok(fo, action, 1, files_write, files_admin):
        return "served"
    tail = " write=" + ("on" if files_write else "off") + " admin=" + ("on" if files_admin else "off")
    if not files_write and model_filesok(fo, action, 1, 1, files_admin):
        return "refused 12526" + tail
    if not files_admin and model_filesok(fo, action, 1, files_write, 1):
        return "refused 12529" + tail
    if not files_write and not files_admin and model_filesok(fo, action, 1, 1, 1):
        return "refused 12529" + tail
    return "refused 12485" + tail


# S.72b, written here from the owner's decision and not read from the program: what apisrvr does with a request of a files-only login, by the write flag of the login (0 without sdfileswrite, 1 with it).
# Request 34 is the new row; 32 and 33 are its neighbours that were already refused; the reads (6, 40, 41 - flag 0 is vb.readv's own test, F8 -, 12, 26) and release (15) need sdfiles alone; 29, 20 and 21 are
# not in the allow table at all (12485, whatever the group says), and the audit word follows the login's own flag.
# 21 Oct 26, S.73 item 3: each row is now (request, write flag, administration flag, answer), the audit words follow BOTH flags, and the administration set (68 to 71) needs both: 12529 when the
# administration group is what is missing (or both are), 12526 when only the write group is, and a number that is not in the table is 12485 whatever the groups say.
F2D_WANT = (
    (34, 0, 0, "refused 12526 write=off admin=off"), (34, 1, 0, "served"),
    (32, 0, 0, "refused 12526 write=off admin=off"), (32, 1, 0, "served"),
    (33, 0, 0, "refused 12526 write=off admin=off"), (33, 1, 0, "served"),
    (30, 0, 0, "refused 12526 write=off admin=off"), (30, 1, 0, "served"),
    (16, 0, 0, "refused 12526 write=off admin=off"), (16, 1, 0, "served"), (16, 0, 1, "refused 12526 write=off admin=on"),
    (6, 0, 0, "served"), (6, 1, 0, "served"),
    (15, 0, 0, "served"), (15, 1, 0, "served"),
    (40, 0, 0, "served"), (41, 0, 0, "served"), (12, 0, 0, "served"), (26, 0, 0, "served"), (35, 0, 0, "served"),
    (29, 0, 0, "refused 12485 write=off admin=off"), (29, 1, 0, "refused 12485 write=on admin=off"), (29, 1, 1, "refused 12485 write=on admin=on"),
    (20, 0, 0, "refused 12485 write=off admin=off"), (21, 1, 0, "refused 12485 write=on admin=off"),
    (70, 0, 0, "refused 12529 write=off admin=off"), (70, 1, 0, "refused 12529 write=on admin=off"), (70, 0, 1, "refused 12526 write=off admin=on"), (70, 1, 1, "served"),
    (71, 1, 0, "refused 12529 write=on admin=off"), (71, 1, 1, "served"),
    (68, 0, 0, "refused 12529 write=off admin=off"), (68, 1, 0, "refused 12529 write=on admin=off"), (68, 1, 1, "served"),
    (69, 0, 1, "refused 12526 write=off admin=on"), (69, 1, 1, "served"),
    (72, 1, 1, "refused 12485 write=on admin=on"), (61, 1, 1, "refused 12485 write=on admin=on"),
)
SHOW = ("F2d",)          # the checks whose detail is printed even when they pass (the real inputs and the answers they were compared with)


def sysmsg_calls(text):
    out = []
    for m in re.finditer(r"sysmsg\(\s*(\d+)\s*(?:,([^)\n]*))?\)", text):
        args = [a.strip() for a in (m.group(2) or "").split(",") if a.strip()]
        out.append((int(m.group(1)), args))
    return out


def run_checks(raw):
    """{label: (ok, detail)} for every check, on these sources."""
    c = {n: code(n, t) for n, t in raw.items()}
    fo, ap, mo, cr, ca2, ai, rs = (c[n] for n in ("apifilesok", "apisrvr", "modifya", "createa", "create_account", "acc_os_info", "restorea"))
    srg, iss, hdr = c["sync-route-groups.ps1"], c["sd.iss"], c["createacc.h"]      # 13 Nov 26 Windows port: Linux's installer, deletesdcore and sd-elevate
    res = {}

    def ck(label, ok, detail=""):
        res[label] = (bool(ok), detail)

    # ---- F1-F2. !apifilesok -------------------------------------------------------------------------------------------------------------
    chg = [int(x) for x in re.findall(r"^files\.chg := '(\d+),'", fo, re.M)]
    ok_nums = [int(x) for x in re.findall(r"^files\.ok := '(\d+),'", fo, re.M)]
    adm = [int(x) for x in re.findall(r"^files\.adm := '(\d+),'", fo, re.M)]
    ck("F1 the change set is exactly 7 8 9 10 16 17 18 19 30 31 32 33 34 (S.72b: recordlocked is the last), once each, starts from ',', and is a subset of the allow table; the administration set (S.73 item 3) is exactly "
       "68 69 70 71, once each, starts from ',', and is a subset of the allow table and disjoint from the change set; the table's own 37 numbers are untouched and 68 to 71 are the only additions",
       sorted(chg) == sorted(CHANGE) and re.search(r"^files\.chg = ','\s*$", fo, re.M) is not None and set(chg) <= set(ok_nums) and sorted(ok_nums) == sorted(ALLOWED)
       and sorted(adm) == sorted(ADMIN) and re.search(r"^files\.adm = ','\s*$", fo, re.M) is not None and set(adm) <= set(ok_nums) and not (set(adm) & set(chg)),
       repr((sorted(set(chg) ^ set(CHANGE)), sorted(set(ok_nums) ^ set(ALLOWED)), sorted(set(adm) ^ set(ADMIN)))))
    wrong = []
    for n in range(0, 81):
        for e in (0, 1):
            for w in (1, 0, 2):
                for a in (1, 0, 2):         # 21 Oct 26, S.73 item 3: the administration flag too, exactly 1 and not
                    got = model_filesok(fo, str(n), e, w, a)
                    if n == 3:
                        want = 0 if e else 1
                    elif n not in ALLOWED:
                        want = 0
                    elif w != 1 and n in CHANGE:
                        want = 0
                    elif n in ADMIN and (w != 1 or a != 1):
                        want = 0
                    else:
                        want = 1
                    if got != want:
                        wrong.append((n, e, w, a, got, want))
    ck("F2a the program's tables, run in Python for every request number 0 to 80, the account entered and not, the write flag and the administration flag each exactly 1, 0 and 2, agree with the lists written "
       "out in this file: the change set is refused unless the write flag is exactly 1, the administration set (68 to 71) unless BOTH are, 3 is allowed once, everything else as before (a number wrong in either direction fails)",
       not wrong, repr(wrong[:6]))
    ck("F2b ...and the tests after the tables are exactly these, in this order: empty is 0, not a number is 0, 3 once, a number outside the allow table is 0, THEN a flag that is "
       "not exactly 1 (`writeok # 1`) refuses a number in the change set (commas on both sides), THEN a number in the administration set is refused unless writeok AND adminok are exactly 1, and the default is 1 - so the groups can only take away from the "
       "table, never add to it, and 7 cannot match 17",
       re.search(r"if action = '' then return 0\s*\n\s*if not\(num\(action\)\) then return 0\s*\n\s*if action = 3 then\s*\n\s*if entered then return 0\s*\n\s*return 1\s*\n"
                 r"\s*end\s*\n\s*if not\(index\(files\.ok, ',' : action : ',', 1\)\) then return 0\s*\n"
                 r"\s*if writeok # 1 then\s*\n\s*if index\(files\.chg, ',' : action : ',', 1\) then return 0\s*\n\s*end\s*\n"
                 r"\s*if index\(files\.adm, ',' : action : ',', 1\) then\s*\n\s*if writeok # 1 then return 0\s*\n\s*if adminok # 1 then return 0\s*\n\s*end\s*\n\s*return 1\s*\n\s*end\s*$", fo) is not None
       and ordered(fo, "files.ok := ", "files.chg := ", "files.adm := ", "if action = '' then return 0"), "")
    ck("F2c ...it is still a $internal function catalogued once as !apifilesok with four parameters, and still PURE (no read, write, open, kernel call, execute, prompt)",
       "$internal" in fo and re.search(r"^function apifilesok\(action, entered, writeok, adminok\)\s*$", fo, re.M) is not None and re.search(r"^\$catalog !apifilesok\s*$", fo, re.M) is not None
       and not re.search(r"\b(?:kernel|read|readv|readu|open|openseq|openpath|write|writeu|writev|delete|execute|os\.execute|select|readnext|input|crt|display|print|call|gosub|goto|void)\b",
                         strip_strings(fo)), "")

    got_ = [(n, w, a_, model_gate(fo, str(n), w, a_), want) for n, w, a_, want in F2D_WANT]
    bad_ = [(n, w, a_, g_, want) for n, w, a_, g_, want in got_ if g_ != want]
    nul_ = [model_gate("", str(n), w, a_) == want for n, w, a_, want in F2D_WANT]          # the same rows on a program with NO tables at all
    ck("F2d S.72b (20 Oct 26) THE WHOLE DECISION OF THE GATE, run in Python on the tables read from the source, for a files-only login without sdfileswrite (flag 0) and with it (flag 1): request 34 "
       "(recordlocked) is REFUSED with message 12526 and the audit word write=off without the group and SERVED with it - exactly as 30 (lock record), 32, 33 and 16 -, the reads 6, 12, 26, 35, 40, 41 and "
       "release 15 are served to both, and 29, 20 and 21 (not in the allow table) are 12485 whatever the group says, with write=on when the login has it.  THE NULL CASE: the same %d rows asked of a program "
       "with no tables at all must NOT all agree (a model that refuses everything, or serves everything, passes none of the pairs).  Printed: every request, flag and answer"
       % len(F2D_WANT),
       not bad_ and not all(nul_) and any(g_ == "served" for _n, _w, _a, g_, _x in got_) and any(g_.startswith("refused 12526") for _n, _w, _a, g_, _x in got_)
       and any(g_.startswith("refused 12529") for _n, _w, _a, g_, _x in got_),
       "; ".join("%d/w%d/a%d -> %s" % (n, w, a_, g_) for n, w, a_, g_, _x in got_) + ("   WRONG: " + repr(bad_[:6]) if bad_ else "")
       + "   | NULL CASE (a program with no tables): %d of %d rows agree with the wanted answers" % (sum(nul_), len(nul_)))

    # ---- F3-F8. apisrvr -----------------------------------------------------------------------------------------------------------------
    cm_i = ap.find("common /$APISRVR/")
    cm = ap[cm_i:ap.find("seq.unbuf(SEQ.MAX)", cm_i)] if cm_i >= 0 else ""
    fi = ap.find("\nvb.scram.final:")
    fin = ap[fi:] if fi >= 0 else ""
    ck("F3 apisrvr declares the four-argument function, keeps the write flag in the COMMON block /$APISRVR/ beside files.only (a plain variable is set afresh by a runtime abort, "
       "which would hand a login the write group it has not got), and starts it false ONCE in the first-time block beside files.only",
       re.search(r"^deffun apifilesok\(action, entered, writeok, adminok\) calling '!apifilesok'\s*$", ap, re.M) is not None and re.search(r"^files\.write,", cm, re.M) is not None
       and len(re.findall(r"(?<![\w.])files\.write = @false", ap)) == 1 and ordered(ap, "if not(kernel(K$CPROC.LEVEL,0)) then", "files.only = @false", "files.write = @false", 'openpath "voc" to voc else'), "")
    # 13 Nov 26 Windows port: F4, F5 and F20 hold Windows's shape.  The session that serves the requests is a NEW pre-authenticated process (K$HANDOFF): it never ran SCRAM,
    # so it works the mark out for itself at start, by its own logname, in the first-time block (sess below); the front (vb.scram.final) reads the same groups only for the
    # login's audit line.  A write or administration group that cannot be read is "no write" / "no administration" (fail closed: Windows cannot tell "no such group" from
    # "could not read"), where Linux refuses the login with 10073; the sdapi and sdfiles lookups still refuse (connection.failed, 10073).  No K$ASSUME.USER here.
    si = ap.find("if api.preauth<1> = 1 and downcase(logname) # 'sdsys' then")
    sess = ap[si: ap.find('openpath "voc" to voc else', si)] if si >= 0 else ""
    ck("F4 THE READ: the session reads the group sdfileswrite ONCE, by its own logname, INSIDE the sdfiles route - after sdapi is read and found false, after sdfiles is read and found, "
       "after files.only = @true - with the status read at once (a lookup that cannot answer is no write); a session whose sdapi or sdfiles lookup cannot answer, or who is in neither, "
       "is refused (10073) and never reads it; the front reads it once too, by scram.user, inside the same route, for the audit line only (status nonzero is no write); both flags start false",
       ap.count("is_grp_member(logname, 'sdfileswrite')") == 1 and ap.count("is_grp_member(scram.user, 'sdfileswrite')") == 1
       and ordered(sess, "api.in.sdapi = is_grp_member(logname, 'sdapi')", "api.route.stat = status()", "if api.route.stat # 0 then", "sysmsg(10073, logname)", "goto connection.failed",
                   "if not(api.in.sdapi) then", "api.in.sdfiles = is_grp_member(logname, 'sdfiles')", "api.files.stat = status()", "if api.files.stat # 0 or not(api.in.sdfiles) then",
                   "sysmsg(10073, logname)", "goto connection.failed", "files.only = @true", "api.write.in = is_grp_member(logname, 'sdfileswrite')")
       and re.search(r"api\.write\.in = is_grp_member\(logname, 'sdfileswrite'\)\s*\n\s*api\.write\.stat = status\(\)\s*\n\s*files\.write = \(api\.write\.in and api\.write\.stat = 0\)\s*\n", sess) is not None
       and ordered(fin, "api.files.login = @false", "api.files.write = @false", "api.in.sdapi = is_grp_member(scram.user, 'sdapi')", "if not(api.in.sdapi) then",
                   "api.files.login = @true", "api.files.write = is_grp_member(scram.user, 'sdfileswrite')")
       and re.search(r"api\.files\.write = is_grp_member\(scram\.user, 'sdfileswrite'\)\s*\n\s*api\.write\.stat = status\(\)\s*\n\s*if api\.write\.stat # 0 then api\.files\.write = @false\s*\n", fin) is not None, "")
    ck("F5 THE MARK: files.write is set in the one place files.only is made true (the session's own test, inside `if not(api.in.sdapi) then`), from that session's own read, "
       "is never cleared, and is assigned in exactly two places (the initialisation and that one); the front never sets it (a mark in the front's variables never reaches the session); "
       "no other program mentions it",
       len(re.findall(r"(?<![\w.])files\.write\s*=(?!=)", ap)) == 2 and len(re.findall(r"(?<![\w.])files\.only = @true", ap)) == 1
       and ordered(sess, "if not(api.in.sdapi) then", "files.only = @true", "files.write = (api.write.in and api.write.stat = 0)")
       and not re.search(r"(?<![\w.])files\.(?:write|admin|only)\s*=", fin)
       and not any(re.search(r"(?<![\w.])files\.write(?![\w.])", t) for n, t in c.items() if n not in ("apisrvr",) and n in BP), "")
    gi = ap.find("if files.only then")
    gb = ap[gi:ap.find("cproc.date = date()", gi)] if gi >= 0 else ""
    ck("F6 THE GATE passes the LOGIN'S OWN flags (files.write, files.admin), not a constant; the refusal is audited with write=on|off admin=on|off (lower case) BEFORE the error is set; the text is "
       "12526 when the write flag is false and the same request WOULD be allowed with the write group (the call with @true says yes), 12529 when the administration flag is false and the request "
       "would be allowed with it, or both are false and it would be allowed with both, 12485 otherwise - tried in that order; all go to return.status.set",
       "if not(apifilesok(action, master.login.done, files.write, files.admin)) then" in gb
       and re.search(r"if files\.write then write\.word = 'on' else write\.word = 'off'\s*\n\s*if files\.admin then admin\.word = 'on' else admin\.word = 'off'\s*\n"
                     r"\s*void kernel\(K\$AUDIT, 'api refused request=' : action : ' route=sdfiles write=' : write\.word : ' admin=' : admin\.word : ' user=' : @logname\)", gb) is not None
       and re.search(r"begin case\s*\n\s*case not\(files\.write\) and apifilesok\(action, master\.login\.done, @true, files\.admin\)\s*\n\s*abort\.message = sysmsg\(12526, action\)[^\n]*\n"
                     r"\s*case not\(files\.admin\) and apifilesok\(action, master\.login\.done, files\.write, @true\)\s*\n\s*abort\.message = sysmsg\(12529, action\)[^\n]*\n"
                     r"\s*case not\(files\.write\) and not\(files\.admin\) and apifilesok\(action, master\.login\.done, @true, @true\)\s*\n\s*abort\.message = sysmsg\(12529, action\)\s*\n"
                     r"\s*case 1\s*\n\s*abort\.message = sysmsg\(12485, action\)", gb) is not None
       and ordered(gb, "kernel(K$AUDIT", "server.error = SV$ON.ERROR", "sysmsg(12526, action)", "sysmsg(12529, action)", "sysmsg(12485, action)", "st = status()", "goto return.status.set")
       and ap.count("apifilesok(") == 5, "")
    ck("F7 the login is audited with both flags: 'api login route=sdfiles write=' : on|off : ' admin=' : on|off : ' user=' - after the mark, before logged.in; no other audit line of the route lacks them",
       "void kernel(K$AUDIT, 'api login route=sdfiles write=' : write.word : ' admin=' : admin.word : ' user=' : scram.user)" in fin
       # 13 Nov 26 Windows port: the front audits the login from its own reading (api.files.*) before the handoff; the session is logged in by K$HANDOFF, not here
       and ordered(fin, "if api.files.login then", "if api.files.write then write.word = 'on' else write.word = 'off'", "if api.files.admin then admin.word = 'on' else admin.word = 'off'",
                   "'api login route=sdfiles write='", "scram.handoff = @true")
       and ap.count("route=sdfiles") == 3 and all("admin=" in ln_ for ln_ in ap.split("\n") if "route=sdfiles" in ln_), "")
    rv = ap.find("\nvb.readv:")
    rvb = ap[rv: ap.find("case flags = 0", rv)] if rv >= 0 else ""
    ck("F8 vb.readv: request 41 is in the allow table for a plain READV, so the LOCKING forms (flags 1, 2, 5, 6; the code refuses any nonzero flag) are refused HERE for a files-only login "
       "without the group - after check.file and the flags are read, BEFORE any read or lock, audited as request 41 with write=off, answered with 12526 naming 41",
       ordered(rvb, "gosub check.file", "flags = oconv(cmnd[3,2], 'ISL')", "if files.only and not(files.write) and flags # 0 then",
               "'api refused request=41 route=sdfiles write=off admin=' : admin.word : ' user=' : @logname", "server.error = SV$ON.ERROR", "abort.message = sysmsg(12526, 41)", "return", "id = cmnd[9,99]"), repr(rvb[-300:]))
    vo = ap.find("\nvb.open:")
    vob = ap[vo: ap.find("\nvb.close:", vo)] if vo >= 0 else ""
    ck("F9 THE DICTIONARY OPEN: vb.open takes a name that begins with the word dict in ANY case and one space (upcase(cmnd[1,5]) = 'DICT ') as OPEN 'DICT', trim(the rest), BEFORE the plain "
       "`open cmnd`, which stays for every other name; both arms keep the trusted-file refusal and the same ELSE; the SDCLIENT / SDNet test above them is untouched, so the dictionary "
       "is as gated as the file",
       ordered(vob, "if kernel(K$SDNET, -1)  or config(\"SDCLIENT\") # 0 then", "if upcase(cmnd[1,5]) = 'DICT ' then", "open 'DICT', trim(cmnd[6,9999]) to files(i)", "end else", "open cmnd to files(i)")
       and vob.count("FL$FLAGS.TRUSTED") == 2 and vob.count("else server.error = SV$ELSE") == 2 and "cmnd[1,5] = 'DICT '" not in vob, repr(vob[-400:]))

    # ---- F16. S.72: the three lock requests an SDNet client now sends reach the file the request NAMED, on every branch ------------------------------
    fl, fu, rk = (routine_body(ap, lab) for lab in ("vb.filelock", "vb.fileunlock", "vb.recordlocked"))
    ck("F16 S.72 (20 Oct 26; K8a of 19 Oct, whose BLOCKING branch had no row and a mutant that survived): vb.filelock reads the file number and the wait flag (two 16 bit numbers), checks the file, then locks "
       "files(fno) on BOTH branches - the waiting one (the flag set; the server blocks) and the no-wait one with `locked server.error = SV$LOCKED` - and never the scratch variable of the last open, files(i); "
       "vb.fileunlock unlocks files(fno); vb.recordlocked asks recordlocked(files(fno), id) and hands STATUS() back to the client with set.status (the lock owner's user number, which RECORDLOCKED() of a "
       "remote file gives the program). The runtime proof is sandbox-req29.py F10-F19 and F20-F49 against a real sd -Q; this is the order",
       ordered(fl, "fno = oconv(cmnd[1,2], 'ISL')", "wait = oconv(cmnd[3,2], 'ISL')", "gosub check.file", "if err then return", "if wait then", "filelock files(fno)", "end else",
               "filelock files(fno) locked server.error = SV$LOCKED", "return")
       and fl.count("filelock files(fno)") == 2 and "files(i)" not in fl and "files(1)" not in fl
       and ordered(fu, "fno = oconv(cmnd[1,2], 'ISL')", "gosub check.file", "if err then return", "fileunlock files(fno)", "return") and fu.count("fileunlock files(fno)") == 1 and "files(i)" not in fu
       and ordered(rk, "fno = oconv(cmnd[1,2], 'ISL')", "gosub check.file", "if err then return", "id = cmnd[3,99]", "recordlocked(files(fno), id)", "st = status()", "set.status st", "return")
       and re.search(r"st = status\(\)\s*\n\s*response = iconv\(i, 'ILL'\);\s*\n\s*set\.status st\b", rk) is not None
       and "files(i)" not in rk and "files(1)" not in rk,
       repr((fl[:200], fu[:160], rk[:200])))
    ck("F17 S.72b (20 Oct 26; it said the opposite on the morning of S.72): request 34 (recordlocked) stays in the allow table AND IS NOW IN the change set with 32 and 33 (a files-only login without "
       "sdfileswrite is refused the file lock, its release and the question who holds a lock - the answer is a user number of THIS server; a login with the group is served; the allow table itself is untouched, so "
       "the group can ask)", 34 in ok_nums and 34 in chg and 32 in chg and 33 in chg and 34 in ALLOWED and 34 in CHANGE,
       repr((34 in ok_nums, 34 in chg, 32 in chg, 33 in chg)))
    di = ap.find("on action + 1 gosub")
    dj = ap.find("\n\n", di) if di >= 0 else -1
    slots = [s for s in re.split(r"[\s,]+", ap[di + len("on action + 1 gosub"):dj]) if s] if 0 <= di < dj else []
    digits = sorted(set(re.findall(r"(?<![\w.$])\d+(?![\w.$])", strip_strings(gb))))
    ck("F18 S.72b: request 34 is refused by the SAME generic gate as 32 and 33 and by NO CODE OF ITS OWN (apisrvr is not changed for it): the gate block names no request number (the only numbers in it are the "
       "messages 12526, 12529 and 12485, and the 1 of the default `case 1`), asks apifilesok for `action` and nothing else, comes before the dispatch; vb.recordlocked has no test of the login in it (no files.only, no files.write, no sysmsg, no audit "
       "line - a second place that could say a different thing); and the dispatch still puts vb.filelock at 32, vb.fileunlock at 33 and vb.recordlocked at 34 (an entry lost before them would shift every "
       "request after it onto the wrong routine), with the table 73 entries long (actions 0 to 71, vb.writeuseqkey at 69, vb.fileadmin at 70, vb.fcontrol at 71 - S.73 item 3 - and the trailing vb.illegal.action)",
       digits == ["1", "12485", "12526", "12529"] and "action = 34" not in gb and "action # 34" not in gb and gb.count("apifilesok(") == 4 and ordered(ap, "if files.only then", "if not(apifilesok(action, master.login.done, files.write, files.admin)) then", "on action + 1 gosub")
       and not re.search(r"files\.only|files\.write|sysmsg|K\$AUDIT|server\.error", rk)
       and len(slots) == 73 and slots[32:35] == ["vb.filelock", "vb.fileunlock", "vb.recordlocked"] and slots[0] == "vb.illegal.action" and slots[1] == "vb.quit"
       and slots[69] == "vb.writeuseqkey" and slots[70] == "vb.fileadmin" and slots[71] == "vb.fcontrol" and slots[72] == "vb.illegal.action",
       repr((digits, slots[31:36], len(slots))))

    # ---- F10-F13. the words -------------------------------------------------------------------------------------------------------------
    sf = routine_body(mo, "set.files")
    ck("F10 MODIFY.ACCOUNT: FILES-WRITE-ON and FILES-WRITE-OFF are words (files.grp = 'sdfileswrite', files.want true / false, set.files, stop), in the syntax lines and in the list of words; "
       "FILES-ON / FILES-OFF set files.grp = 'sdfiles' (the helper takes the group from it)",
       # 13 Nov 26 Windows port: modify.account dispatches on `case upcase(action) = 'X'` in its main loop, with no RETURN after the gosub; the list of words goes on
       # with Windows's own (shared-read-on ...), so the files words are held as their run; ai-on / ai-off and sdsys-on / sdsys-off are other rows' (not carried here)
       all(re.search(r"case upcase\(action\) = '%s'\s*\n\s*files\.grp = '%s'\s*\n\s*files\.want = @%s\s*\n\s*gosub set\.files\s*\n" % (w, g_, b), mo)
           for w, g_, b in (("FILES-ON", "sdfiles", "true"), ("FILES-OFF", "sdfiles", "false"), ("FILES-WRITE-ON", "sdfileswrite", "true"), ("FILES-WRITE-OFF", "sdfileswrite", "false"),
                            ("FILES-ADMIN-ON", "sdfilesadmin", "true"), ("FILES-ADMIN-OFF", "sdfilesadmin", "false")))
       and "modify.account <account> files-on | files-off | files-write-on | files-write-off | files-admin-on | files-admin-off" in mo
       and "files-on, files-off, files-write-on, files-write-off, files-admin-on, files-admin-off," in mo
       and "FILES-ON,FILES-OFF,FILES-WRITE-ON,FILES-WRITE-OFF,FILES-ADMIN-ON,FILES-ADMIN-OFF," in mo and sf != "", "")
    cgf = routine_body(mo, "change.files.group")
    rfg = routine_body(mo, "read.files.groups")          # 21 Oct 26, S.73 item 3
    rrm = routine_body(mo, "report.removals")
    ck("F11 set.files: FILES-WRITE-ON is refused for a person who is not in sdfiles (12528, read three-valued) BEFORE the 'already had it' answer and before anything is run; "
       "(K4a, 19 Oct 26) for FILES-ON and FILES-OFF the write group is read too, three-valued (10081 when it cannot be read), BEFORE that answer, and FILES-OFF has nothing to do only for a "
       "person who is in NEITHER group - the orphan, in sdfileswrite and not in sdfiles, was told 'nothing changed' and kept the membership; the write group is taken out FIRST, before the group "
       "itself, so a failure of the second removal leaves read access and never write access without read; FILES-ON takes a stray write membership away BEFORE it adds sdfiles and stops "
       "with 10081 when it cannot; every group change is change.files.group, which reads the membership back; the line printed is 12527 for the write group (first, when it was taken "
       "away) and 12487 for the other, read back",
       # 21 Oct 26 (S.73 item 3): the three groups are read in ONE place, read.files.groups (three-valued, 10081 when it cannot be read), BEFORE the refusals and the 'already had it' answer;
       # sdfilesadmin is refused for a person who is not in both sdfiles and sdfileswrite (12531), sdfileswrite for one who is not in sdfiles (12528); the removals go TOP DOWN (admin, write, the group itself)
       ordered(sf, "gosub read.files.groups", "if files.stat # 0 then", "sysmsg(10081, acc.name, files.stat)", "if files.grp = 'sdfileswrite' and files.want then", "if not(has.files) then", "sysmsg(12528, acc.name)",
               "if files.grp = 'sdfilesadmin' and files.want then", "if not(has.files) or not(has.write) then", "sysmsg(12531, acc.name)",
               "nothing.to.do = not(has.files) and not(has.write) and not(has.admin)", "nothing.to.do = not(has.write) and not(has.admin)", "nothing.to.do = (has.target = files.want)",
               "if nothing.to.do then", "sysmsg(10080, acc.name)", "files.found = is_group(files.grp)", "gosub change.files.group")
       and re.search(r"if files\.grp = 'sdfileswrite' and files\.want then\s*\n\s*if not\(has\.files\) then\s*\n\s*@system\.return\.code = -ER\$FAILED\s*\n"
                     r"\s*crt sysmsg\(12528, acc\.name\)[^\n]*\n\s*return\s*\n\s*end\s*\n\s*end", sf) is not None
       and re.search(r"if files\.grp = 'sdfilesadmin' and files\.want then\s*\n\s*if not\(has\.files\) or not\(has\.write\) then\s*\n\s*@system\.return\.code = -ER\$FAILED\s*\n"
                     r"\s*crt sysmsg\(12531, acc\.name\)[^\n]*\n\s*return\s*\n\s*end\s*\n\s*end", sf) is not None
       # 13 Nov 26 Windows port: the three groups are read through one routine, read.one.group, because Windows cannot tell "no such group" from "could not read" (both
       # status 1): a lookup that failed asks whether the group is there, a group that is not there has nobody in it (and fails only when it is the one to be joined), and a
       # group that is there and cannot be read stops the command (files.stat, the first such status).  Linux reads each group in line, three-valued.
       and re.search(r"files\.stat = 0\s*\n\s*rg\.group = 'sdfiles'\s*\n\s*gosub read\.one\.group\s*\n\s*has\.files = rg\.is\s*\n"
                     r"\s*rg\.group = 'sdfileswrite'\s*\n\s*gosub read\.one\.group\s*\n\s*has\.write = rg\.is\s*\n"
                     r"\s*rg\.group = 'sdfilesadmin'\s*\n\s*gosub read\.one\.group\s*\n\s*has\.admin = rg\.is\s*\n", rfg) is not None
       and re.search(r"^read\.one\.group:\s*\n\s*rg\.is = is_grp_member\(files\.user, rg\.group\)\s*\n\s*rg\.stat = status\(\)\s*\n\s*if rg\.stat # 0 then\s*\n\s*rg\.is = @false\s*\n"
                     r"\s*rg\.found = is_group\(rg\.group\)\s*\n\s*rg\.istat = status\(\)\s*\n\s*if rg\.istat = 0 and not\(rg\.found\) then\s*\n\s*rg\.stat = 0\s*\n"
                     r"\s*if files\.want and rg\.group = files\.grp then rg\.stat = 1\s*\n\s*end\s*\n\s*end\s*\n\s*if rg\.stat # 0 and files\.stat = 0 then files\.stat = rg\.stat\s*\n\s*return\s*$", mo, re.M) is not None
       and ordered(rfg, "case files.grp = 'sdfilesadmin'", "has.target = has.admin", "case files.grp = 'sdfileswrite'", "has.target = has.write", "case 1", "has.target = has.files")
       and ordered(sf, "admin.removed = @false", "write.removed = @false", "if (files.grp = 'sdfiles' or files.grp = 'sdfileswrite') and has.admin then", "cg.group = 'sdfilesadmin'", "cg.want = @false",
                   "gosub change.files.group", "if files.stat # 0 then", "sysmsg(10081, acc.name, files.stat)", "return", "now.admin = cg.now", "admin.removed = @true",
                   "if files.grp = 'sdfiles' and has.write then", "cg.group = 'sdfileswrite'", "cg.want = @false", "gosub change.files.group",
                   "if files.stat # 0 then", "gosub report.removals", "sysmsg(10081, acc.name, files.stat)", "return", "now.write = cg.now", "write.removed = @true",
                   "if not(files.want) and not(has.target) then", "now.files = @false", "end else", "cg.group = files.grp", "cg.want = files.want",
                   "gosub change.files.group", "now.files = cg.now")
       # 13 Nov 26 Windows port: the change is !os_group ADDMEM / DELMEM (its status is the answer; read back only when it is 0), not sd-elevate through os.execute
       and sf.count("gosub change.files.group") == 3 and sf.count("os_group(") == 0 and sf.count("os.execute") == 0 and cgf.count("os_group(") == 2
       and ordered(cgf, "cg.now = @false", "if cg.want then", 'files.stat = os_group("ADDMEM", cg.group, files.user)', "end else", 'files.stat = os_group("DELMEM", cg.group, files.user)',
                   "if files.stat = 0 then", "cg.now = is_grp_member(files.user, cg.group)", "files.stat = status()", "if files.stat = 0 and cg.now # cg.want then files.stat = 2")
       and ordered(sf, "if admin.removed then gosub admin.removed.line", "sysmsg(12530, acc.name, if now.files then 'yes' else 'no')", "sysmsg(12527, acc.name, if now.files then 'yes' else 'no')",
                   "if write.removed then gosub write.removed.line", "sysmsg(12487, acc.name, if now.files then 'yes' else 'no')")
       # 19 Oct 26 (finish 2, verifier), 21 Oct 26 (S.73 item 3: one routine for every removal that happened): the step after a removal FAILED, the group above having gone: the audit lines for THOSE removals
       # (files-admin-off, files-write-off - not the action asked for) and their state lines come BEFORE the failure message, from the same routines the success path uses
       and ordered(sf, "now.files = cg.now", "gosub report.removals", "sysmsg(10081, acc.name, files.stat)", "@system.return.code = 0", "kernel(K$AUDIT, 'modify.account ' : downcase(action) : ' account=' : acc.name)")
       and re.search(r"if admin\.removed then\s*\n\s*void kernel\(K\$AUDIT, 'modify\.account files-admin-off account=' : acc\.name\)\s*\n\s*gosub admin\.removed\.line\s*\n\s*end\s*\n"
                     r"\s*if write\.removed then\s*\n\s*void kernel\(K\$AUDIT, 'modify\.account files-write-off account=' : acc\.name\)\s*\n\s*gosub write\.removed\.line\s*\n\s*end\s*\n\s*return\s*$", rrm.rstrip() + "\n") is not None
       and re.search(r"^write\.removed\.line:\s*\n\s*crt sysmsg\(12527, acc\.name, if now\.write then 'yes' else 'no'\)[^\n]*\n\s*return\s*$", mo, re.M) is not None
       and re.search(r"^admin\.removed\.line:\s*\n\s*crt sysmsg\(12530, acc\.name, if now\.admin then 'yes' else 'no'\)[^\n]*\n\s*return\s*$", mo, re.M) is not None, "")
    ck("F12 createacc.h defines CA$FILESWRITE as 39 (after CA$SHARED.WRITE 38, unique); CREATEA: FILES-WRITE-ON sets it to 1 (nothing else does) and the syntax line names it; "
       "CREATE.ACCOUNT: a request is exactly 1, it needs FILES-ON (12528, before anything is made), the group sdfileswrite is looked for before the Linux user is made (10024), a group or "
       "other account is refused as for FILES-ON, the join is sd-elevate addgroup <user> sdfileswrite AFTER the sdfiles join, and the state line 12527 is read off /etc/group",
       re.search(r"\$define\s+CA\$FILESWRITE\s+39\b", hdr) is not None and len(re.findall(r"\$define\s+\S+\s+39\b", hdr)) == 1
       and re.search(r"case upcase\(token\) = 'FILES-WRITE-ON'\s*\n\s*settings<CA\$FILESWRITE> = 1\s*\n", cr) is not None and len(re.findall(r"(?<!if )settings<CA\$FILESWRITE>\s*=", cr)) == 1
       and "{files-on} {files-write-on} {files-admin-on} {ai-on}" in cr      # 13 Nov 26 Windows port: {ai-on} with RELEASE_1.1 246 (Linux S.69 step 2); the words after it differ (the shared words between)
       and "files.write.want = (settings<CA$FILESWRITE> = 1)" in ca2
       and re.search(r"if files\.write\.want then\s*\n\s*if not\(files\.want\) then\s*\n\s*@system\.return\.code = -ER\$ARGS\s*\n\s*err = 12528:@vm:acc\.name[^\n]*\n\s*goto exit\.create\s*\n\s*end", ca2) is not None
       # 21 Oct 26 (S.73 item 3): the look-up of a group and its join are the two internal subroutines check.files.group and join.files.group, called once per group, sdfiles then sdfileswrite then sdfilesadmin;
       # the look-ups all come BEFORE the Linux user is made and the joins AFTER
       # 13 Nov 26 Windows port: the joins are !os_group ADDMEM in set.access (after create_user), typed out once per group, each stopping the verb with 10081 and its
       # status; Linux's join.files.group subroutine is the same steps.  Four look-ups (the fourth is sdaiusers, RELEASE_1.1 246; test-ai-units.py holds its rows) and three files joins
       and ordered(ca2, "files.grp.name = 'sdfiles'", "gosub check.files.group", "if files.write.want then", "err = 12528:@vm:acc.name", "files.grp.name = 'sdfileswrite'", "gosub check.files.group",
                   "if files.admin.want then", "err = 12531:@vm:acc.name", "files.grp.name = 'sdfilesadmin'", "gosub check.files.group",
                   "if not(create_user(acc.uname)) then", "if files.want then", 'stat = os_group("ADDMEM", "sdfiles", acc.uname)', "if files.write.want then", 'stat = os_group("ADDMEM", "sdfileswrite", acc.uname)',
                   "if files.admin.want then", 'stat = os_group("ADDMEM", "sdfilesadmin", acc.uname)')
       and ca2.count("gosub check.files.group") == 4 and all(ca2.count('os_group("ADDMEM", "%s", acc.uname)' % g_) == 1 for g_ in ("sdfiles", "sdfileswrite", "sdfilesadmin"))
       and all(re.search(r'if %s then\s*\n\s*stat = os_group\("ADDMEM", "%s", acc\.uname\)\s*\n\s*if stat # 0 then\s*\n\s*@system\.return\.code = -ER\$FAILED\s*\n'
                         r"\s*err = 10081:@vm:acc\.uname:@vm:stat ; return\s*\n\s*end\s*\n\s*end" % (re.escape(w_), g_), ca2) is not None
               for w_, g_ in (("files.want", "sdfiles"), ("files.write.want", "sdfileswrite"), ("files.admin.want", "sdfilesadmin")))
       and re.search(r"if files\.admin\.want then\s*\n\s*if not\(files\.want\) or not\(files\.write\.want\) then\s*\n\s*@system\.return\.code = -ER\$ARGS\s*\n\s*err = 12531:@vm:acc\.name[^\n]*\n\s*goto exit\.create\s*\n\s*end", ca2) is not None
       and re.search(r"^check\.files\.group:\s*\n\s*files\.bad = @false\s*\n\s*files\.found = is_group\(files\.grp\.name\)\s*\n\s*files\.stat = status\(\)\s*\n\s*if files\.stat # 0 then\s*\n"
                     r"\s*@system\.return\.code = -ER\$FAILED\s*\n\s*err = 10081:@vm:acc\.uname:@vm:files\.stat[^\n]*\n\s*files\.bad = @true\s*\n\s*end else\s*\n\s*if not\(files\.found\) then\s*\n"
                     r"\s*@system\.return\.code = -ER\$FAILED\s*\n\s*err = 10024:@vm:files\.grp\.name[^\n]*\n\s*files\.bad = @true\s*\n\s*end\s*\n\s*end\s*\n\s*return\s*$", ca2, re.M) is not None
       and re.search(r"\$define\s+CA\$FILESADMIN\s+40\b", hdr) is not None and len(re.findall(r"\$define\s+\S+\s+40\b", hdr)) == 1
       and re.search(r"case upcase\(token\) = 'FILES-ADMIN-ON'\s*\n\s*settings<CA\$FILESADMIN> = 1\s*\n", cr) is not None and len(re.findall(r"(?<!if )settings<CA\$FILESADMIN>\s*=", cr)) == 1
       # 13 Nov 26 Windows port: the state lines read the group into files.wnow / files.anow first (the same reading); ai.want joins the group / other refusal (RELEASE_1.1 246)
       and "files.admin.want = (settings<CA$FILESADMIN> = 1)" in ca2
       and re.search(r"files\.anow = is_grp_member\(acc\.uname, 'sdfilesadmin'\)\s*\n\s*crt sysmsg\(12530, acc\.name, if files\.anow then 'yes' else 'no'\)", ca2) is not None
       and ca2.count("if files.want or files.write.want or files.admin.want or ai.want then") == 2
       and re.search(r"files\.wnow = is_grp_member\(acc\.uname, 'sdfileswrite'\)\s*\n\s*crt sysmsg\(12527, acc\.name, if files\.wnow then 'yes' else 'no'\)", ca2) is not None, "")
    ck("F13 the manifest: route.files.write: 1|0 for a USER account from membership of sdfileswrite, right after route.files and before os.sh; RESTORE.ACCOUNT reads it (and clears it for each "
       "section), hands it on as CA$FILESWRITE only when route.files is 1 too, so a manifest without the key, or with the write group and no files route, restores as NOT in the group",
       # 13 Nov 26 Windows port: the membership is read first into fwrite / fadmin (0 unless the lookup answered yes, so a group an older install has not got is "not a member")
       ordered(ai, "fwrite = 0", "fadmin = 0", "m = is_grp_member(uname, 'sdfileswrite')", "if m and status() = 0 then fwrite = 1", "m = is_grp_member(uname, 'sdfilesadmin')", "if m and status() = 0 then fadmin = 1",
               "info<-1> = 'route.files: ' : files", "info<-1> = 'route.files.write: ' : fwrite", "info<-1> = 'route.files.admin: ' : fadmin", "'os.sh: '")
       and ai.count("fwrite = 1") == 1 and ai.count("fadmin = 1") == 1
       and re.search(r"= 'route\.files\.write'\s*; m\.route\.files\.write = kv", rs) is not None and "m.route.files = '' ; m.route.files.write = ''" in rs
       and "if m.route.files = '1' and m.route.files.write = '1' then settings<CA$FILESWRITE> = 1" in rs and rs.count("CA$FILESWRITE") == 1
       # 21 Oct 26 (S.73 item 3): route.files.admin, after route.files.write, handed on as CA$FILESADMIN only when route.files AND route.files.write are 1 too
       and re.search(r"= 'route\.files\.admin'\s*; m\.route\.files\.admin = kv", rs) is not None and "m.route.files.admin = ''" in rs
       and "if m.route.files = '1' and m.route.files.write = '1' and m.route.files.admin = '1' then settings<CA$FILESADMIN> = 1" in rs and rs.count("CA$FILESADMIN") == 1, "")

    # ---- F14-F16. the group: installer, deletesdcore, sd-elevate; the messages ------------------------------------------------------------------
    # 13 Nov 26 Windows port: the same three things, where Windows does them.  The groups are made by sync-route-groups.ps1, which sd.iss runs at every install
    # (Ensure-Group: New-LocalGroup only when Get-LocalGroup finds none, so an upgrade install makes it empty and adds nobody; only sdssh is seeded); they are removed by
    # sd.iss RemoveSdGroups with the other route groups, on an interactive uninstall only (the owner's rule of 2 Sep 26; Linux's keep-unless-DELETE question is an
    # installer of its own).  Linux's sd-elevate rows (the whitelist for addgroup / delgroup / groupadd) are out: Windows has no sudo helper; SDSYS changes a group
    # in its own session through !os_group, so there is no list of group names at a privilege boundary to hold.
    egf = srg[srg.find("function Ensure-Group"): srg.find("function Get-Members")] if "function Ensure-Group" in srg else ""
    rsg = iss[iss.find("procedure RemoveSdGroups;"): iss.find("\nend;", iss.find("procedure RemoveSdGroups;"))] if "procedure RemoveSdGroups;" in iss else ""
    ck("F14 the installer makes sdfileswrite and sdfilesadmin with the other route groups (sync-route-groups.ps1, run by sd.iss: Ensure-Group, New-LocalGroup only when Get-LocalGroup "
       "finds none, so an upgrade install creates them empty and adds nobody; nobody is added to either); the uninstaller removes them with the other route groups, after the "
       "silent-uninstall exit, once each",
       re.search(r"^\$FilesWriteGroup\s*=\s*'sdfileswrite'\s*$", srg, re.M) is not None and re.search(r"^\$FilesAdminGroup\s*=\s*'sdfilesadmin'\s*$", srg, re.M) is not None
       and re.search(r"^\s*Ensure-Group \$FilesWriteGroup \$FilesWriteComment\s*$", srg, re.M) is not None    # 13 Nov 26 (277): no $null =, the answer is $script:GroupCreated
       and re.search(r"^\s*Ensure-Group \$FilesAdminGroup \$FilesAdminComment\s*$", srg, re.M) is not None
       and ordered(egf, "$g = Get-LocalGroup -Name $name", "if ($null -ne $g) {", "return", "New-LocalGroup -Name $name")   # 277: a bare return
       and not re.search(r"Add-LocalGroupMember[^\n]*(?:\$FilesWriteGroup|\$FilesAdminGroup|\$FilesGroup|sdfiles)", srg)
       and "Script := ExpandConstant('{app}" + chr(92) + "sync-route-groups.ps1');" in iss and "RouteMsg := SyncRouteGroups;" in iss
       and ordered(rsg, "if UninstallSilent then", "Exit;", "Exec(Net, 'localgroup sdfiles /delete'", "Exec(Net, 'localgroup sdfileswrite /delete'", "Exec(Net, 'localgroup sdfilesadmin /delete'")
       and iss.count("localgroup sdfileswrite /delete") == 1 and iss.count("localgroup sdfilesadmin /delete") == 1 and "RemoveSdGroups;" in iss[iss.find("\nend;", iss.find("procedure RemoveSdGroups;")):], "")
    m21, m22, m23 = (raw["msg:%d" % n].strip("\n") for n in (12526, 12527, 12528))
    stray = []                                    # any other program of gpl.bp that writes one of the three numbers
    for fname in sorted(os.listdir(GPL)):
        if fname in ("apisrvr", "modifya", "create_account"):
            continue
        p = os.path.join(GPL, fname)
        if os.path.isfile(p):
            with open(p, encoding="utf-8", errors="replace") as f:
                if re.search(r"\b1252[678]\b", strip_bas(f.read())):
                    stray.append(fname)
    ck("F15 messages 12526 to 12528 exist, ONE line each, with the words they name in lower case (files-write-on, files-on); 12526 names the request (%1) and what the administrator can do, "
       "and is AT MOST 100 CHARACTERS with a request number in it (19 Oct 26, K1: the SDNet client shows an ON ERROR reply's text cut to 100 characters, gpl.bp/netfile clean.text, and the first text "
       "was 175 - the person at the client saw 'status 0' where the reason should have been); "
       "12527 is 'Account %1 has files-write %2' (lower case, the owner's rule: a keyword SD prints); and each is used where it should be and nowhere else: 12526 by apisrvr only, twice (the gate, ONE argument; vb.readv, request 41), "
       "12527 by MODIFY.ACCOUNT (twice since 19 Oct 26: the write words, and FILES-OFF / FILES-ON when the write group went too) and CREATE.ACCOUNT (once) with the account and yes or no, 12528 by MODIFY.ACCOUNT (sysmsg) and CREATE.ACCOUNT (err =) once each with the account",
       "\n" not in m21 and "\n" not in m22 and "\n" not in m23 and "%1" in m21 and "files-write-on" in m21 and m22 == "Account %1 has files-write %2" and "files-on" in m23 and "%1" in m23 and "FILES" not in m21 + m22 + m23
       and len(m21.replace("%1", "41")) <= 100 and len(m21.replace("%1", "41")) > 40
       and len(re.findall(r"sysmsg\(12526, (?:action|41)\)", ap)) == 2 and ap.count("12526") == 2 and mo.count("sysmsg(12527, acc.name, if now.files then 'yes' else 'no')") == 1
       and ca2.count("sysmsg(12527, acc.name, if files.wnow then 'yes' else 'no')") == 1 and mo.count("sysmsg(12528, acc.name)") == 1
       and ca2.count("err = 12528:@vm:acc.name") == 1 and mo.count("12527") == 2 and mo.count("sysmsg(12527, acc.name, if now.write then 'yes' else 'no')") == 1 and ca2.count("12527") == 1 and mo.count("12528") == 1 and ca2.count("12528") == 1
       and not any(re.search(r"\b1252[678]\b", c[n_]) for n_ in ("createa", "acc_os_info", "restorea", "apifilesok")) and not stray,
       repr((m21, m22, m23, stray)))
    # ---- F20. the administration flag of apisrvr, the same three things F3 to F5 hold for the write flag (21 Oct 26, S.73 item 3) -------------------------------------------------------
    ck("F20 apisrvr keeps the ADMINISTRATION flag as the write flag is kept: in the COMMON block beside files.only (a plain variable is set afresh by a runtime abort), started false ONCE in the first-time block; "
       "the session reads sdfilesadmin ONCE, by its own logname, inside the sdfiles route right after the write group (a lookup that cannot answer is no administration), so a member of sdapi never "
       "reads it; files.admin is set there, in the one place files.only is made true, is never cleared, is assigned in exactly two places, and no other program mentions it; the front reads the "
       "group once, by scram.user, right after the write group, for the audit line only (13 Nov 26 Windows port: see F4)",
       re.search(r"^files\.admin,", cm, re.M) is not None and len(re.findall(r"(?<![\w.])files\.admin = @false", ap)) == 1
       and ordered(ap, "if not(kernel(K$CPROC.LEVEL,0)) then", "files.only = @false", "files.write = @false", "files.admin = @false", 'openpath "voc" to voc else')
       and ap.count("is_grp_member(logname, 'sdfilesadmin')") == 1 and ap.count("is_grp_member(scram.user, 'sdfilesadmin')") == 1
       and ordered(sess, "if not(api.in.sdapi) then", "files.only = @true", "files.write = (api.write.in and api.write.stat = 0)", "api.admin.in = is_grp_member(logname, 'sdfilesadmin')")
       and re.search(r"api\.admin\.in = is_grp_member\(logname, 'sdfilesadmin'\)\s*\n\s*api\.admin\.stat = status\(\)\s*\n\s*files\.admin = \(api\.admin\.in and api\.admin\.stat = 0\)\s*\n", sess) is not None
       and ordered(fin, "api.files.login = @false", "api.files.write = @false", "api.files.admin = @false", "api.in.sdapi = is_grp_member(scram.user, 'sdapi')", "if not(api.in.sdapi) then",
                   "api.files.login = @true", "api.files.write = is_grp_member(scram.user, 'sdfileswrite')", "api.files.admin = is_grp_member(scram.user, 'sdfilesadmin')")
       and re.search(r"api\.files\.admin = is_grp_member\(scram\.user, 'sdfilesadmin'\)\s*\n\s*api\.admin\.stat = status\(\)\s*\n\s*if api\.admin\.stat # 0 then api\.files\.admin = @false\s*\n", fin) is not None
       and len(re.findall(r"(?<![\w.])files\.admin\s*=(?!=)", ap)) == 2
       and not any(re.search(r"(?<![\w.])files\.admin(?![\w.])", t) for n, t in c.items() if n not in ("apisrvr",) and n in BP), "")
    m24, m25, m26 = (raw["msg:%d" % n].strip("\n") for n in (12529, 12530, 12531))
    stray2 = []                                   # any other program of gpl.bp that writes one of the S.73 numbers (the client side, later, is the one place that may)
    for fname in sorted(os.listdir(GPL)):
        if fname in ("apisrvr", "modifya", "create_account"):
            continue
        p = os.path.join(GPL, fname)
        if os.path.isfile(p):
            with open(p, encoding="utf-8", errors="replace") as f:
                if re.search(r"\b(?:12529|1253[01])\b", strip_bas(f.read())):
                    stray2.append(fname)
    ck("F19 S.73 item 3: messages 12529 to 12531 exist, ONE line each, with the words they name in lower case (files-admin-on, files-write-on, files-admin); 12529 names the request (%1) and what the administrator can do "
       "and is AT MOST 100 CHARACTERS with a two digit request number in it (the SDNet client shows an ON ERROR reply's text cut to 100); 12530 is 'Account %1 has files-admin %2'; 12531 names files-write-on; and "
       "each is used where it should be and nowhere else: 12529 by apisrvr only, in two arms of the gate's case, 12530 by MODIFY.ACCOUNT (the state line, and the line of a removal) and CREATE.ACCOUNT (once), "
       "12531 by MODIFY.ACCOUNT (sysmsg) and CREATE.ACCOUNT (err =) once each",
       all("\n" not in x for x in (m24, m25, m26)) and "%1" in m24 and "files-admin-on" in m24 and m25 == "Account %1 has files-admin %2" and "files-write-on" in m26 and "%1" in m26
       and "FILES" not in m24 + m25 + m26 and 40 < len(m24.replace("%1", "70")) <= 100
       and ap.count("sysmsg(12529, action)") == 2 and ap.count("12529") == 2
       and mo.count("sysmsg(12530, acc.name, if now.files then 'yes' else 'no')") == 1 and mo.count("sysmsg(12530, acc.name, if now.admin then 'yes' else 'no')") == 1 and mo.count("12530") == 2
       and ca2.count("sysmsg(12530, acc.name, if files.anow then 'yes' else 'no')") == 1 and ca2.count("12530") == 1
       and mo.count("sysmsg(12531, acc.name)") == 1 and mo.count("12531") == 1 and ca2.count("err = 12531:@vm:acc.name") == 1 and ca2.count("12531") == 1
       and not any(re.search(r"\b(?:12529|1253[01])\b", c[n_]) for n_ in ("createa", "acc_os_info", "restorea", "apifilesok")) and not stray2,
       repr((m24, m25, m26, stray2)))
    return res


def mutants(raw):
    """(name, file, old, new): one deliberate fault at a time, applied to the RAW source (old must occur exactly once)."""
    M = []

    def m(name, f, old, new):
        M.append((name, f, old, new))
    # apifilesok
    m("a number of the change set is dropped (30)", "apifilesok", "files.chg := '30,'   ;* lock record\n", "")
    m("a plain read joins the change set (6)", "apifilesok", "files.chg := '7,'    ;* readl\n", "files.chg := '6,'    ;* read\nfiles.chg := '7,'    ;* readl\n")
    m("clearfile is no longer in the change set (31)", "apifilesok", "files.chg := '31,'   ;* clearfile\n", "")
    m("filelock is no longer in the change set (32)", "apifilesok", "files.chg := '32,'   ;* filelock\n", "")
    m("a number joins the change set that the table does not allow (20, call)", "apifilesok", "files.chg := '7,'    ;* readl\n", "files.chg := '20,'   ;* call\nfiles.chg := '7,'    ;* readl\n")
    # S.72 / K8a: the lock requests reach the file the request named (the first of these is the mutant the 19 Oct audit said survived)
    m("vb.filelock: the WAITING branch locks the file opened last (the stale files(i))", "apisrvr",
      "filelock files(fno)   ;* 19 Oct 26 (K8a): was files(i), the stale loop variable of the last open, as vb.clearfile's was", "filelock files(i)   ;* 19 Oct 26 (K8a): was files(i), the stale loop variable of the last open, as vb.clearfile's was")
    m("vb.filelock: the NO-WAIT branch locks the file opened last", "apisrvr", "filelock files(fno) locked server.error = SV$LOCKED", "filelock files(i) locked server.error = SV$LOCKED")
    m("vb.filelock: the no-wait branch has no LOCKED clause (a busy file would block the server)", "apisrvr", "filelock files(fno) locked server.error = SV$LOCKED", "filelock files(fno)")
    m("vb.filelock: the wait flag is read from the file number's bytes", "apisrvr", "wait = oconv(cmnd[3,2], 'ISL')", "wait = oconv(cmnd[1,2], 'ISL')")
    m("vb.fileunlock: unlocks the file opened last", "apisrvr", "fileunlock files(fno)   ;* 19 Oct 26 (K8a): was files(i)", "fileunlock files(i)   ;* 19 Oct 26 (K8a): was files(i)")
    m("vb.recordlocked: asks about the first file", "apisrvr", "i = recordlocked(files(fno), id)", "i = recordlocked(files(1), id)")
    m("vb.recordlocked: does not hand STATUS() back (the owner's number)", "apisrvr", "response = iconv(i, 'ILL');", "response = iconv(i, 'ILL'); st = 0")
    # S.72b (20 Oct 26): 34 is IN the change set now, so the old mutant `recordlocked (34) joins the change set` is the baseline reality and is gone; these are the faults that undo it
    def line_out(pattern):
        """The first line of the source that matches PATTERN is taken out (the mutant applies to apifilesok's own table lines, whatever the comment after the number says)."""
        def f(t):
            return re.sub(r"^[^\n]*" + pattern + r"[^\n]*\n", "", t, count=1, flags=re.M)
        return f
    m("recordlocked (34) leaves the change set", "apifilesok", line_out(r"files\.chg := '34,'"), None)
    m("recordlocked (34) leaves the allow table too (a login with the group could not ask)", "apifilesok", line_out(r"files\.ok := '34,'"), None)
    m("recordlocked (34) is in the change set twice", "apifilesok", lambda t: re.sub(r"(^files\.chg := '34,'[^\n]*\n)", r"\1\1", t, count=1, flags=re.M), None)
    m("the gate of apisrvr lets request 34 through for a files-only login", "apisrvr", "if not(apifilesok(action, master.login.done, files.write, files.admin)) then",
      "if action # 34 and not(apifilesok(action, master.login.done, files.write, files.admin)) then")
    m("vb.recordlocked refuses a login without the group on its own (a second place)", "apisrvr", "i = recordlocked(files(fno), id)",
      "if files.only and not(files.write) then i = 0 else i = recordlocked(files(fno), id)")
    m("the dispatch loses an entry before request 34 (every request after it shifts)", "apisrvr", "   vb.fileunlock,     ;*  33   Release file lock\n", "")
    m("fileunlock (33) leaves the change set", "apifilesok", "files.chg := '33,'   ;* fileunlock\n", "")
    m("the write flag is tested as a boolean, not as exactly 1", "apifilesok", "if writeok # 1 then\n   if index(files.chg", "if not(writeok) then\n   if index(files.chg")
    m("the write flag is ignored", "apifilesok", "if writeok # 1 then\n   if index(files.chg", "if 0 then\n   if index(files.chg")
    m("the write flag is tested as a boolean for the administration set too", "apifilesok", "   if writeok # 1 then return 0\n   if adminok", "   if not(writeok) then return 0\n   if adminok")
    m("the change set is tested BEFORE the table (a number outside the table is answered by the wrong test)", "apifilesok",
      "if not(index(files.ok, ',' : action : ',', 1)) then return 0\n", "")
    m("the change set is refused without the commas (7 matches 17)", "apifilesok", "if index(files.chg, ',' : action : ',', 1) then return 0", "if index(files.chg, action, 1) then return 0")
    m("the default is 0", "apifilesok", "return 1\n\nend\n\n* END-CODE", "return 0\n\nend\n\n* END-CODE")
    m("the parameter is dropped", "apifilesok", "function apifilesok(action, entered, writeok, adminok)", "function apifilesok(action, entered, writeok)")
    # S.73 item 3 (21 Oct 26): the administration set
    m("an administration number drops out of the set (70)", "apifilesok", "files.adm := '70,'   ;* fileadmin\n", "")
    m("a number of the change set joins the administration set (16)", "apifilesok", "files.adm := '68,'   ;* writeseqkey\n", "files.adm := '16,'   ;* write\nfiles.adm := '68,'   ;* writeseqkey\n")
    m("the administration flag is ignored", "apifilesok", "   if adminok # 1 then return 0\n", "")
    m("the administration flag is tested as a boolean, not as exactly 1", "apifilesok", "if adminok # 1 then return 0", "if not(adminok) then return 0")
    m("the write flag is not asked for the administration set (the administration group alone would do)", "apifilesok", "   if writeok # 1 then return 0\n   if adminok # 1 then return 0", "   if adminok # 1 then return 0")
    m("the administration set is tested without the commas (7 would match 70)", "apifilesok", "if index(files.adm, ',' : action : ',', 1) then", "if index(files.adm, action, 1) then")
    m("request 70 leaves the allow table (the administration group could not ask)", "apifilesok", line_out(r"files\.ok := '70,'"), None)
    m("the change set is no longer tested at all (the administration set was added beside it, not instead of it)", "apifilesok",
      "if writeok # 1 then\n   if index(files.chg, ',' : action : ',', 1) then return 0\nend\n", "")
    # apisrvr
    m("the flag is not in the common block", "apisrvr", "files.write,        ;* 18 Oct 26", "filesx.write,        ;* 18 Oct 26")
    m("the flag is not started false", "apisrvr", "   files.write = @false       ;*", "   files.writex = @false       ;*")
    # 13 Nov 26 Windows port: the mark is the session's own (F4, F5); the front's read is for the audit line
    m("the login is given the write group unconditionally", "apisrvr", "files.write = (api.write.in and api.write.stat = 0)", "files.write = @true")
    m("the session reads the wrong group for the write flag", "apisrvr", "api.write.in = is_grp_member(logname, 'sdfileswrite')", "api.write.in = is_grp_member(logname, 'sdfiles')")
    m("a write group the session cannot read gives write (fail open)", "apisrvr", "files.write = (api.write.in and api.write.stat = 0)", "files.write = (api.write.in or api.write.stat # 0)")
    m("the session's write flag is set before files.only (outside the sdfiles route)", "apisrvr", "      if not(api.in.sdapi) then\n         api.in.sdfiles = is_grp_member(logname, 'sdfiles')",
      "      api.write.in = is_grp_member(logname, 'sdfileswrite')\n      files.write = api.write.in\n      if not(api.in.sdapi) then\n         api.in.sdfiles = is_grp_member(logname, 'sdfiles')")
    m("the front sets the mark itself (it never reaches the session)", "apisrvr", "                  api.files.login = @true\n", "                  api.files.login = @true\n                  files.write = @true\n")
    m("the wrong group is read for the write flag", "apisrvr", "api.files.write = is_grp_member(scram.user, 'sdfileswrite')", "api.files.write = is_grp_member(scram.user, 'sdfiles')")
    m("the write group is not read three-valued", "apisrvr", "if api.write.stat # 0 then", "if 0 then")
    m("the gate passes true instead of the login's flag", "apisrvr", "if not(apifilesok(action, master.login.done, files.write, files.admin)) then", "if not(apifilesok(action, master.login.done, @true, files.admin)) then")
    m("the gate passes false instead of the login's flag", "apisrvr", "if not(apifilesok(action, master.login.done, files.write, files.admin)) then", "if not(apifilesok(action, master.login.done, @false, files.admin)) then")
    m("the refusal has no write word in the audit line", "apisrvr", "' route=sdfiles write=' : write.word : ' admin=' : admin.word : ' user=' : @logname)  ;* @logname, not logname", "' route=sdfiles admin=' : admin.word : ' user=' : @logname)  ;* @logname, not logname")
    m("the refusal always says 12485", "apisrvr", "abort.message = sysmsg(12526, action)", "abort.message = sysmsg(12485, action)")
    m("the login line has no write word", "apisrvr", "'api login route=sdfiles write=' : write.word : ' admin=' : admin.word : ' user='", "'api login route=sdfiles admin=' : admin.word : ' user='")
    # S.73 item 3 (21 Oct 26): the administration flag
    m("the gate passes true for the administration flag", "apisrvr", "if not(apifilesok(action, master.login.done, files.write, files.admin)) then", "if not(apifilesok(action, master.login.done, files.write, @true)) then")
    m("the gate passes false for the administration flag", "apisrvr", "if not(apifilesok(action, master.login.done, files.write, files.admin)) then", "if not(apifilesok(action, master.login.done, files.write, @false)) then")
    m("the administration flag is not in the common block", "apisrvr", "files.admin,        ;* 21 Oct 26 S.73", "filesx.admin,        ;* 21 Oct 26 S.73")
    m("the administration flag is not started false", "apisrvr", "   files.admin = @false       ;*", "   files.adminx = @false       ;*")
    m("the login is given the administration group unconditionally", "apisrvr", "files.admin = (api.admin.in and api.admin.stat = 0)", "files.admin = @true")
    m("the session reads the wrong group for the administration flag (13 Nov 26 Windows port)", "apisrvr", "api.admin.in = is_grp_member(logname, 'sdfilesadmin')", "api.admin.in = is_grp_member(logname, 'sdfileswrite')")
    m("an administration group the session cannot read gives administration (fail open; 13 Nov 26 Windows port)", "apisrvr", "files.admin = (api.admin.in and api.admin.stat = 0)", "files.admin = api.admin.in")
    m("the wrong group is read for the administration flag", "apisrvr", "api.files.admin = is_grp_member(scram.user, 'sdfilesadmin')", "api.files.admin = is_grp_member(scram.user, 'sdfileswrite')")
    m("the administration group is not read three-valued", "apisrvr", "if api.admin.stat # 0 then", "if 0 then")
    m("the refusal has no administration word in the audit line", "apisrvr", " write=' : write.word : ' admin=' : admin.word : ' user=' : @logname)  ;* @logname, not logname", " write=' : write.word : ' user=' : @logname)  ;* @logname, not logname")
    m("the login line has no administration word", "apisrvr", " write=' : write.word : ' admin=' : admin.word : ' user=' : scram.user)", " write=' : write.word : ' user=' : scram.user)")
    m("the refusal for the administration group says 12526", "apisrvr", "abort.message = sysmsg(12529, action) ;* This login cannot administer", "abort.message = sysmsg(12526, action) ;* This login cannot administer")
    m("the dispatch loses the entry of request 70 (71 shifts onto 70)", "apisrvr", line_out(r"vb\.fileadmin,"), None)
    m("the dispatch loses the entry of request 71", "apisrvr", line_out(r"vb\.fcontrol,"), None)
    m("the readv lock test is gone", "apisrvr", "if files.only and not(files.write) and flags # 0 then", "if 0 then")
    m("the readv test refuses only flag 1", "apisrvr", "if files.only and not(files.write) and flags # 0 then", "if files.only and not(files.write) and flags = 1 then")
    m("the readv test refuses a plain READV too", "apisrvr", "if files.only and not(files.write) and flags # 0 then", "if files.only and not(files.write) then")
    m("the readv test is made for every session, sdapi included", "apisrvr", "if files.only and not(files.write) and flags # 0 then", "if not(files.write) and flags # 0 then")
    m("the dictionary test is case sensitive", "apisrvr", "if upcase(cmnd[1,5]) = 'DICT ' then", "if cmnd[1,5] = 'DICT ' then")
    m("the dictionary open uses the whole name", "apisrvr", "open 'DICT', trim(cmnd[6,9999]) to files(i)", "open 'DICT', cmnd to files(i)")
    m("the dictionary open is not a dictionary open", "apisrvr", "open 'DICT', trim(cmnd[6,9999]) to files(i)", "open trim(cmnd[6,9999]) to files(i)")
    # modifya
    m("FILES-WRITE-ON sets the wrong group", "modifya", "            files.grp = 'sdfileswrite'\n            files.want = @true", "            files.grp = 'sdfiles'\n            files.want = @true")      # 13 Nov 26 Windows port: 12-space indent
    m("FILES-WRITE-OFF is not a word", "modifya", "case upcase(action) = 'FILES-WRITE-OFF'", "case upcase(action) = 'FILES-WRITE-OFFX'")
    m("the person need not be in sdfiles", "modifya", "      if not(has.files) then\n         @system.return.code = -ER$FAILED\n         crt sysmsg(12528", "      if 0 then\n         @system.return.code = -ER$FAILED\n         crt sysmsg(12528")
    m("files-off leaves the write group", "modifya", "if files.grp = 'sdfiles' and has.write then\n      cg.group = 'sdfileswrite'", "if 0 then\n      cg.group = 'sdfileswrite'")
    m("files-on leaves a stray write membership (K4a: it became write access at the next files-on)", "modifya", "if files.grp = 'sdfiles' and has.write then\n      cg.group = 'sdfileswrite'",
      "if files.grp = 'sdfiles' and has.write and not(files.want) then\n      cg.group = 'sdfileswrite'")
    m("the orphan (write group, not sdfiles) is told nothing changed", "modifya", "nothing.to.do = not(has.files) and not(has.write)", "nothing.to.do = not(has.files)")
    # 13 Nov 26 Windows port: the groups are read through read.one.group (F11), so these two aim there
    m("the write group is not read for the pair", "modifya", "   rg.group = 'sdfileswrite'\n   gosub read.one.group\n   has.write = rg.is\n", "   has.write = @false\n")
    m("the groups are not read three-valued", "modifya", "   rg.stat = status()\n", "   rg.stat = 0\n")
    m("a failed removal of the write group does not stop the command", "modifya",
      "      gosub change.files.group\n      if files.stat # 0 then\n         @system.return.code = -ER$FAILED\n         gosub report.removals  ;* sdfilesadmin may have gone before this step\n         crt sysmsg(10081, acc.name, files.stat)\n         return\n      end\n      now.write = cg.now",
      "      gosub change.files.group\n      now.write = cg.now")
    m("sdfiles is taken from a person who is not in it", "modifya", "if not(files.want) and not(has.target) then", "if 0 then")
    # S.73 item 3 (21 Oct 26): the administration words
    m("FILES-ADMIN-ON sets the wrong group", "modifya", "            files.grp = 'sdfilesadmin'\n            files.want = @true", "            files.grp = 'sdfileswrite'\n            files.want = @true")
    m("FILES-ADMIN-OFF is not a word", "modifya", "case upcase(action) = 'FILES-ADMIN-OFF'", "case upcase(action) = 'FILES-ADMIN-OFFX'")
    m("the person need not be in sdfileswrite to be given administration", "modifya", "      if not(has.files) or not(has.write) then", "      if not(has.files) then")
    m("files-write-off leaves the administration group (it would be left without the write it needs)", "modifya", "if (files.grp = 'sdfiles' or files.grp = 'sdfileswrite') and has.admin then", "if files.grp = 'sdfiles' and has.admin then")
    m("files-on and files-write-on leave a stray administration group", "modifya", "if (files.grp = 'sdfiles' or files.grp = 'sdfileswrite') and has.admin then", "if 0 then")
    m("a group that cannot be read does not stop the command (13 Nov 26 Windows port: read.one.group)", "modifya", "   if rg.stat # 0 and files.stat = 0 then files.stat = rg.stat\n", "")
    m("a group that is not there counts as a failure to read (13 Nov 26 Windows port: an older install has no sdfilesadmin)", "modifya", "         rg.stat = 0\n         if files.want", "         if files.want")
    m("the line for the administration group that went is not printed", "modifya", "if admin.removed then gosub admin.removed.line", "if 0 then gosub admin.removed.line")
    m("a failure after the administration group went writes no audit line for the removal", "modifya", "      void kernel(K$AUDIT, 'modify.account files-admin-off account=' : acc.name)\n", "")
    m("files-off has nothing to do for a person who is in the administration group only", "modifya", "nothing.to.do = not(has.files) and not(has.write) and not(has.admin)", "nothing.to.do = not(has.files) and not(has.write)")
    m("files-write-off has nothing to do for a person who is in the administration group only", "modifya", "nothing.to.do = not(has.write) and not(has.admin)", "nothing.to.do = not(has.write)")
    m("the administration state line is the write group's message", "modifya", "crt sysmsg(12530, acc.name, if now.files then 'yes' else 'no')", "crt sysmsg(12527, acc.name, if now.files then 'yes' else 'no')")
    m("a group change is not read back", "modifya", "cg.now = is_grp_member(files.user, cg.group)", "cg.now = cg.want")
    m("a read back that differs is a success", "modifya", "if files.stat = 0 and cg.now # cg.want then files.stat = 2", "null")
    m("set.files changes a group itself again (a second place that changes a group)", "modifya", "   write.removed = @false\n", "   write.removed = @false\n   files.stat = os_group(\"DELMEM\", \"sdfileswrite\", files.user)\n")
    m("the line for the write group that went is not printed", "modifya", "if write.removed then gosub write.removed.line", "if 0 then gosub write.removed.line")
    # 19 Oct 26, finish 2 (verifier): the step after the write removal fails - the failure path must say the write group went, in the audit trail and on the screen, before the failure message
    m("a failure after the write group went writes no audit line for the removal", "modifya", "      void kernel(K$AUDIT, 'modify.account files-write-off account=' : acc.name)\n", "")
    m("a failure after the write group went does not print the write group's line", "modifya", "      gosub write.removed.line\n   end\n   return\n", "   end\n   return\n")
    m("a failure after the write group went audits the action asked for", "modifya", "'modify.account files-write-off account=' : acc.name)", "'modify.account ' : downcase(action) : ' account=' : acc.name)")

    def write_group_last(t):
        """The block that takes the person out of sdfileswrite is moved to AFTER the group change: the order of the 18 Oct build.  (21 Oct 26: the blocks are now the administration removal, the
        write removal and the group change; the write removal and what follows it up to the failure block of the group change are swapped round the group change.)"""
        i = t.index("   if files.grp = 'sdfiles' and has.write then\n")
        j = t.index("\n* The group itself")
        k = t.index("   if files.stat # 0 then\n      @system.return.code = -ER$FAILED\n      gosub report.removals\n", j)      # the failure block of the group change (13 Nov 26 Windows port: the "A group above HAS gone" comment sits on the earlier failure block here)
        return t[:i] + t[j + 1:k] + t[i:j + 1] + t[k:]
    m("the write group is taken out AFTER sdfiles (the order that could leave the orphan)", "modifya", write_group_last, None)
    m("the write group's line is the other message", "modifya", "crt sysmsg(12527, acc.name, if now.files then 'yes' else 'no')", "crt sysmsg(12487, acc.name, if now.files then 'yes' else 'no')")
    # createa / create_account / restorea / acc_os_info
    m("FILES-WRITE-ON sets nothing", "createa", "'FILES-WRITE-ON'\n            settings<CA$FILESWRITE> = 1", "'FILES-WRITE-ON'\n            settings<CA$FILES> = 1")   # the parser's line: 19 Oct 26 the audit builder reads the same setting once more
    m("the write group is joined as sdfiles", "create_account", 'stat = os_group("ADDMEM", "sdfileswrite", acc.uname)', 'stat = os_group("ADDMEM", "sdfiles", acc.uname)')      # 13 Nov 26 Windows port: the join is os_group
    m("a failed join of the write group does not stop the verb (13 Nov 26 Windows port)", "create_account",
      '      stat = os_group("ADDMEM", "sdfileswrite", acc.uname)\n      if stat # 0 then', '      stat = os_group("ADDMEM", "sdfileswrite", acc.uname)\n      if 0 then')
    m("the write group needs no files-on", "create_account", "       if not(files.want) then\n         @system.return.code = -ER$ARGS\n         err = 12528",
      "       if 0 then\n         @system.return.code = -ER$ARGS\n         err = 12528")
    m("a group account is no longer refused the write group", "create_account", "     if files.want or files.write.want or files.admin.want or ai.want then      ;* 13 Nov 26 (Linux S.69 step 2): and no AI gate",
      "     if files.want or files.admin.want or ai.want then      ;* 13 Nov 26 (Linux S.69 step 2): and no AI gate")
    m("the manifest has no write key", "acc_os_info", "   info<-1> = 'route.files.write: ' : fwrite\n", "")      # 13 Nov 26 Windows port: the key is built from fwrite (F13)
    m("the manifest's write key is read off the wrong group (13 Nov 26 Windows port)", "acc_os_info", "m = is_grp_member(uname, 'sdfileswrite')", "m = is_grp_member(uname, 'sdfiles')")
    m("a write group that cannot be read is a member in the manifest (13 Nov 26 Windows port)", "acc_os_info", "if m and status() = 0 then fwrite = 1", "if m then fwrite = 1")
    m("the restore gives the write group without the files route", "restorea", "if m.route.files = '1' and m.route.files.write = '1' then settings<CA$FILESWRITE> = 1", "if m.route.files.write = '1' then settings<CA$FILESWRITE> = 1")
    # S.73 item 3 (21 Oct 26): the administration group at creation, in the manifest and in the restore
    m("FILES-ADMIN-ON sets nothing", "createa", "'FILES-ADMIN-ON'\n            settings<CA$FILESADMIN> = 1", "'FILES-ADMIN-ON'\n            settings<CA$FILES> = 1")
    m("the administration group needs no files-write-on", "create_account", "       if not(files.want) or not(files.write.want) then", "       if not(files.want) then")
    m("the administration group is joined as sdfiles", "create_account", 'stat = os_group("ADDMEM", "sdfilesadmin", acc.uname)', 'stat = os_group("ADDMEM", "sdfiles", acc.uname)')
    m("a group account is given the administration group (the 10087 refusal forgets it)", "create_account", "     if files.want or files.write.want or files.admin.want or ai.want then      ;* 13 Nov 26 (Linux S.69 step 2): and no AI gate",
      "     if files.want or files.write.want or ai.want then      ;* 13 Nov 26 (Linux S.69 step 2): and no AI gate")
    m("the manifest has no administration key", "acc_os_info", "   info<-1> = 'route.files.admin: ' : fadmin\n", "")
    m("the restore gives the administration group without the write route", "restorea", "if m.route.files = '1' and m.route.files.write = '1' and m.route.files.admin = '1' then settings<CA$FILESADMIN> = 1",
      "if m.route.files = '1' and m.route.files.admin = '1' then settings<CA$FILESADMIN> = 1")
    # installers
    # 13 Nov 26 Windows port: Linux's installsdcore.sh / deletesdcore.sh mutants, aimed at sync-route-groups.ps1 and sd.iss; the four sd-elevate mutants are out with its rows (F14)
    m("the installer does not make the group", "sync-route-groups.ps1", "    Ensure-Group $FilesWriteGroup $FilesWriteComment\n", "")
    m("the installer does not make the administration group", "sync-route-groups.ps1", "    Ensure-Group $FilesAdminGroup $FilesAdminComment\n", "")
    m("the installer makes the group under another name", "sync-route-groups.ps1", "$FilesWriteGroup = 'sdfileswrite'", "$FilesWriteGroup = 'sdfileswr'")
    m("Ensure-Group makes a group that is already there (an upgrade would fail or reset it)", "sync-route-groups.ps1", "    if ($null -ne $g) {\n", "    if ($false) {\n")
    m("the installer seeds the write group", "sync-route-groups.ps1", "    Ensure-Group $FilesAdminGroup $FilesAdminComment\n",
      "    Ensure-Group $FilesAdminGroup $FilesAdminComment\n    Add-LocalGroupMember -Group $FilesWriteGroup -Member $env:USERNAME\n")
    m("the uninstaller does not remove the group", "sd.iss", "  Exec(Net, 'localgroup sdfileswrite /delete', '', SW_HIDE, ewWaitUntilTerminated, Code);\n", "")
    m("the uninstaller does not remove the administration group", "sd.iss", "  Exec(Net, 'localgroup sdfilesadmin /delete', '', SW_HIDE, ewWaitUntilTerminated, Code);\n", "")
    # messages
    m("message 12526 does not name the verb", "msg:12526", "files-write-on", "the-write-word")
    m("message 12526 is longer than the 100 characters the client shows (the first text was 175)", "msg:12526", "ask the administrator for", "ask the administrator of this server, who can allow it, for")
    m("message 12526 loses its place for the request", "msg:12526", "(request %1)", "(request)")
    m("message 12527 is another text", "msg:12527", "Account %1 has files-write %2", "Account %1 has write %2")
    m("message 12527 spells its keyword in capitals (the lower case rule)", "msg:12527", "Account %1 has files-write %2", "Account %1 has FILES-WRITE %2")
    m("message 12528 spells its keywords in capitals (the lower case rule)", "msg:12528", "so it cannot be given files-write:", "so it cannot be given FILES-WRITE:")
    m("message 12526 spells its keyword in capitals (the lower case rule; 13 Nov 26 Windows port)", "msg:12526", "files-write-on", "FILES-WRITE-ON")
    # S.73 item 3 (21 Oct 26)
    m("message 12529 does not name the verb", "msg:12529", "files-admin-on", "the-admin-word")
    m("message 12529 is longer than the 100 characters the client shows", "msg:12529", "ask the administrator for", "ask the administrator of this server, who can allow it, for")
    m("message 12529 loses its place for the request", "msg:12529", "(request %1)", "(request)")
    m("message 12530 is another text", "msg:12530", "Account %1 has files-admin %2", "Account %1 has admin %2")
    m("message 12530 spells its keyword in capitals (the lower case rule)", "msg:12530", "Account %1 has files-admin %2", "Account %1 has FILES-ADMIN %2")
    m("message 12531 spells its keywords in capitals (the lower case rule)", "msg:12531", "so it cannot be given files-admin:", "so it cannot be given FILES-ADMIN:")
    m("message 12531 does not name the word to use first", "msg:12531", "use files-write-on first", "use the other word first")
    return M


def main():
    raw = load()
    res = run_checks(raw)
    failed = [k for k, (ok, _d) in res.items() if not ok]
    for k, (ok, d) in res.items():
        shown = (not ok or k.split(" ")[0] in SHOW) and d          # a failing check says what it saw; so does a check in SHOW (S.72b: F2d prints every request, flag and answer it compared)
        print("  [%s] %s%s" % ("PASS" if ok else "FAIL", k[:400], "" if not shown else "   <- " + d[:1500]))
    print("\ntest-fileswrite-units: %d checks, %d failed" % (len(res), len(failed)))
    # 13 Nov 26 Windows port: Linux's sandbox-net.py, sandbox-netfile.py, netfake.py and sandbox-qmclient.py are not in this tree; the runtime proof here is the verify suite
    print("NOT MEASURED HERE: whether the gate refuses anybody.  On Linux that is sandbox-net.py, sandbox-netfile.py wgroup, netfake.py and sandbox-qmclient.py H0a-H0d, none of "
          "which is in this tree; here it is a real files-only login on an installed server (the verify suite or a witness).")
    if "--selftest" not in sys.argv:
        return 1 if failed else 0
    if failed:
        print("selftest: the real sources already fail %d check(s); the mutants say nothing until they pass" % len(failed))
        return 1
    survivors = 0
    ms = mutants(raw)
    for name, f, old, new in ms:
        if f not in raw:
            print("  [REFUSED ] %s - no such file %s" % (name, f))
            return 2
        if not callable(old) and raw[f].count(old) != 1:
            print("  [REFUSED ] %s - its text occurs %d times in %s, not once" % (name, raw[f].count(old), f))
            return 2
        mr = dict(raw)
        if callable(old):                      # a mutant made by a function of the source (19 Oct 26: the order of two blocks cannot be changed by one replacement)
            mr[f] = old(raw[f])
            if mr[f] == raw[f]:
                print("  [REFUSED ] %s - the function changed nothing in %s" % (name, f))
                return 2
        else:
            mr[f] = raw[f].replace(old, new)
        got = run_checks(mr)
        caught = [k.split(" ")[0] for k, (ok, _d) in got.items() if not ok]
        if caught:
            print("  [KILLED  ] %-84s | %s" % (name, " ".join(caught)))
        else:
            survivors += 1
            print("  [SURVIVED] %s" % name)
    print("%d of %d mutants killed" % (len(ms) - survivors, len(ms)))
    return 1 if survivors else 0


if __name__ == "__main__":
    sys.exit(main())
