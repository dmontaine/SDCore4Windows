#!/usr/bin/env python3
#
# sandbox-cmd-a9.py - 1.2-0 bundles A-7, A-9, A-10 and A-11, the second sitting (14 Oct 26): the command line, select lists
#                     and the ED editor.  Sheet items 449 (SHOW.LIST), 146 (LPTR and NO.PAGE on a program run by its
#                     catalogue name), 296 (.C- in the command stack editor), 396 (the command stack is kept in the account
#                     the user entered), 490 (CATALOG ... LOCAL asks before it overwrites a pointer to a different object
#                     file), 268 (ED's EV on a compound I-type) and 320 (ED takes text, subvalue and value marks as typed).
#                     No install, no sudo.
#
#   python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/sandbox-cmd-a9.py <dir> [--build]
#
# <dir> is a sandbox made by sandbox-fromtree.py.  With --build it is built first from THIS tree (it must be empty or
# absent).  Exit 0 every row passed, 1 a row failed, 2 it could not run.
#
# START-HISTORY:
# 14 Oct 26 dm  Written for 1.2-0 bundles A-7, A-9, A-10 and A-11: sheet 449, 146, 296, 396, 490, 268 and 320.
# END-HISTORY
#
# THE INSTRUMENT.  Every session is the real bin/sd with its commands on stdin, run in the SDSYS account as the
# administrator (the sandbox user plays SDSYS; a CPROC patched as sandbox-gates.py patches it is not needed here).  What a
# command printed is read from the output with the echoed command lines (those that begin with a colon) taken out, and every
# pattern is anchored to the start of a line, because a session echoes what it was given.  ED is driven through its own
# command language, the lines it waits for being the session's next lines; the two rows that need a byte above 250 send the
# session BYTES, not text.
#
#   A  449  SHOW.LIST: its first page, T N P Q QC and ?, S and C with numbers, ranges, lists, VISIBLE and ALL, a numbered
#           list other than 0, a list that is not active, a bad number, a bad item (and the list unchanged after it)
#   B  296  .C- undoes the .C before it; .L and .? may come between; a command run, or another dot command, ends the chance
#   C  146  a catalogued program run by its catalogue name takes LPTR (output to printer 0) and NO.PAGE; a quoted LPTR is not one
#   D  396  the command stack is saved in the account the user ENTERED, not the one he LOGTO'd to
#   E  490  CATALOG ... LOCAL over a pointer to another object file asks (N is the default); Y replaces; NO.QUERY does not
#           ask; the same file again does not ask
#   F  268 and 320  ED
#
# NOT TESTED HERE: 523 (an error in ED's SPOOL print loop leaving the printer open) - it needs a failing print loop.

import getpass
import os
import re
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.path.join(HERE, "sandbox-fromtree.py")
ANSI = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]")
USER = getpass.getuser()
passed = failed = 0
BOX = SYS = SD = None


def say(s=""):
    print(s)
    sys.stdout.flush()


def row(name, ok, detail=""):
    global passed, failed
    if ok:
        passed += 1
        say("  [PASS] " + name)
    else:
        failed += 1
        say("  [FAIL] " + name + ("   <- " + detail if detail else ""))


def bail(msg):
    say("sandbox-cmd-a9: CANNOT RUN - " + msg)
    sys.exit(2)


def env():
    e = dict(os.environ, SD_CONFIG=os.path.join(BOX, "sd.conf"), SDTEST_ADMIN="1")
    e.pop("SSH_CONNECTION", None)
    e.pop("SSH_TTY", None)
    return e


def sd(cmds, cwd=None, internal=False, raw=None, term="200,9999"):
    """Run sd as the administrator with the commands on stdin (or the bytes in `raw`, which are used as they are); return
    the lines it printed after the TERM line, echoed command lines removed.  Prints the real inputs.  `term` is the answer
    to the terminal question at sign-on, width and height: a TERM command typed later does not change @CRTHIGH."""
    cwd = cwd or SYS
    argv = [SD] + (["-internal"] if internal else [])
    say("    > [admin]%s%s in %s: %s" % (" [internal]" if internal else "", (" [TERM " + term + "]") if term != "200,9999" else "",
                                         os.path.relpath(cwd, BOX) if cwd != BOX else ".",
                                         " | ".join(c if len(c) < 70 else c[:67] + "..." for c in cmds)))
    if raw is None:
        raw = ("\nTERM " + term + "\n" + "".join(c + "\n" for c in cmds) + "OFF\n").encode("latin-1")
    p = subprocess.run(argv, input=raw, cwd=cwd, env=env(), capture_output=True, errors=None, timeout=300)
    text = ANSI.sub("", (p.stdout + p.stderr).decode("latin-1")).split(":TERM " + term, 1)[-1]
    return [ln.rstrip() for ln in text.splitlines() if ln.strip() and not ln.startswith(":")]


