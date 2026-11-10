#!/usr/bin/env python3
"""test-tooltest-units.py - the test runner, TOOL.TEST (`gpl.bp/tool_test`), as invariants read off the source (S.75, development app DV7).  Free: no install, no sudo, no sd.

    python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/test-tooltest-units.py [--selftest]

WHAT THIS IS, AND WHAT IT IS NOT.  It reads the page's BASIC as text, with comments removed.  ***IT RUNS NOTHING, SO IT CANNOT SAY THAT A TEST IS RUN, THAT A VERDICT IS RIGHT OR THAT
CTRL-C STOPS ONE***: that is `sandbox-tool-test.py` (a private SD, ordinary sessions on a pseudo-terminal, the count of runs in a data file and an independent run as the evidence).
What a text check is for: the properties that make the page a FRONT END for an account holder - it is a USER app (any account, no administrator test), it opens the base before it reads
anything, the only commands it runs are `run` and `basic` and it runs them through the one place that runs commands, the compile is behind the box, a name goes into a command only when it
is made of the characters $tk_run lets through, the verdict rule keeps its shape, an abort is told by a message the page sets first, a test that asks for input is answered and the
leftovers discarded, the break key is on only while a test runs, and a long output is cut to its ends - which are mostly ORDER and ABSENCE, and an edit that moves one still compiles.

--selftest breaks each invariant in the way an edit plausibly would and requires a check to notice; a mutant that nothing catches is a failure of the self-test.
"""

import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SDSYS = os.path.normpath(os.path.join(HERE, "..", "sdsys"))
GPL = os.path.join(SDSYS, "gpl.bp")
FILES = {
    "page": os.path.join(GPL, "tool_test"),
    "voc": os.path.join(SDSYS, "voc_template", "tool.test"),
    "newvoc": os.path.join(SDSYS, "newvoc", "tool.test"),
    "help": os.path.join(SDSYS, "helptext", "tool.test.page"),
    "run": os.path.join(GPL, "tk_run"),
}
SAFE = "abcdefghijklmnopqrstuvwxyz0123456789._-"


def load():
    raw = {}
    for k, p in FILES.items():
        try:
            with open(p, encoding="latin-1") as f:
                raw[k] = f.read()
        except OSError:
            raw[k] = ""
    return raw


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


def nostr(text):
    """the code with the quoted text taken out, so that a word in a message is not read as a statement"""
    return re.sub(r"'[^'\n]*'|\"[^\"\n]*\"", "''", text)


def block(text, label):
    """The text of an internal subroutine: from its label to the next label at the start of a line (or to END)."""
    m = re.search(r"^" + re.escape(label) + r":\s*$", text, re.M)
    if not m:
        return ""
    n = re.search(r"^[a-z][a-z.0-9]*:\s*$|^end\s*$", text[m.end():], re.M)
    return text[m.start(): m.end() + (n.start() if n else len(text))]


def before(text, *needles):
    """every needle is in the text, and they come in the order given"""
    pos = [text.find(n) for n in needles]
    return all(p >= 0 for p in pos) and pos == sorted(pos) and len(set(pos)) == len(pos)


