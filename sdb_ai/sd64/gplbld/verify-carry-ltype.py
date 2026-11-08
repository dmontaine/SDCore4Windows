#!/usr/bin/env python3
#
# sandbox-ltype.py - 17 Oct 2026, QM4 Fixes 7: L-type dictionary records (links) in I-type expressions, links to links,
#                    links to A, S and I items, a link's file expression, and what a link says when it is wrong.
#                    No install, no sudo.
#
#   python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/sandbox-ltype.py <dir> [--build]
#
# <dir> is a sandbox made by sandbox-fromtree.py (needs a `make`d bin/sd).  With --build it is built first from THIS tree
# (it must be empty or absent).  Exit 0 every row passed, 1 a row failed, 2 it could not run.
#
# START-HISTORY:
# 17 Oct 26 dm  Written.  The rows were first run on a sandbox built from the tree before the change.
# END-HISTORY
#
# THE FILES.  zzlta (titles: TITLE, AUTHOR, YEAR) and zzltb (the same ids, other titles, the second of two files that
# share zzlta's dictionary); zzlbook (the copies of a title: id title-copy, field 1 a mark, field 2 the region, a or b);
# zzlrdr (readers; the books on loan, multivalued).  zzlbook's dictionary has the link TTL (the id is the part of the book
# id before the hyphen; the file is zzlta) and RG (the same id, the dictionary of zzlta, but the file named by an expression:
# zzlt and the region).  zzlrdr's has OUT, a link to zzlbook, so OUT%TTL%TITLE is a link to a link.
#
# A row passes when every pattern in `want` matches the session's output (each is anchored with (?m) and matches a
# line) and no pattern in `deny` does.  The output of a session echoes the command it was given, so a pattern is a piece
# of the data or of a message, never of the command.

import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.path.join(HERE, "sandbox-fromtree.py")
ANSI = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]")
passed = failed = 0