def has(lines, pattern):
    return any(re.search(pattern, ln) for ln in lines)


def put(path, text):
    with open(path, "w", encoding="latin-1") as f:
        f.write(text)


def tagged(lines, tag):
    for ln in lines:
        m = re.match(r"^%s\[(.*)\]\s*$" % tag, ln)
        if m:
            return m.group(1)
    return None


PROGS = {
    # a numbered select list of 12 items, item01 to item12
    "zzslmk": "   l = ''\n   for i = 1 to 12\n      l<-1> = 'item':fmt(i, '2\"0\"R')\n   next i\n   formlist l to 0\n   crt 'MADE'\nend\n",
    "zzslmk2": "   l = ''\n   for i = 1 to 4\n      l<-1> = 'two':i\n   next i\n   formlist l to 2\n   crt 'MADE2'\nend\n",
    "zzsldmp": ("   a = selectinfo(0, 1)\n   kept = ''\n   loop\n      readnext id from 0 else exit\n      kept<-1> = id\n   repeat\n"
                "   crt 'LEFT[':a:'][':dcount(kept, @fm):'][':change(kept, @fm, '/'):']'\nend\n"),
    "zzsldmp2": ("   a = selectinfo(2, 1)\n   kept = ''\n   loop\n      readnext id from 2 else exit\n      kept<-1> = id\n   repeat\n"
                 "   crt 'LEFT2[':a:'][':dcount(kept, @fm):'][':change(kept, @fm, '/'):']'\nend\n"),
    # 146: a program that prints a line and says what it was given; one that prints twenty lines
    "zzcatp": "   print 'CATP-OUT'\n   crt 'CATP-SENTENCE[':@sentence:']'\nend\n",
    "zzcatn": "   for i = 1 to 20\n      print 'ROW':fmt(i, '2\"0\"R')\n   next i\n   print 'ROWEND'\nend\n",
    "zzholdrd": ("   open '$hold' to h else stop 'no hold'\n   read x from h, 'zzcatout' then crt 'HOLD[':change(x, @fm, '/'):']' else crt 'HOLD[none]'\n"
                 "   delete h, 'zzcatout'\nend\n"),
    # 490: the same call name from two files
    "zzcl1": "   crt 'ZZCL1'\nend\n",
    "zzclrd": ("   read r from @voc, 'zzcl1' then crt 'CLREC[':r<1>:'/':r<2>:'/':r<3>:']' else crt 'CLREC[none]'\n"
               "   delete @voc, 'zzcl1'\nend\n"),
    # 268 and 320: an I-type with quoted text, brackets and semicolons; and what is in a record
    "zzedmk": ("   execute 'DELETE.FILE zzedf' capturing j\n   execute 'CREATE.FILE zzedf' capturing j\n   open 'DICT', 'zzedf' to d else stop 'no dict'\n"
               "   rec = 'I':@fm:'\"p;q\":(r;s);' : \"'t;u'\"\n   write rec to d, 'zzedi'\n   crt 'EDMADE'\nend\n"),
    "zzedrd": ("   open 'DICT', 'zzedf' to d else stop 'no dict'\n   read r from d, 'zzedi' then crt 'F2[':r<2>:']' else crt 'F2[none]'\nend\n"),
    "zzedrd2": ("   open 'zzedf' to f else stop 'no f'\n   read r from f, 'zzedrec' then\n"
                "      crt 'MARK[':count(r<1>, char(253)):'][':count(r, char(254)):'][':r<2>:']'\n   end else crt 'MARK[none]'\nend\n"),
}