def checks(raw):
    rows = []

    def ck(i, what, ok, detail=""):
        rows.append((i, what, bool(ok), detail))

    pg = strip_bas(raw["page"])
    code = nostr(pg)
    rt = block(pg, "run.test")
    ss = block(pg, "set.sentinel")
    jd = block(pg, "judge")
    pv = block(pg, "parse.verdict")
    so = block(pg, "store.output")
    cl = block(pg, "clean.line")
    dr = block(pg, "do.run")
    dm = block(pg, "do.many")
    dc = block(pg, "do.compile")
    sf = block(pg, "scan.file")
    ra = block(pg, "read.all")
    cn = block(pg, "check.names")
    ok_ = block(pg, "out.key")
    ck("TT0", "NULL CASE: the page, both VOC entries, the help record and $tk_run were found and are not empty, and every routine this check cuts out of the page is there (a check on nothing would pass)",
       len(pg) > 15000 and raw["voc"].strip() != "" and raw["newvoc"].strip() != "" and len(raw["help"].split("\n")) >= 4 and len(raw["run"]) > 500
       and all(len(b) > 40 for b in (rt, ss, jd, pv, so, cl, dr, dm, dc, sf, ra, cn, ok_)), "%d" % len(pg))
    ck("TT1", "the page is an internal program catalogued as $tool_test, and EVERY account has it as a verb: newvoc and SDSYS's VOC both run that program",
       re.search(r"^\$internal\s*\nprogram \$tool_test\s*\n\$catalog \$tool_test\b", pg, re.M) is not None and raw["voc"].split("\n")[:3] == ["V", "CA", "$tool_test"]
       and raw["newvoc"].split("\n")[1:3] == ["CA", "$tool_test"] and raw["newvoc"].startswith("Verb - "), repr((raw["voc"][:30], raw["newvoc"][:60])))
    op = pg.find("call $tk_open('tool.test', '', ctx, err)")
    ck("TT2", "it is a USER app: the base is opened with no audience (an account holder is never refused for being one) and BEFORE anything is read, asked or run - the VOC, a file, a gate, a command",
       0 <= op < pg.find("open 'VOC'") and op < pg.find("kernel(K$") and op < pg.find("call $tk_run(") and "'admin'" not in pg and "K$ADMINISTRATOR" not in pg
       and "if err # '' then\n      display err\n      stop" in pg, op)
    ck("TT3", "the only commands it can run are two words declared once at the top (run, basic), run ONLY through $tk_run - once for a test and once for the compile - and no statement of the page executes anything itself",
       re.findall(r"(?<![.\w])allow = '([^']*)'", pg) == ["run basic"] and pg.count("call $tk_run(allow, sent, out, stat, rerr)") == 2 and "call $tk_run(allow, sent, out, stat, rerr)" in rt
       and "call $tk_run(allow, sent, out, stat, rerr)" in dc and not re.search(r"^\s*(execute|perform|chain|enter)\b", code, re.M) and "$tk_runx" not in pg
       and "sent = 'run ' : zfl : ' ' : zid" in rt and "sent = 'basic ' : zfl : ' ' : zid" in dc, "")
    opens = re.findall(r"^\s*open (.+?) to \w+ then", pg, re.M)
    ck("TT4", "the page writes nothing and writes no audit line: no write, delete, clearfile, osdelete, oswrite, rename or logto statement, no kernel(K$AUDIT, ...), the results live in two dimensioned arrays in memory, and it opens only the VOC, a program file and its .out file",
       not re.search(r"^\s*(write|writev|writet|delete|clearfile|osdelete|oswrite|rename|logto|writeseq|openseq)\b", code, re.M) and "K$AUDIT" not in pg
       and "dim rz(500)" in pg and "dim oz(500)" in pg and sorted(opens) == sorted(["'VOC'", "fn", "fn : '.out'"]), repr(opens))
    ck("TT5", "the compile is behind the box: the name is checked first, then the box shows the command (it asks no typed name - nothing is destroyed), and only an answer of Run goes on to $tk_run",
       before(dc, "case tok<ri> = 0", "call $tk_confirm(sent, lines, '', cres, cmsg)", "if cres # 'run' then\n      msg = cmsg\n      return\n   end", "call $tk_run(allow, sent, out, stat, rerr)")
       and "case tobj<ri> = 1" in dc and dc.find("case tobj<ri> = 1") < dc.find("call $tk_confirm"), "")
    ck("TT6", "a name goes into a command only when it is made of the characters $tk_run lets through (the same list, at most 63 long, program file and test both), decided once when the list is read; R, B and A each refuse a name that is not, and A leaves out a test with no object code",
       "good = '%s'" % SAFE in cn and ("good = '%s'" % SAFE) in raw["run"] and "len(zfl) <= 63 and" in cn and "and len(zid) <= 63)" in cn and "okname = @false" in cn
       and before(sf, "zfl = fn", "gosub check.names", "tok<nt> = (if okname then 1 else 0)") and pg.count("gosub run.test") == 2
       and before(dr, "case tok<ri> = 0", "case tobj<ri> = 0", "gosub run.test") and before(dm, "case tobj<ri> = 0", "case tok<ri> = 0", "queue<-1> = zk", "gosub run.test"),
       "")
    ck("TT7", "the verdict rule keeps its shape: the line holds ' passed, ', the word before it is a number and anything in front of that ends in a colon and a space, the word after it is a number followed by failed, and a failure is judged BEFORE a pass, which needs a passed count above 0",
       "zp1 = index(v, ' passed, ', 1)" in pv and pv.count("matches '1N0N'") == 2 and "if v.pre[len(v.pre) - 1, 2] # ': ' then return" in pv and "if w3[1, 6] # 'failed' then return" in pv
       and "if index(',.;)', w4, 1) = 0 then return" in pv and before(jd, "v = lastl", "gosub parse.verdict", "case nf > 0\n                  zstate = 'fail'", "case np > 0\n                  zstate = 'pass'"), "")
    ck("TT8", "an abort is told by the system's message: the page sets a message of its own (a caught division by zero) BEFORE the test runs, and the test aborted when nothing was captured and the message is no longer that one; a test that printed something is never called aborted",
       before(rt, "gosub set.sentinel", "call $tk_run(") and "try\n      sentv = 1 / zero\n   catch sys.program.div_zero\n      sentinel = @abort.message\n   end" in ss
       and "if out = '' then\n      if @abort.message # sentinel then\n         zstate = 'fail'\n         abm = @abort.message" in jd and "      zt = field(out, @fm," in jd, "")
    ck("TT9", "a test that asks for input is answered, not waited for: ANSWERS empty answers are stacked BEFORE the command, the leftovers are counted and then discarded AFTER it, the count is what the box says, and keys typed during a run are discarded",
       "ANSWERS = 50" in pg and before(rt, "for za = 1 to ANSWERS\n      data ''\n   next za", "call $tk_run(", "zleft = len(@data.pending)", "cleardata") and "used = ANSWERS - zleft" in rt
       and "clearinput" in dr and "clearinput" in dm, "")
    ck("TT10", "the break key is on only while a test runs: turned on (the terminal's and the program's) just before the command, turned off again just after, and the nesting count is put back to what it was",
       before(rt, "bc0 = break.count()", "void pterm(PT$BREAK, @true)\n   break on", "call $tk_run(", "break off\n   void pterm(PT$BREAK, @false)", "loop while break.count() < bc0", "loop while break.count() > bc0")
       and "Ctrl-C then Q stops a test that does not end" in rt, "")
    nums = re.search(r"KEEP = (\d+) ; HEADN = (\d+) ; TAILN = (\d+) ; LINEW = (\d+)", pg)
    ck("TT11", "a long output is cut to its ends and the verdict is judged on all of it: KEEP lines are kept whole, else the first HEADN, one marker line and the last TAILN (they add up to KEEP), each line cut to LINEW and made safe to show; the kept lines are what Enter shows, the full capture is what is judged",
       nums is not None and int(nums.group(2)) + 1 + int(nums.group(3)) == int(nums.group(1)) and "field(out, @fm, 1, HEADN)" in so and "field(out, @fm, nl - TAILN + 1, TAILN)" in so and "' lines left out ...'" in so
       and "zs = zs[1, LINEW]" in so and "zs = convert(char(13), '', zs)" in cl and "zs = change(zs, char(9), '    ')" in cl and "zs = convert(ctl, dots, zs)" in cl
       and "kept" not in jd and before(rt, "gosub judge", "gosub store.output", "oz(rp) = kept"), "")
    ck("TT12", "the one gate the page shows - bp-edit, which compiling needs - is ASKED of the kernel (with -1) in the summary and in the compile box, and nothing else is asked or tried",
       "kernel(K$BP.EDIT, -1)" in block(pg, "draw.foot") and "kernel(K$BP.EDIT, -1)" in dc and set(re.findall(r"\bK\$[A-Z.]+", pg)) == {"K$BP.EDIT"}, "")
    ck("TT13", "the tests are the records that start with test. (any case) of the program files of the account: directory files called bp, ending .bp, or with a file of the same name and .out beside them (a name that ends .out is never one), and a test has object code when its lower-case name is in that .out file",
       before(sf, "if sfx # '.out' then", "if lfn = 'bp' then cand = @true", "if sfx = '.bp' then cand = @true", "locate fn : '.out' in fids<1> setting zp then", "if fileinfo(zf, FL$TYPE) = FL$TYPE.DIR then",
              "if downcase(zid[1, 5]) = 'test.' then ztests<-1> = zid", "open fn : '.out' to zof then", "locate downcase(zid) in zobj<1> setting zp then")
       and "if t1 = 'F' or t1[1, 5] = 'FILE ' then fids<-1> = ids<i>" in ra, "")
    ck("TT14", "a letter is the same key in either case, every key the page acts on has a place in the key table (the function-key row shows exactly the keys it uses), and Esc is the Output pane's own",
       "if len(nm) = 1 then nm = downcase(nm)" in pg and all(("call $tk_keys('add', keys, '%s'," % k) in pg for k in ("f1", "r", "a", "f", "b", "enter", "/", "esc", "f5", "ctrl-q"))
       and "call $tk_keys('add', keys, 'esc', 'tests', 'back', 'Output', 1)" in pg
       and all(("case nm = '%s'" % k) in block(pg, "on.key") for k in ("r", "a", "f", "b", "enter", "f5", "ctrl-q")), "")
    ck("TT15", "the layout fits the 140 by 43 frame (S.88 L2: the two boxes are the layout service's panes, declared 22 and 17 rows by 138 and drawn from their rectangles; the numbers at 140 by 43 are "
               "test-l2-files-units.py's): two boxes (rows 1-22 and 23-39), 16 rows of tests (the list's height less 6) at the list's y + 2, the summary and the hint on its last interior rows, the lower box (detail or output) "
               "on its interior rows with VISO its height less 2; nothing is drawn on a border",
       "d<1> = 'list' : @vm : 1 : @vm : 1 : @vm : 22 : @vm : 138 :" in pg and "d<2> = 'detail' : @vm : 2 : @vm : 1 : @vm : 17 : @vm : 138 :" in pg
       and "screen box at lx,ly size lw,lh title ttl" in pg and "screen box at dx,dy size dw,dh title 'The test under the cursor'" in pg and "screen box at dx,dy size dw,dh title ottl" in pg
       and "VIS = lh - 6" in pg and "VISO = dh - 2" in pg
       and "for r = 1 to dh - 2" in block(pg, "draw.detail") and "at dx + 2,dy + r width tw" in block(pg, "draw.detail") and "for r = 1 to VISO" in block(pg, "draw.output") and "at dx + 2,dy + r width tw" in block(pg, "draw.output")
       and "at lx + 2,ly + lh - 4 attr 'bold' width tw" in pg and "at lx + 2,ly + lh - 3 width tw" in pg, "")
    ck("TT16", "the page waits on the keyboard only through the base: the key read is screen key (the cursor lock and the end of the input are the library's), the end of the input ends it, the base is closed on the way out, and A looks for Esc between tests (keyready, then screen key) so it can stop after the one that is running",
       "screen key returning nm" in pg and "if status() = ER$EOF then exit" in pg and "case nm = 'guardquit'\n            exit" in pg and pg.find("call $tk_close(ctx)") > pg.find("repeat")
       and before(dm, "gosub run.test", "if keyready() then", "screen key timeout 1 returning zkey", "if zkey = 'esc' then", "stopped = zj"), "")
    ck("TT17", "the help record names a page of the documentation, and the page asks for it by that name from F1, ?, a click on [?] and the Output pane",
       pg.count("call $tk_help('box', 'tool.test.page', hm, 0, 0)") == 3 and re.match(r"^[^\n]{1,60}\n[0-9a-z-]+\n", raw["help"]) is not None and "passed, 0 failed" in raw["help"] and "test." in raw["help"], repr(raw["help"][:60]))
    ck("TT18", "the test that is running is shown as running BEFORE it starts (the base's status line and the list are drawn first, so a long test is not a frozen screen), and the mark is taken off after",
       before(rt, "running.ri = ri", "msg = mrun : 'running ' : sent", "call $tk_frame(ctx, keys, pn, msg)", "gosub draw.list", "call $tk_run(", "running.ri = 0"), "")
    ck("TT19", "the lines of an output scroll inside their limits (never above the first line or below the last page), each key redrawing only the box",
       "ozmax = nv - VISO" in ok_ and "if ot > 0 then ot -= 1" in ok_ and "if ot < ozmax then ot += 1" in ok_ and "if ot < 0 then ot = 0" in ok_ and "if ot > ozmax then ot = ozmax" in ok_, "")
    ck("TT20", "the results of the session are kept per test (file and name), a test that was already listed keeps its place when the files are read again, and the store starts again when it is full",
       "fkey = tfile<ri> : '/' : tid<ri>" in block(pg, "find.result") and "locate fkey in rkeys<1> setting fzp then rp = fzp" in block(pg, "find.result") and "if dcount(rkeys, @fm) >= 500 then" in block(pg, "make.result")
       and "keep.k = tfile<shown<ci>> : '/' : tid<shown<ci>>" in ra and "if keep.k # '' then" in ra and "if tfile<shown<zi>> : '/' : tid<shown<zi>> = keep.k then ci = zi" in ra, "")
    ck("TT21", "A and F ask first (one key starts up to 500 programs, some perhaps put in a shared program file by another member): do.many shows the count and the first commands in a $tk_confirm box, Cancel is the default, and nothing runs before the box answers Run; R, one test, is the same as typing run and has no box",
       before(dm, "nq = dcount(queue, @fm)", "call $tk_confirm(sent, lines, '', cres, cmsg)", "if cres # 'run' then\n      msg = cmsg\n      return\n   end", "m.pass = 0 ; m.fail = 0", "gosub run.test")
       and "lines<-1> = '  run ' : tfile<zri2> : ' ' : tid<zri2>" in dm and "$tk_confirm" not in dr, "")
    ck("TT22", "the two texts that came from outside the page are cleaned before they are shown: the compiler's last line (carriage return, tab and every control character, then cut to 120) and the message of an abort (cut to 200), by clean.line",
       "zs = out<zq>\n      gosub clean.line" in dc and "zlast = trim(zs)[1, 120]" in dc and "zs = abm ; gosub clean.line ; abm = zs[1, 200]" in rt, "")
    ck("TT23", "the output pane of the runs (Ctrl-O): the open layout (rows named lo, made from the page's own d rows; the list 16 rows, the pane 6, the lower box as it was one band lower = 39) is declared only while it is open, the bar is given outopen with the filter as BUSY, Esc closes it first in either pane, Ctrl-PgUp / Ctrl-PgDn scroll it, and each run's answer (or its refusal) is added",
       "lo<1> = d<1> ; lo<1, 4> = 16" in pg and "lo<2> = d<2> ; lo<2, 1> = 'output' ; lo<2, 2> = 2 ; lo<2, 4> = 6" in pg and "lo<3> = d<2> ; lo<3, 2> = 3" in pg and "      d = lo\n" in pg
       and "busy = (if filt # '' or outopen then 1 else 0)" in pg and "case nm = 'esc' and outopen\n         gosub toggle.out" in pg and "case (nm = 'ctrl-pgup' or nm = 'ctrl-pgdn') and outopen" in pg
       and pg.count("call $tk_out('add'") == 2 and "if outopen then call $tk_out('draw', ctx, 'output', '', oc)" in pg and "case nm = 'ctrl-o'\n         gosub toggle.out" in pg)
    return rows