SETUP = """\
   for each f in 'zzlta':@fm:'zzltb':@fm:'zzlbook':@fm:'zzlrdr'
      execute 'DELETE.FILE ':f capturing j
      execute 'CREATE.FILE ':f capturing j
   next f
   open 'zzlta' to ta else stop 'no zzlta'
   open 'DICT zzlta' to dta else stop 'no dict zzlta'
   open 'zzltb' to tb else stop 'no zzltb'
   open 'DICT zzltb' to dtb else stop 'no dict zzltb'
   open 'zzlbook' to bk else stop 'no zzlbook'
   open 'DICT zzlbook' to dbk else stop 'no dict zzlbook'
   open 'zzlrdr' to rd else stop 'no zzlrdr'
   open 'DICT zzlrdr' to drd else stop 'no dict zzlrdr'

   write 'Moby Dick':@fm:'Melville':@fm:'1851' to ta, 'T1'
   write 'Emma':@fm:'Austen':@fm:'1815' to ta, 'T2'
   write 'Moby Dick B':@fm:'Melville':@fm:'1851' to tb, 'T1'
   write 'Emma B':@fm:'Austen':@fm:'1815' to tb, 'T2'
   write 'D':@fm:'1':@fm:'':@fm:'Title':@fm:'20L':@fm:'S' to dta, 'TITLE'
   write 'D':@fm:'2':@fm:'':@fm:'Author':@fm:'12L':@fm:'S' to dta, 'AUTHOR'
   write 'D':@fm:'3':@fm:'':@fm:'Year':@fm:'6R':@fm:'S' to dta, 'YEAR'
   write 'D':@fm:'1':@fm:'':@fm:'Title':@fm:'20L':@fm:'S' to dtb, 'TITLE'
   write 'D':@fm:'3':@fm:'':@fm:'Yr':@fm:'6R':@fm:'S' to dta, 'MY-ITEM'
   write 'A':@fm:'1':@fm:'A-Title':@fm:'':@fm:'':@fm:'':@fm:'':@fm:'':@fm:'L':@fm:'20' to dta, 'ATTL'
   write 'I':@fm:'UPCASE(AUTHOR)':@fm:'':@fm:'Upper':@fm:'12L':@fm:'S' to dta, 'UPAUTH'

   write 'x':@fm:'b' to bk, 'T1-1'
   write 'y':@fm:'a' to bk, 'T1-2'
   write 'z':@fm:'a' to bk, 'T2-1'
   write 'D':@fm:'1':@fm:'':@fm:'Copy':@fm:'6L':@fm:'S' to dbk, 'COPY'
   write 'D':@fm:'2':@fm:'':@fm:'Reg':@fm:'4L':@fm:'S' to dbk, 'REGION'
   write 'L':@fm:'FIELD(@ID, "-", 1)':@fm:'zzlta' to dbk, 'TTL'
   write 'L':@fm:'FIELD(@ID, "-", 1)':@fm:'zzlta':@fm:'"zzlt":REGION' to dbk, 'RG'
   write 'I':@fm:'TTL%TITLE':@fm:'':@fm:'Book title':@fm:'20L':@fm:'S' to dbk, 'TT'
   write 'I':@fm:'UPCASE(TTL%AUTHOR)':@fm:'':@fm:'Writer':@fm:'12L':@fm:'S' to dbk, 'TU'
   write 'I':@fm:'COPY : "/" : TTL%TITLE':@fm:'':@fm:'Both':@fm:'24L':@fm:'S' to dbk, 'TC'
   write 'I':@fm:'TTL%UPAUTH':@fm:'':@fm:'Via I':@fm:'12L':@fm:'S' to dbk, 'TUP'
   write 'I':@fm:'RG%TITLE':@fm:'':@fm:'Region title':@fm:'20L':@fm:'S' to dbk, 'TRG'
   write 'D':@fm:'1':@fm:'':@fm:'XY':@fm:'4L':@fm:'S' to dbk, 'X%Y'
   write 'I':@fm:'X%Y':@fm:'':@fm:'XYT':@fm:'4L':@fm:'S' to dbk, 'XYT'
   write 'I':@fm:'NOSUCHFIELD + 1':@fm:'':@fm:'Undefined':@fm:'6R':@fm:'S' to dbk, 'UNDEF'
   write 'D':@fm:'1':@fm:'':@fm:'F1':@fm:'6L':@fm:'S' to dbk, 'f1'      ;* 27 Oct 26 (S.87): an Fn name is a field only if the dictionary has a D item of that name
   write 'I':@fm:'F1 : "!"':@fm:'':@fm:'F1':@fm:'6L':@fm:'S' to dbk, 'FONE'
   write 'I':@fm:'TRANS("zzlta", FIELD(@ID, "-", 1), TITLE, "X")':@fm:'':@fm:'Trans':@fm:'20L':@fm:'S' to dbk, 'TRN'
   write 'L':@fm:'FIELD(@ID, "-", 1)':@fm:'zznosuch' to dbk, 'BADF'
   write 'L':@fm:'':@fm:'zzlta' to dbk, 'BADN'
   write 'L':@fm:'A;B':@fm:'zzlta' to dbk, 'BADC'
   write 'L':@fm:'@ID':@fm:'' to dbk, 'BADE'
   write 'I':@fm:'TTL%NOSUCH':@fm:'':@fm:'No item':@fm:'6L':@fm:'S' to dbk, 'BADI'
   write 'I':@fm:'BADN%TITLE':@fm:'':@fm:'No id':@fm:'6L':@fm:'S' to dbk, 'BADNI'
   write 'I':@fm:'BADC%TITLE':@fm:'':@fm:'Compound':@fm:'6L':@fm:'S' to dbk, 'BADCI'
   write 'I':@fm:'COPY%TITLE':@fm:'':@fm:'Not a link':@fm:'6L':@fm:'S' to dbk, 'NOTL'
   write 'L':@fm:'@ID':@fm:'zzlbook' to dbk, 'CY'
   write 'I':@fm:'TTL%MY-ITEM':@fm:'':@fm:'Hy':@fm:'6R':@fm:'S' to dbk, 'HY'

   write 'T1-1':@vm:'T2-1' to rd, 'R1'
   write 'T1-2' to rd, 'R2'
   write 'D':@fm:'1':@fm:'':@fm:'Loans':@fm:'8L':@fm:'M' to drd, 'LOANS'
   write 'L':@fm:'LOANS':@fm:'zzlbook' to drd, 'OUT'
   write 'I':@fm:'OUT%TTL%TITLE':@fm:'':@fm:'Loan titles':@fm:'20L':@fm:'M' to drd, 'RT'
   crt 'SETUP DONE'
end
"""