def main():
    global BOX, SYS, SD
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) != 1:
        bail("usage: sandbox-cmd-a9.py <dir> [--build]")
    BOX = os.path.abspath(args[0])
    SYS = os.path.join(BOX, "sys")
    SD = os.path.join(SYS, "bin", "sd")
    say("sandbox-cmd-a9: sandbox  %s" % BOX)
    say("sandbox-cmd-a9: user %s" % USER)
    if "--build" in sys.argv:
        if os.path.exists(BOX) and os.listdir(BOX):
            bail("%s is not empty" % BOX)
        r = subprocess.run([sys.executable, TOOL, BOX, "all"], capture_output=True, text=True, errors="replace", timeout=900)
        if "[FAIL]" in r.stdout or r.returncode != 0 or "[PASS] THIRD.COMPILE" not in r.stdout:
            bail("the sandbox build did not pass:\n" + r.stdout[-800:])
        say("sandbox-cmd-a9: built, bootstrap passed")
    elif not os.path.isfile(SD):
        bail("%s holds no built sandbox (use --build, or point it at one)" % BOX)
    subprocess.run([sys.executable, TOOL, BOX, "start"], capture_output=True, text=True, errors="replace", timeout=120)

    say("\n--- preparation: the probes, a second directory for the CATALOG rows, a second account -------------------------")
    for nm, text in PROGS.items():
        put(os.path.join(SYS, "bp", nm), text)
    out = sd(["BASIC bp " + " ".join(PROGS), "CREATE.FILE bp2 DIRECTORY"])
    if not has(out, r"^Compiled %d program\(s\) with no errors" % len(PROGS)):
        bail("the probes did not compile:\n" + "\n".join(out[-10:]))
    # a copy of zzcl1's source in bp2, compiled there: the same call name, a different object file
    put(os.path.join(SYS, "bp2", "zzcl1"), PROGS["zzcl1"])
    out = sd(["BASIC bp2 zzcl1"])
    if not has(out, r"^Compiled 1 program\(s\) with no errors"):
        bail("zzcl1 did not compile in bp2:\n" + "\n".join(out[-6:]))
    acct2 = os.path.join(BOX, "user_accounts", "zzacct2")
    if os.path.isdir(acct2):
        shutil.rmtree(acct2)
    os.makedirs(acct2)
    put(os.path.join(SYS, "bp", "zzfix"), "\n".join([
        "$internal",
        "   acct = '%s'" % acct2,
        "   create.file acct:'/voc' dynamic on error crt 'FIX create voc failed' ; stop",
        "   openpath acct:'/voc' to v else crt 'FIX open voc failed' ; stop",
        "   openpath '%s/newvoc' to nv else crt 'FIX no newvoc' ; stop" % SYS,
        "   select nv to 11",
        "   loop",
        "      readnext id from 11 else exit",
        "      read rec from nv, id then write rec to v, id",
        "   repeat",
        "   write 'X' to v, '$command.stack'",        # CREATE.ACCOUNT writes this record; NEWVOC does not carry it
        "   crt 'FIX done'",
        "end", ""]))
    out = sd(["BASIC bp zzfix", "RUN bp zzfix"], internal=True)
    if not has(out, r"^FIX done$"):
        bail("the second account was not built:\n" + "\n".join(out[-6:]))
    put(os.path.join(SYS, "bp", "zzfix2"), "   write 'X' to @voc, '$command.stack'\n   crt 'FIX2 done'\nend\n")
    out = sd(["BASIC bp zzfix2", "RUN bp zzfix2"])
    if not has(out, r"^FIX2 done$"):
        bail("the SDSYS VOC did not get its $command.stack record:\n" + "\n".join(out[-6:]))
    say("  [done] probes, bp2, and the account %s" % acct2)

    # -------------------------------------------------------------------------------------------------------------
    say("\n--- A. 449: SHOW.LIST ------------------------------------------------------------------------------------")
    out = sd(["RUN bp zzslmk", "SHOW.LIST", "Q", "RUN bp zzsldmp"])
    items = [ln for ln in out if re.match(r"^\s+\d+ [* ] item\d\d$", ln)]
    row("the first page: twelve items, each numbered and starred, all selected at the start",
        len(items) == 12 and all(re.match(r"^\s+\d+ \* item\d\d$", ln) for ln in items), repr(items[:3]))
    row("Q keeps what is starred: all twelve are in the list again", tagged(out, "LEFT") == "1][12][" + "/".join("item%02d" % i for i in range(1, 13)), repr(tagged(out, "LEFT")))
    out = sd(["RUN bp zzslmk", "SHOW.LIST", "C 3", "Q", "RUN bp zzsldmp"])
    row("C 3 clears one: it is shown without its star, and is gone from the list",
        has(out, r"^\s+3   item03$") and tagged(out, "LEFT") == "1][11][" + "/".join("item%02d" % i for i in range(1, 13) if i != 3), repr(tagged(out, "LEFT")))
    out = sd(["RUN bp zzslmk", "SHOW.LIST", "C1,4,8-10", "Q", "RUN bp zzsldmp"])
    row("C 1,4,8-10: numbers and a range in one command (comma separated)",
        tagged(out, "LEFT") == "1][7][item02/item03/item05/item06/item07/item11/item12", repr(tagged(out, "LEFT")))
    out = sd(["RUN bp zzslmk", "SHOW.LIST", "C 2 3 5-6", "S5", "Q", "RUN bp zzsldmp"])
    row("space separated, and S5 with no space after S: 2, 3, 5 and 6 cleared, 5 set again",
        tagged(out, "LEFT") == "1][9][item01/item04/item05/item07/item08/item09/item10/item11/item12", repr(tagged(out, "LEFT")))
    out = sd(["RUN bp zzslmk", "SHOW.LIST", "C ALL", "2-3", "Q", "RUN bp zzsldmp"])
    row("C ALL, then a bare item (the same as S): only items 2 and 3 are left", tagged(out, "LEFT") == "1][2][item02/item03", repr(tagged(out, "LEFT")))
    out = sd(["RUN bp zzslmk", "SHOW.LIST", "c a", "s 12", "q", "RUN bp zzsldmp"])
    row("lower case, and ALL shortened to A: all cleared, then 12 set", tagged(out, "LEFT") == "1][1][item12", repr(tagged(out, "LEFT")))
    out = sd(["RUN bp zzslmk", "SHOW.LIST", "QC", "RUN bp zzsldmp"])
    row("QC quits clearing every item: the list is empty", tagged(out, "LEFT") == "0][0][", repr(tagged(out, "LEFT")))
    out = sd(["RUN bp zzslmk", "SHOW.LIST", "C 99", "C 5-3", "C x", "Q", "RUN bp zzsldmp"])
    bad = [ln for ln in out if re.match(r"^Invalid item \(", ln)]
    row("CONTROL: a bad item (99, a backwards range, a word) is refused with its own message each time, and changes nothing",
        len(bad) == 3 and tagged(out, "LEFT") == "1][12][" + "/".join("item%02d" % i for i in range(1, 13)), "%r %r" % (bad, tagged(out, "LEFT")))

    out = sd(["RUN bp zzslmk", "SHOW.LIST"])
    row("when the input ends inside SHOW.LIST the command ends too (the session's own OFF is read as an item and refused, then "
        "the end of input is taken as Q): it does not ask again for ever", has(out, r"^Invalid item \(OFF\)"), repr(out[-4:]))
    out = sd(["RUN bp zzslmk", "SHOW.LIST", "Q"], term="80,10")
    first_page = [ln for ln in out if re.match(r"^\s+\d+ [* ] item\d\d$", ln)]
    row("a screen 10 lines high shows 7 items a page (the screen height less 3)", len(first_page) == 7 and first_page[-1].strip().startswith("7 "), repr(first_page))
    out = sd(["RUN bp zzslmk", "SHOW.LIST", "N", "C V", "Q", "RUN bp zzsldmp"], term="80,10")
    row("N goes to the next page (items 8 to 12) and C VISIBLE clears just those: 1-7 are left",
        tagged(out, "LEFT") == "1][7][item01/item02/item03/item04/item05/item06/item07", repr(tagged(out, "LEFT")))
    out = sd(["RUN bp zzslmk", "SHOW.LIST", "", "", "P", "T", "C VIS", "Q", "RUN bp zzsldmp"], term="80,10")
    row("Return is N (and stays on the last page), then P and T go back to the top, and VIS (VISIBLE shortened) clears page 1: 8 to 12 are left",
        tagged(out, "LEFT") == "1][5][item08/item09/item10/item11/item12", repr(tagged(out, "LEFT")))

    out = sd(["RUN bp zzslmk2", "SHOW.LIST 2", "C 1-2", "Q", "RUN bp zzsldmp2"])
    row("SHOW.LIST 2 works on list 2: two of its four items are cleared", tagged(out, "LEFT2") == "1][2][two3/two4", repr(tagged(out, "LEFT2")))
    out = sd(["SHOW.LIST 5"])
    row("a list that is not active is refused: Select list 5 is not active", has(out, r"^Select list 5 is not active"), repr(out[-3:]))
    out = sd(["SHOW.LIST x"])
    row("a list number that is not a number is refused", has(out, r"^Illegal select list number"), repr(out[-3:]))
    out = sd(["SHOW.LIST 99"])
    row("a list number above the highest (12) is refused", has(out, r"^Illegal select list number"), repr(out[-3:]))
    out = sd(["RUN bp zzslmk", "SHOW.LIST", "?", "", "Q", "RUN bp zzsldmp"])
    row("? shows the help (one line for every command) and asks for a key; the list is then used as before",
        has(out, r"^QC\s+Quit, clearing every item") and has(out, r"^Press return to continue, Q to quit")
        and tagged(out, "LEFT") == "1][12][" + "/".join("item%02d" % i for i in range(1, 13)), repr(out[-4:]))

    # -------------------------------------------------------------------------------------------------------------
    say("\n--- B. 296: .C- in the command stack editor ---------------------------------------------------------------")
    out = sd(["WHO", ".C/WHO/DATE/", ".C-"])
    shown = [ln for ln in out if re.match(r"^01  ", ln)]
    row("CONTROL: .C changes the top entry and shows it (01  DATE); .C- shows it as it was (01  WHO)",
        shown == ["01  DATE", "01  WHO"], repr(shown))
    out = sd(["WHO", ".C/WHO/DATE/", ".C-", ".C-"])
    row("a second .C- has nothing to undo, and says so", has(out, r"^There is no \.C to undo"), repr(out[-3:]))
    out = sd(["WHO", ".C/WHO/DATE/", ".L2", ".?", ".C-"])
    shown = [ln for ln in out if re.match(r"^01  ", ln)]
    row("an intervening .L and .? are allowed: .C- still puts it back", shown[-1:] == ["01  WHO"] and not has(out, r"^There is no \.C to undo"), repr(shown))
    out = sd(["WHO", ".C/WHO/DATE/", "WHO", ".C-"])
    row("a command that is run in between ends the chance: There is no .C to undo", has(out, r"^There is no \.C to undo"), repr(out[-3:]))
    out = sd(["WHO", "DATE", ".C2/WHO/TIME/", ".A1 x", ".C-"])
    row("another dot command in between (.A) ends it too", has(out, r"^There is no \.C to undo"), repr(out[-3:]))
    out = sd([".C-"])
    row("CONTROL: with no .C before it, .C- says so", has(out, r"^There is no \.C to undo"), repr(out[-3:]))
    out = sd(["WHO", "DATE", ".C2/WHO/TIME/", ".C-", ".L2"])
    row("it is the entry that .C changed that comes back (entry 2, not the top): the list shows WHO again as entry 2",
        has(out, r"^02  WHO$") and has(out, r"^01  DATE$"), repr(out[-5:]))

    # -------------------------------------------------------------------------------------------------------------
    say("\n--- C. 146: a catalogued program run by its catalogue name ------------------------------------------------")
    out = sd(["CATALOG bp zzcatp", "CATALOG bp zzcatn"])
    row("setup: both programs are in the private catalogue",
        has(out, r"^zzcatp added to private catalogue") and has(out, r"^zzcatn added to private catalogue"), repr(out[-3:]))
    out = sd(["zzcatp"])
    row("CONTROL: run by its catalogue name it prints on the screen", has(out, r"^CATP-OUT$"), repr(out[-3:]))
    out = sd(["SETPTR 0,80,60,0,0,3,AS zzcatout,BRIEF", "zzcatp LPTR", "RUN bp zzholdrd"])
    row("LPTR: the output went to printer 0 (the $HOLD entry), not the screen",
        not has(out, r"^CATP-OUT$") and tagged(out, "HOLD") is not None and "CATP-OUT" in tagged(out, "HOLD"), repr(out[-4:]))
    row("... and the word is left in the sentence for the program to see", has(out, r"^CATP-SENTENCE\[zzcatp LPTR\]"), repr(out[-4:]))
    out = sd(["SETPTR 0,80,60,0,0,3,AS zzcatout,BRIEF", "zzcatp lptr", "RUN bp zzholdrd"])
    row("... in lower case too", not has(out, r"^CATP-OUT$") and "CATP-OUT" in (tagged(out, "HOLD") or ""), repr(out[-4:]))
    out = sd(["SETPTR 0,80,60,0,0,3,AS zzcatout,BRIEF", "zzcatp 'a LPTR b'", "RUN bp zzholdrd"])
    row("CONTROL: a LPTR inside quotation marks is an argument, not a keyword: the output stays on the screen",
        has(out, r"^CATP-OUT$"), repr(out[-4:]))
    out = sd(["SETPTR 0,80,60,0,0,3,AS zzcatout,BRIEF", "zzcatp zzcatp LPTR", "RUN bp zzholdrd"])
    row("the program's own name is not a keyword even when it repeats a word of the sentence (LPTR is found after it)",
        not has(out, r"^CATP-OUT$"), repr(out[-4:]))
    out = sd(["zzcatn NO.PAGE"], term="80,10")
    rows = [ln for ln in out if re.match(r"^ROW", ln)]
    row("NO.PAGE: twenty lines on a 6 line screen are printed without stopping, to ROWEND", len(rows) == 21 and rows[-1] == "ROWEND", "%d lines" % len(rows))
    out = sd(["zzcatn", "Q"], term="80,10")
    rows = [ln for ln in out if re.match(r"^ROW", ln)]
    row("CONTROL: without it the output is paginated: it stops after a page, and Q ends it before ROWEND",
        0 < len(rows) < 21 and "ROWEND" not in rows, "%d lines" % len(rows))

    # -------------------------------------------------------------------------------------------------------------
    say("\n--- D. 396: the command stack is saved in the account the user entered --------------------------------------")
    stacks = os.path.join(SYS, "stacks")
    shutil.rmtree(stacks, ignore_errors=True)
    shutil.rmtree(os.path.join(acct2, "stacks"), ignore_errors=True)
    out = sd(["WHO", "LOGTO " + acct2, "DATE"])
    mine = os.path.join(stacks, USER)
    got = open(mine, encoding="latin-1").read() if os.path.isfile(mine) else None
    row("the stack is in the entry account's stacks directory, under the user's name: %s" % os.path.relpath(mine, BOX),
        got is not None and "WHO" in got and "DATE" in got, repr(got))
    parts = got.split("\n") if got is not None else []
    row("... and it holds the commands typed AFTER the LOGTO as well as before it (most recent first: OFF, DATE, LOGTO, WHO)",
        parts[:4] == ["OFF", "DATE", "LOGTO " + acct2, "WHO"], repr(got))
    row("CONTROL: nothing was written to the stacks directory of the account that was LOGTO'd to", not os.path.exists(os.path.join(acct2, "stacks")),
        repr(os.listdir(acct2)))

    # -------------------------------------------------------------------------------------------------------------
    say("\n--- E. 490: CATALOG ... LOCAL over a pointer to a different object file -----------------------------------")
    bp1 = os.path.join(SYS, "bp.out", "zzcl1")
    bp2 = os.path.join(SYS, "bp2.out", "zzcl1")
    out = sd(["DELETE.CATALOG zzcl1", "CATALOG bp zzcl1 LOCAL", "RUN bp zzclrd"])
    row("setup: the first CATALOG LOCAL makes the pointer to bp.out", has(out, r"^zzcl1 added to local catalogue") and (tagged(out, "CLREC") or "").endswith("bp.out/zzcl1"),
        repr(tagged(out, "CLREC")))
    out = sd(["CATALOG bp zzcl1 LOCAL", "CATALOG bp zzcl1 LOCAL", "RUN bp zzclrd"])
    row("CONTROL: the same object file again does not ask, and says it is added", not has(out, r"Replace it") and has(out, r"^zzcl1 added to local catalogue"), repr(out[-4:]))
    sd(["CATALOG bp zzcl1 LOCAL"])
    out = sd(["CATALOG bp2 zzcl1 LOCAL", "", "RUN bp zzclrd"])
    row("490: another object file asks, naming the pointer's path, and Return (N) leaves the pointer alone",
        has(out, r"^Local catalogue entry zzcl1 is for .*bp\.out/zzcl1\.\s+Replace it \(y/<n>\)\?") and not has(out, r"^zzcl1 added to local catalogue")
        and (tagged(out, "CLREC") or "").endswith("bp.out/zzcl1"), repr(out[-5:]))
    sd(["CATALOG bp zzcl1 LOCAL"])
    out = sd(["CATALOG bp2 zzcl1 LOCAL", "N", "RUN bp zzclrd"])
    row("... and N the same", (tagged(out, "CLREC") or "").endswith("bp.out/zzcl1") and not has(out, r"^zzcl1 added"), repr(out[-4:]))
    sd(["CATALOG bp zzcl1 LOCAL"])
    out = sd(["CATALOG bp2 zzcl1 LOCAL", "Y", "RUN bp zzclrd"])
    row("... Y replaces it: the pointer is to bp2.out and the entry is added", has(out, r"^zzcl1 added to local catalogue") and (tagged(out, "CLREC") or "").endswith("bp2.out/zzcl1"),
        repr(out[-4:]))
    sd(["CATALOG bp zzcl1 LOCAL"])
    out = sd(["CATALOG bp2 zzcl1 LOCAL NO.QUERY", "RUN bp zzclrd"])
    row("NO.QUERY goes ahead without asking, as it always did", not has(out, r"Replace it") and (tagged(out, "CLREC") or "").endswith("bp2.out/zzcl1"), repr(out[-4:]))
    sd(["DELETE.CATALOG zzcl1"])

    # -------------------------------------------------------------------------------------------------------------
    say("\n--- F. 268 and 320: ED ---------------------------------------------------------------------------------------")
    out = sd(["RUN bp zzedmk", "RUN bp zzedrd"])
    original = tagged(out, "F2")
    row("setup: the I-type's field 2 holds quoted text, brackets and semicolons: " + str(original),
        original == "\"p;q\":(r;s);'t;u'", repr(original))
    out = sd(["ED DICT zzedf zzedi", "G2", "EV", "P9", "SV", "FI", "RUN bp zzedrd"])
    ev_lines = [ln for ln in out if re.match(r"^\d{4}[:=] ", ln) or re.match(r"^\d{4}: ", ln)]
    row("268: EV, then SV and FI leave field 2 exactly as it was", tagged(out, "F2") == original, "%r  %r" % (tagged(out, "F2"), out[-8:]))
    row("268: in EV mode the I-type is split at the semicolons that are outside the quotes and the brackets: two lines",
        has(out, r"""^0001: "p;q":\(r;s\)$""") and has(out, r"""^0002: 't;u'$"""), repr(out[-9:]))

    mark = bytes([253]).decode("latin-1")
    raw = ("\nTERM 200,9999\nDELETE.FILE zzedf\nCREATE.FILE zzedf\nED zzedf zzedrec\nI a" + mark + "b\nI c\nFI\nRUN bp zzedrd2\nOFF\n").encode("latin-1")
    out = sd(["(bytes)"], raw=raw)
    row("320: a value mark typed in an I command is accepted without NPRINT: no 'non-printing characters' message, and the record has it",
        not has(out, r"non-printing") and tagged(out, "MARK") is not None and tagged(out, "MARK").startswith("1]["), repr(out[-5:]))
    fm = bytes([254]).decode("latin-1")
    raw = ("\nTERM 200,9999\nDELETE.FILE zzedf\nCREATE.FILE zzedf\nED zzedf zzedrec\nI a" + fm + "b\n" + "I ok\nFI\nRUN bp zzedrd2\nOFF\n").encode("latin-1")
    out = sd(["(bytes)"], raw=raw)
    row("CONTROL: a field mark is still refused (Command contains non-printing characters)", has(out, r"^Command contains non-printing characters"), repr(out[-5:]))
    raw = ("\nTERM 200,9999\nDELETE.FILE zzedf\nCREATE.FILE zzedf\nED zzedf zzedrec\nI\nx" + mark + "y\n\nFI\nRUN bp zzedrd2\nOFF\n").encode("latin-1")
    out = sd(["(bytes)"], raw=raw)
    row("320: ... and the same in the insert mode's own prompt: x<VM>y is accepted there",
        not has(out, r"non-printing") and tagged(out, "MARK") is not None and tagged(out, "MARK").startswith("1]["), repr(out[-6:]))
    raw = ("\nTERM 200,9999\nDELETE.FILE zzedf\nCREATE.FILE zzedf\nED zzedf zzedrec\nI\nx" + fm + "y\nz\n\nFI\nRUN bp zzedrd2\nOFF\n").encode("latin-1")
    out = sd(["(bytes)"], raw=raw)
    row("CONTROL: ... and a field mark is refused there (Data contains non-printing characters)", has(out, r"^Data contains non-printing characters"), repr(out[-6:]))
    sd(["DELETE.FILE zzedf"])

    say("\nsandbox-cmd-a9: %d passed, %d failed" % (passed, failed))
    if passed + failed == 0:
        bail("no row ran - a broken test, not a pass")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