def sub(key, old, new):
    def f(raw):
        r = dict(raw)
        if old not in r[key]:
            raise KeyError("%s: %r is not in the file, so the mutant cannot be made" % (key, old[:60]))
        r[key] = r[key].replace(old, new, 1)
        return r
    return f


def setkey(key, val):
    def f(raw):
        r = dict(raw)
        r[key] = val
        return r
    return f


def both(*fs):
    def f(raw):
        r = raw
        for g in fs:
            r = g(r)
        return r
    return f


TK_RUN = "call $tk_run(allow, sent, out, stat, rerr)"
MUTANTS = [
    ("the bar is not told the output pane is open", "TT23", sub("page", "busy = (if filt # '' or outopen then 1 else 0)", "busy = (if filt # '' then 1 else 0)")),
    ("Esc does not close the output pane", "TT23", sub("page", "case nm = 'esc' and outopen\n         gosub toggle.out", "case nm = 'esc' and 0\n         gosub toggle.out")),
    ("the pane is as tall as the list lost", "TT23", sub("page", "lo<2, 4> = 6", "lo<2, 4> = 7")),
    ("a run's answer is not kept", "TT23", sub("page", "      call $tk_out('add', ctx, okind, otext, '')", "      otext = otext")),
    ("the pane is not drawn", "TT23", sub("page", "   if outopen then call $tk_out('draw', ctx, 'output', '', oc)", "   oc = ''")),
    ("A and F run without asking", "TT21", sub("page", "   call $tk_confirm(sent, lines, '', cres, cmsg)\n   if cres # 'run' then\n      msg = cmsg\n      return\n   end\n   m.pass = 0", "   m.pass = 0")),
    ("A and F run whatever the box answered", "TT21", sub("page", "   call $tk_confirm(sent, lines, '', cres, cmsg)\n   if cres # 'run' then\n      msg = cmsg\n      return\n   end\n   m.pass = 0", "   call $tk_confirm(sent, lines, '', cres, cmsg)\n   m.pass = 0")),
    ("R asks too", "TT21", sub("page", "         mrun = ''\n         gosub run.test\n", "         mrun = ''\n         call $tk_confirm(sent, lines, '', cres, cmsg)\n         gosub run.test\n")),
    ("the compiler's last line is shown raw", "TT22", sub("page", "      zs = out<zq>\n      gosub clean.line", "      zs = out<zq>")),
    ("the abort message is shown raw", "TT22", sub("page", "      zs = abm ; gosub clean.line ; abm = zs[1, 200]            ;* the abort message can be a test's own text\n", "")),
    ("the page is opened for the administrator only", "TT2", sub("page", "call $tk_open('tool.test', '', ctx, err)", "call $tk_open('tool.test', 'admin', ctx, err)")),
    ("the page reads the VOC before it opens the base", "TT2", sub("page", "   call $tk_open('tool.test', '', ctx, err)\n", "   open 'VOC' to vocx then close vocx\n   call $tk_open('tool.test', '', ctx, err)\n")),
    ("an ordinary account has no verb", "TT1", setkey("newvoc", "")),
    ("SDSYS's verb runs another program", "TT1", sub("voc", "$tool_test", "$tool_keys")),
    ("the page may run another command", "TT3", sub("page", "allow = 'run basic'", "allow = 'run basic sh'")),
    ("the page may no longer compile", "TT3", sub("page", "allow = 'run basic'", "allow = 'run'")),
    ("the page runs a command itself", "TT3", sub("page", TK_RUN + "\n   t1 = time()", "execute sent capturing out\n   t1 = time()")),
    ("the compile uses the looser runner", "TT3", sub("page", TK_RUN + "\n   if rerr # '' then\n      msg = rerr\n      return", "call $tk_runx(allow, sent, out, stat, rerr)\n   if rerr # '' then\n      msg = rerr\n      return")),
    ("the page runs a second execute statement", "TT3", sub("page", "   ttl = 'Tests in ' : @who\n", "   ttl = 'Tests in ' : @who\n   execute 'sh'\n")),
    ("the page writes a record", "TT4", sub("page", "   ttl = 'Tests in ' : @who\n", "   ttl = 'Tests in ' : @who\n   write 'x' on vocx, 'y'\n")),
    ("the page deletes a record", "TT4", sub("page", "   ttl = 'Tests in ' : @who\n", "   ttl = 'Tests in ' : @who\n   delete vocx, 'y'\n")),
    ("the page writes an audit line", "TT4", sub("page", "   ttl = 'Tests in ' : @who\n", "   ttl = 'Tests in ' : @who\n   void kernel(K$AUDIT, 'tool test')\n")),
    ("the page opens another file", "TT4", sub("page", "      open fn to zf then\n", "      open fn to zf then\n         open 'sd.accounts' to zx then close zx\n")),
    ("the compile does not ask", "TT5", sub("page", "   call $tk_confirm(sent, lines, '', cres, cmsg)\n   if cres # 'run' then\n      msg = cmsg\n      return\n   end\n   gosub make.result", "   gosub make.result")),
    ("the compile runs whatever the box answered", "TT5", sub("page", "   if cres # 'run' then\n      msg = cmsg\n      return\n   end\n   gosub make.result", "   gosub make.result")),
    ("the compile box is shown before the name is checked", "TT5", sub("page", "      case tok<ri> = 0\n         msg = 'this name has a character the page does not give to a command: type basic '", "      case tok<ri> = 99\n         msg = 'this name has a character the page does not give to a command: type basic '")),
    ("R does not check the name", "TT6", sub("page", "      case tok<ri> = 0\n         msg = 'this name has a character the page does not give to a command: type run '", "      case tok<ri> = 99\n         msg = 'this name has a character the page does not give to a command: type run '")),
    ("the name list lets a dollar through", "TT6", sub("page", "good = 'abcdefghijklmnopqrstuvwxyz0123456789._-'", "good = 'abcdefghijklmnopqrstuvwxyz0123456789._-$'")),
    ("the name length is not limited", "TT6", sub("page", "len(zid) <= 63", "len(zid) <= 6300")),
    ("every name is taken as safe when the list is read", "TT6", sub("page", "tok<nt> = (if okname then 1 else 0)", "tok<nt> = 1")),
    ("A queues a name the page does not give to a command", "TT6", sub("page", "         case tok<ri> = 0\n            if zmode = 'all' then skipn += 1", "         case tok<ri> = 99\n            if zmode = 'all' then skipn += 1")),
    ("A queues a test with no object code", "TT6", sub("page", "         case tobj<ri> = 0\n            if zmode = 'all' then skipo += 1", "         case tobj<ri> = 99\n            if zmode = 'all' then skipo += 1")),
    ("R runs a test with no object code", "TT6", sub("page", "      case tobj<ri> = 0\n         msg = 'no object code for '", "      case tobj<ri> = 99\n         msg = 'no object code for '")),
    ("a pass is judged before a failure", "TT7", sub("page", "               case nf > 0\n                  zstate = 'fail'\n               case np > 0\n                  zstate = 'pass'\n", "               case np > 0\n                  zstate = 'pass'\n               case nf > 0\n                  zstate = 'fail'\n")),
    ("0 passed counts as a pass", "TT7", sub("page", "               case np > 0\n", "               case np >= 0\n")),
    ("anything may come before the numbers", "TT7", sub("page", "      if v.pre[len(v.pre) - 1, 2] # ': ' then return\n", "      null\n")),
    ("the word failed is not required", "TT7", sub("page", "   if w3[1, 6] # 'failed' then return\n", "")),
    ("the passed word is another", "TT7", sub("page", "index(v, ' passed, ', 1)", "index(v, ' passes, ', 1)")),
    ("an abort is told by any message", "TT8", sub("page", "      if @abort.message # sentinel then\n         zstate = 'fail'", "      if @abort.message # '' then\n         zstate = 'fail'")),
    ("an abort is looked for when the test printed something", "TT8", sub("page", "   if out = '' then\n      if @abort.message # sentinel then", "   if 1 then\n      if @abort.message # sentinel then")),
    ("the page's own message is set after the run", "TT8", both(sub("page", "   gosub set.sentinel\n   for za = 1 to ANSWERS", "   for za = 1 to ANSWERS"), sub("page", "   t1 = time()\n   break off", "   t1 = time()\n   gosub set.sentinel\n   break off"))),
    ("the page's own message is not set by a division", "TT8", sub("page", "      sentv = 1 / zero\n", "      sentv = 0\n")),
    ("no answers are stacked for a test that asks for input", "TT9", sub("page", "   for za = 1 to ANSWERS\n      data ''\n   next za\n", "")),
    ("the leftover answers are not discarded", "TT9", sub("page", "   cleardata\n", "")),
    ("the answers used are not counted", "TT9", sub("page", "used = ANSWERS - zleft", "used = 0")),
    ("keys typed during a run are kept", "TT9", sub("page", "         gosub run.test\n         clearinput", "         gosub run.test\n         null")),
    ("the break key is not turned on for the run", "TT10", sub("page", "   void pterm(PT$BREAK, @true)\n   break on\n", "")),
    ("the break key is left on after the run", "TT10", sub("page", "   break off\n   void pterm(PT$BREAK, @false)\n   zbn = 0", "   zbn = 0")),
    ("the break count is not put back", "TT10", sub("page", "   loop while break.count() > bc0 and zbn < 10 do\n      break on\n      zbn += 1\n   repeat\n", "")),
    ("the verdict is judged on the kept lines", "TT11", sub("page", "      zt = field(out, @fm, (if nl > 50 then nl - 49 else 1), 50)", "      zt = field(kept, @fm, (if nl > 50 then nl - 49 else 1), 50)")),
    ("an output is never cut", "TT11", sub("page", "KEEP = 400 ;", "KEEP = 400000 ;")),
    ("the head and the tail do not add up", "TT11", sub("page", "TAILN = 39", "TAILN = 30")),
    ("a long line is not cut", "TT11", sub("page", "         zs = zs[1, LINEW]\n", "")),
    ("control characters are shown as they are", "TT11", sub("page", "   zs = convert(ctl, dots, zs)\n", "")),
    ("the bp-edit gate is not asked", "TT12", sub("page", "(if kernel(K$BP.EDIT, -1) then 'on' else 'off') : ' (B compiles)'", "'on' : ' (B compiles)'")),
    ("another gate is asked", "TT12", sub("page", "   s := '.   Your gate:  bp-edit '", "   if kernel(K$VOC.EDIT, -1) then s := ' '\n   s := '.   Your gate:  bp-edit '")),
    ("every directory file is a program file", "TT13", sub("page", "      if lfn = 'bp' then cand = @true\n      if sfx = '.bp' then cand = @true\n", "      cand = @true\n")),
    ("a file that is not a directory file is read", "TT13", sub("page", "         if fileinfo(zf, FL$TYPE) = FL$TYPE.DIR then", "         if 1 then")),
    ("a record that starts with test is a test", "TT13", sub("page", "if downcase(zid[1, 5]) = 'test.' then", "if downcase(zid[1, 4]) = 'test' then")),
    ("the object code is looked for under the test's own case", "TT13", sub("page", "locate downcase(zid) in zobj<1> setting zp then", "locate zid in zobj<1> setting zp then")),
    ("a key is missing from the key table", "TT14", sub("page", "   call $tk_keys('add', keys, 'b', 'compile', 'compile', 'Tests', 1)\n", "")),
    ("a capital R is not a key", "TT14", sub("page", "   if len(nm) = 1 then nm = downcase(nm)", "   if len(nm) = 99 then nm = downcase(nm)")),
    ("Esc is a key of every pane", "TT14", sub("page", "'esc', 'tests', 'back', 'Output', 1)", "'esc', 'tests', 'back', '', 1)")),
    ("the detail overruns the border", "TT15", sub("page", "   for r = 1 to dh - 2\n", "   for r = 1 to dh - 1\n")),
    ("the first box overlaps the second", "TT15", sub("page", "d<1> = 'list' : @vm : 1 : @vm : 1 : @vm : 22 : @vm : 138 :", "d<1> = 'list' : @vm : 1 : @vm : 1 : @vm : 23 : @vm : 138 :")),
    ("the end of the input is not seen", "TT16", sub("page", "            if status() = ER$EOF then exit\n", "")),
    ("the page waits with no key reader of the library", "TT16", sub("page", "screen key returning nm", "input nm,1")),
    ("A does not look for Esc", "TT16", sub("page", "         if keyready() then\n            zkey = ''", "         if 0 then\n            zkey = ''")),
    ("the help key names a record that does not exist", "TT17", sub("page", "      case nm = 'f1' or nm = '?'\n         call $tk_help('box', 'tool.test.page', hm, 0, 0)\n         if hm # '' then msg = hm\n      case nm = 'f5'\n         gosub read.all\n         gosub draw.all",
                                                                 "      case nm = 'f1' or nm = '?'\n         call $tk_help('box', 'tool.test.nopage', hm, 0, 0)\n         if hm # '' then msg = hm\n      case nm = 'f5'\n         gosub read.all\n         gosub draw.all")),
    ("the help record has no verdict line in it", "TT17", lambda raw: dict(raw, help=raw["help"].replace("passed, 0 failed", "passed"))),
    ("the running test is not marked before it starts", "TT18", sub("page", "   running.ri = ri\n   msg = mrun", "   msg = mrun")),
    ("the list is not drawn before the test starts", "TT18", sub("page", "   call $tk_frame(ctx, keys, pn, msg)\n   gosub draw.list\n   call $sl_curat(0, ctx<TK.C.YSTAT>)\n   gosub set.sentinel", "   gosub set.sentinel")),
    ("the output scrolls past its last page", "TT19", sub("page", "         if ot < ozmax then ot += 1", "         ot += 1")),
    ("the output scrolls above its first line", "TT19", sub("page", "         ot -= VISO\n         if ot < 0 then ot = 0\n", "         ot -= VISO\n")),
    ("a result belongs to the test's name alone", "TT20", sub("page", "fkey = tfile<ri> : '/' : tid<ri>", "fkey = tid<ri>")),
    ("the cursor does not go back to its test after F5", "TT20", sub("page", "   if ns > 0 and ci >= 1 and ci <= ns then keep.k = tfile<shown<ci>> : '/' : tid<shown<ci>>\n", "")),
]