ERR = r"Non-numeric where numeric|not defined|Cannot open|not found|Compilation error|nested too deeply|no id expression|compound"
CY = "%".join(["CY"] * 12) + "%COPY"

# (label, command, want, deny)
ROWS = [
    ("CONTROL: a link in a query reaches a D item one link away (the heading and the data are the target's)",
     "LIST zzlbook TTL%TITLE TTL%AUTHOR", [r"^\S+\s+Moby Dick\s+Melville", r"^T2-1\s+Emma\s+Austen", r"Title\.+\s+Author"], [ERR]),
    ("CONTROL: ... and an I item one link away", "LIST zzlbook TTL%UPAUTH", [r"^T1-1\s+MELVILLE", r"^T2-1\s+AUSTEN"], [ERR]),
    ("CONTROL: an I-type with an explicit TRANS() still works", "LIST zzlbook TRN", [r"^T1-1\s+Moby Dick", r"^T2-1\s+Emma"], [ERR]),
    ("CONTROL: an I-type naming FnN (F1) still works", "LIST zzlbook FONE", [r"^T1-1\s+x!", r"^T2-1\s+z!"], [ERR]),
    ("CONTROL: a record in the dictionary called X%Y is a field, not a link (it is found first)", "LIST zzlbook XYT",
     [r"^T1-1\s+x\b", r"^T2-1\s+z\b"], [ERR]),
    ("CONTROL: a link in a selection", 'LIST zzlbook WITH TTL%AUTHOR = "Melville" COPY', [r"^T1-1\s+x", r"^T1-2\s+y"], [r"^T2-1", ERR]),

    ("an I-type that is a link reference (TTL%TITLE)", "LIST zzlbook TT", [r"Book title", r"^T1-1\s+Moby Dick", r"^T1-2\s+Moby Dick", r"^T2-1\s+Emma"], [ERR]),
    ("a link inside a function (UPCASE(TTL%AUTHOR))", "LIST zzlbook TU", [r"^T1-1\s+MELVILLE", r"^T2-1\s+AUSTEN"], [ERR]),
    ("a link in an expression with a field and a string", "LIST zzlbook TC", [r"^T1-1\s+x/Moby Dick", r"^T2-1\s+z/Emma"], [ERR]),
    ("a link to an I-type item, from an I-type", "LIST zzlbook TUP", [r"^T1-1\s+MELVILLE", r"^T2-1\s+AUSTEN"], [ERR]),
    ("a link in a query reaches an A-type item (and takes its heading)", "LIST zzlbook TTL%ATTL",
     [r"A-Title", r"^T1-1\s+Moby Dick", r"^T2-1\s+Emma"], [ERR]),
    ("a link to a link, in an I-type: OUT%TTL%TITLE, the loans are several ids", "LIST zzlrdr RT",
     [r"Loan titles", r"^R1\s+Moby Dick", r"^\s+Emma", r"^R2\s+Moby Dick"], [ERR]),
    ("a link to a link, in a query", "LIST zzlrdr OUT%TTL%TITLE", [r"^R1\s+Moby Dick", r"^\s+Emma", r"^R2\s+Moby Dick"], [ERR]),
    ("a link to a link reaches an A-type item at the end", "LIST zzlrdr OUT%TTL%ATTL", [r"A-Title", r"^R1\s+Moby Dick", r"^\s+Emma"], [ERR]),
    ("the file expression of a link names the file read (zzltb for region b), the dictionary being zzlta's, in a query", "LIST zzlbook RG%TITLE",
     [r"^T1-1\s+Moby Dick B", r"^T1-2\s+Moby Dick\s*$", r"^T2-1\s+Emma\s*$"], [ERR]),
    ("...and in an I-type", "LIST zzlbook TRG", [r"Region title", r"^T1-1\s+Moby Dick B", r"^T1-2\s+Moby Dick\s*$"], [ERR]),
    ("a link in BY sorts by what it reaches", "LIST zzlbook BY TTL%TITLE COPY", [r"(?s)T2-1.*T1-1"], [ERR]),
    ("EVAL of a link reference takes the format of the item it reaches (20L: a column 20 wide, then the 3 spaces between columns)",
     'LIST zzlbook EVAL "TTL%TITLE" COPY', [r"^T1-1\s+Moby Dick {14}x\s*$", r"^T2-1\s+Emma {19}z\s*$"], [ERR]),

    ("a link to a file with no dictionary says so, naming the file and the link", "LIST zzlbook BADF%TITLE",
     [r"Cannot open zznosuch dictionary for link BADF"], []),
    ("an item that is not there says which item (it used to name the link)", "LIST zzlbook TTL%NOSUCH", [r"Link item NOSUCH not found"], [r"Link item TTL not found"]),
    ("...in an I-type", "LIST zzlbook BADI", [r"Link item NOSUCH not found"], []),
    ("a link with no id expression", "LIST zzlbook BADNI", [r"Link BADN has no id expression"], []),
    ("a link whose expression is compound", "LIST zzlbook BADCI", [r"The expressions of link BADC cannot be compound"], []),
    ("a link that names no file", "LIST zzlbook BADE%TITLE", [r"Link BADE names no file"], []),
    ("links nested too deeply", "LIST zzlbook " + CY, [r"Links are nested too deeply"], []),
    ("a name with a % whose first part is not a link is an undefined field", "LIST zzlbook NOTL", [r"Field 'COPY%TITLE' is not defined"], []),
    ("an undefined field in an I-type is reported, not a crash in $icomp", "LIST zzlbook UNDEF", [r"Field 'NOSUCHFIELD' is not defined"],
     [r"Non-numeric where numeric required"]),
    ("an item name with a hyphen after the % is not supported: the message names the part before the hyphen", "LIST zzlbook HY",
     [r"Link item MY not found"], []),
]


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
    say("sandbox-ltype: CANNOT RUN - " + msg)
    sys.exit(2)