def report(rows):
    bad = 0
    for i, what, ok, detail in rows:
        print("  [%s] %s %s%s" % ("PASS" if ok else "FAIL", i, what, "" if ok or not detail else "   <- " + str(detail)[:200]))
        bad += 0 if ok else 1
    return bad


def selftest(raw):
    base = [r[0] for r in checks(raw) if not r[2]]
    if base:
        print("selftest: the unchanged tree fails %s, so a mutant's own failure cannot be told from the tree's; run the plain check first" % base)
        return 1
    holes = 0
    for name, want, mut in MUTANTS:
        try:
            m = mut(raw)
        except KeyError as exc:
            print("  [FAIL] selftest: %s  <- %s" % (name, exc))
            holes += 1
            continue
        failed = sorted({r[0] for r in checks(m) if not r[2]})
        hit = want in failed
        print("  [%s] selftest: %s is caught by %s (failed: %s)" % ("PASS" if hit else "FAIL", name, want, " ".join(failed) or "none"))
        holes += 0 if hit else 1
    print("selftest: %d mutants, %d not caught" % (len(MUTANTS), holes))
    return 1 if holes else 0


def main(argv):
    raw = load()
    print("test-tooltest-units: tree %s" % os.path.dirname(GPL))
    if not raw["page"]:
        print("test-tooltest-units: CANNOT RUN - %s is not there" % FILES["page"])
        return 2
    rows = checks(raw)
    bad = report(rows)
    print("\ntest-tooltest-units: %d passed, %d failed" % (len(rows) - bad, bad))
    rc = 1 if bad else 0
    if "--selftest" in argv:
        rc = (selftest(raw) or rc)
    return rc


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