def sess(box, *cmds):
    p = subprocess.run([sys.executable, TOOL, box, "sess", os.path.join(box, "user_accounts")] + list(cmds),
                       capture_output=True, text=True, timeout=900)
    out = ANSI.sub("", p.stdout + p.stderr)
    return out.split(":TERM 200,9999", 1)[-1]


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) != 1:
        bail("usage: sandbox-ltype.py <dir> [--build]")
    box = os.path.abspath(args[0])
    sysd = os.path.join(box, "sys")
    bp = os.path.join(sysd, "bp")
    say("sandbox-ltype: sandbox %s" % box)
    if "--build" in sys.argv:
        if os.path.exists(box) and os.listdir(box):
            bail("%s is not empty" % box)
        r = subprocess.run([sys.executable, TOOL, box, "all"], capture_output=True, text=True, errors="replace", timeout=900)
        if "[FAIL]" in r.stdout or r.returncode != 0 or "[PASS] THIRD.COMPILE" not in r.stdout:
            bail("the sandbox build did not pass:\n" + r.stdout[-800:])
        say("sandbox-ltype: built, bootstrap passed")
    elif not os.path.isfile(os.path.join(sysd, "bin", "sd")):
        bail("%s holds no built sandbox (use --build, or point it at one)" % box)
    subprocess.run([sys.executable, TOOL, box, "start"], capture_output=True, text=True, errors="replace", timeout=120)

    prog = os.path.join(bp, "zzltset")
    chg = os.path.join(bp, "zzltchg")
    try:
        with open(prog, "w") as f:
            f.write(SETUP)
        out = sess(box, "BASIC bp zzltset", "RUN bp zzltset")
        if "SETUP DONE" not in out:
            bail("the fixture was not made:\n" + out[-600:])
        say("--- links in dictionaries and queries ----------------------------------------------------------")
        for label, cmd, want, deny in ROWS:
            out = sess(box, cmd)
            lines = out.replace("\r", "")
            missing = [w for w in want if not re.search(w if w.startswith("(?") else "(?m)" + w, lines)]
            found = [d for d in deny if re.search("(?m)" + d, lines)]
            row("%s" % label, not missing and not found,
                ("pattern(s) missing %s; denied pattern(s) present %s; output: %s" % (missing, found, lines[-500:].replace("\n", " | "))))

        # An I-type holds the TRANS() the link made when it was compiled, so a link that is changed afterwards is not followed
        # until the I-type is compiled again (CD); a query that names the link is compiled each time and does follow it.
        say("\n--- changing a link ----------------------------------------------------------------------------")
        chg = os.path.join(bp, "zzltchg")
        with open(chg, "w") as f:
            f.write("   open 'DICT zzlbook' to dbk else stop 'no dict zzlbook'\n"
                    "   write 'L':@fm:'FIELD(@ID, \"-\", 1)':@fm:'zzltb' to dbk, 'TTL'\n   crt 'CHANGED'\nend\n")
        out = sess(box, "LIST zzlbook TT")
        row("CONTROL: before the change TT gives the titles of zzlta", re.search(r"(?m)^T1-1\s+Moby Dick\s*$", out) is not None, out[-300:].replace("\n", " | "))
        out = sess(box, "BASIC bp zzltchg", "RUN bp zzltchg")
        if "CHANGED" not in out:
            bail("the link was not changed:\n" + out[-500:])
        out = sess(box, "LIST zzlbook TT")
        row("the I-type, compiled before the change, still gives the old answer (the link is worked out when it is compiled)",
            re.search(r"(?m)^T1-1\s+Moby Dick\s*$", out) is not None and "Moby Dick B" not in out, out[-300:].replace("\n", " | "))
        out = sess(box, "LIST zzlbook TTL%TITLE")
        row("a query that names the link is compiled each time, so it follows the change at once",
            re.search(r"(?m)^T1-1\s+Moby Dick B\s*$", out) is not None, out[-300:].replace("\n", " | "))
        out = sess(box, "COMPILE.DICT zzlbook TT", "LIST zzlbook TT")
        row("CD compiles the I-type again and it follows the changed link",
            re.search(r"(?m)^Compiling TT", out) is not None and re.search(r"(?m)^T1-1\s+Moby Dick B\s*$", out) is not None,
            out[-300:].replace("\n", " | "))
    finally:
        # --keep leaves the four files, to look at them by hand
        if "--keep" not in sys.argv:
            sess(box, *["DELETE.FILE %s" % f for f in ("zzlta", "zzltb", "zzlbook", "zzlrdr")])
        for p in (prog, chg):
            if os.path.exists(p):
                os.remove(p)
        if os.path.isdir(os.path.join(sysd, "bp.out")):
            for f in os.listdir(os.path.join(sysd, "bp.out")):
                if f.startswith("zzlt"):
                    os.remove(os.path.join(sysd, "bp.out", f))

    say("\nsandbox-ltype: %d passed, %d failed" % (passed, failed))
    sys.exit(0 if failed == 0 else 1)


main()
