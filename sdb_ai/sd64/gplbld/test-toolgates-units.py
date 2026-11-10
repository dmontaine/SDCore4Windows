#!/usr/bin/env python3
"""test-toolgates-units.py - the gate matrix, TOOL.GATES (`gpl.bp/tool_gates`), as invariants read off the source (S.75, administrator app A2).  Free: no install, no sudo, no sd.

    python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/test-toolgates-units.py [--selftest [--from=N]]

TG18-TG20 (2 Nov 26, S.88 p5-U2b P10): Ctrl-Q asks before it drops a queue; the first of their mutants is M_P10 (37), so --selftest --from=37 runs only those.

WHAT THIS IS, AND WHAT IT IS NOT.  It reads the page's BASIC as text, with comments removed.  ***IT RUNS NOTHING, SO IT CANNOT SAY THAT A CELL CHANGES OR THAT THE VERB ACCEPTS WHAT THE PAGE
SENDS***: that is `sandbox-tool-gates.py` (a private SD, the real modify.account, the disk as the evidence).  What a text check is for: the properties that make the page a FRONT END and
not a second wall - it opens the base for the administrator before it reads anything, it runs one command through the one place that runs commands, it writes no file, its all-on and all-off keys
(A, N; 1 Nov 2026) only QUEUE and only what a single cell could, a gate that reaches beyond SD is not turned on without the account's name being typed, and the words it sends come from the gate table - are mostly ORDER and ABSENCE,
and an edit that moves one still compiles.

--selftest breaks each invariant in the way an edit plausibly would and requires a check to notice; a mutant that nothing catches is a failure of the self-test.
"""

import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SDSYS = os.path.normpath(os.path.join(HERE, "..", "sdsys"))
GPL = os.path.join(SDSYS, "gpl.bp")
FILES = {
    "page": os.path.join(GPL, "tool_gates"),
    "info": os.path.join(GPL, "tk_gate_info"),
    "voc": os.path.join(SDSYS, "voc_template", "tool.gates"),
    "newvoc": os.path.join(SDSYS, "newvoc", "tool.gates"),
    "help": os.path.join(SDSYS, "helptext", "tool.gates.matrix"),
}


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


def block(text, label, until=None):
    """The text of an internal subroutine: from its label to the next label at the start of a line (or to END)."""
    m = re.search(r"^" + re.escape(label) + r":\s*$", text, re.M)
    if not m:
        return ""
    n = re.search(r"^[a-z][a-z.]*:\s*$|^end\s*$", text[m.end():], re.M)
    return text[m.start(): m.end() + (n.start() if n else len(text))]


def checks(raw):
    rows = []

    def ck(i, what, ok, detail=""):
        rows.append((i, what, bool(ok), detail))

    pg = strip_bas(raw["page"])
    info_rows = [r.split("|") for r in re.findall(r'rows<-1> = "([^"]*)"', raw["info"])]
    built = [r for r in info_rows if len(r) == 15 and r[14] == "built"]

    ck("TG0", "NULL CASE: the page, the gate table and the VOC entry were found and are not empty (a check on nothing would pass)", len(pg) > 9000 and len(info_rows) >= 12 and raw["voc"].strip() != "" and len(raw["help"]) > 200,
       "%d %d" % (len(pg), len(info_rows)))
    ck("TG1", "the page is an internal program catalogued as $tool_gates, SDSYS's VOC has it as a verb for that program, and the shared VOC (newvoc) does not: its verb of that name runs the account holder's page, $tool_mygates (24 Oct 26)",
       re.search(r"^\$internal\s*\nprogram \$tool_gates\s*\n\$catalog \$tool_gates\b", pg, re.M) is not None and raw["voc"].split("\n")[:3] == ["V", "CA", "$tool_gates"]
       and "$tool_gates" not in raw["newvoc"].split("\n") and "$tool_mygates" in raw["newvoc"].split("\n"), repr((raw["voc"][:30], raw["newvoc"][:80])))
    i_open = pg.find("call $tk_open('tool.gates', 'admin', ctx, err)")
    i_read = pg.find("openpath @sdsys:@ds:'accounts'")
    i_audit = pg.find("kernel(K$AUDIT, 'tool start app=tool.gates')")
    ck("TG2", "it opens the toolkit's base for the ADMINISTRATOR first (a refusal is shown and the program stops), before it reads anything or writes its audit line; the audit line is the only one and has no other kernel(K$AUDIT",
       0 < i_open < i_audit < i_read and re.search(r"call \$tk_open\('tool\.gates', 'admin', ctx, err\)\s*\n\s*if err # '' then\s*\n\s*display err\s*\n\s*stop\s*\n\s*end", pg) is not None and pg.count("K$AUDIT") == 1,
       "open %s, audit %s, read %s" % (i_open, i_audit, i_read))
    ck("TG3", "it runs ONE command, modify.account, through $tk_run and nowhere else: one allow list, one call of $tk_run guarded by res = 'run', no execute, os.execute, perform or chain, and the page writes no file and deletes no record",
       re.findall(r"\ballow = '([^']*)'", pg) == ["modify.account"] and pg.count("call $tk_run(allow, sent, out, stat, err)") == 1 and not re.search(r"^\s*(?:execute|os\.execute|perform|chain|write[uv]?|delete[uv]?|matwrite)\b", pg, re.M) and not re.search(r"\b(?:execute|perform)\s+[a-z']", pg)
       and re.search(r"call \$tk_confirm\(sent, el, typed, res, cmsg\)\s*\n\s*if res = 'run' then\s*\n\s*call \$tk_run\(allow, sent, out, stat, err\)", pg) is not None)
    mk = block(pg, "make.sentence")
    ck("TG4", "the sentence is 'modify.account ' + the account's name from the register + the words: a gate's own on or off word from the table, or one of the four route words; no other source of a word",
       "sent = 'modify.account ' : anm<av> : ' ' : trim(change(words, @fm, ' '))" in mk and mk.count("words<-1> =") == 2 and "words<-1> = (if aq<av, k> = 1 then gon<k> else goff<k>)" in mk and "words<-1> = rword" in mk
       and set(re.findall(r"rword = '([a-z]+)'", mk)) == {"both", "ssh", "api", "none"})
    qa = block(pg, "queue.all")
    cw = block(pg, "cell.why")
    qc = block(pg, "queue.cell")
    ck("TG5", "A and N (all on, all off; the owner's convenience of 1 Nov 2026) only QUEUE: A sends tv = 1 and N tv = 0 to queue.all, which writes a cell only when cell.why (the one test Enter uses too: built, applies to the "
       "kind of account, not sh or os for an account that is not a person) accepts it, to end in tv, taking back a queue for a gate already in tv; queue.all runs and confirms nothing; nothing assigns the literal 1 to a "
       "queued cell; the key table has exactly the ten actions and the Esc row that opens the menu bar (S.88 U2: the bar runs nothing, a choice is one of those keys)",
       not re.search(r"^\s*aq<.*>\s*=\s*1\b", pg, re.M) and re.search(r"aq<av, k> = \(if nw = s0 then '' else nw\)", qc) is not None and "gosub cell.why" in qc
       and re.search(r"case nm = 'a'\s*\n\s*tv = 1\s*\n\s*gosub queue.all", pg) is not None and re.search(r"case nm = 'n'\s*\n\s*tv = 0\s*\n\s*gosub queue.all", pg) is not None
       and re.search(r"gosub cell\.why\s*\n\s*if gids<k> = 'home' then why = [^\n]*\n\s*if why = '' then\s*\n\s*aq<av, k> = \(if ast<av, k> = tv then '' else tv\)", qa) is not None and qa.count("aq<av, k> =") == 1   # S.166: A and N leave home alone
       and not re.search(r"\$tk_run|\$tk_confirm|execute|gosub run\.queue", qa) and "case gstat<k> # 'built'" in cw and "case ast<av, k> = 'na'" in cw and "case (gids<k> = 'sh' or gids<k> = 'os') and aty<av> # 'USER'" in cw
       and sorted(set(re.findall(r"call \$tk_keys\('add', keys, '[^']+', '[^']+', '([a-z]+)'", pg))) == sorted(["help", "queue", "run", "drop", "tighten", "allon", "alloff", "filter", "find", "refresh", "quit", "menu"]))   # find: '/' (S.186, 9 Nov 26)
    th = block(pg, "tighten")
    ck("TG6", "T queues OFF (0) and only for a built gate that is off as delivered and on now, and not sh or os for an account that is not a person",
       "aq<av, k> = 0" in th and "gstat<k> = 'built' and gdef<k> = 'off' and ast<av, k> = 1" in th and "person.only = (gids<k> = 'sh' or gids<k> = 'os')" in th and "not(person.only and aty<av> # 'USER')" in th and th.count("aq<av, k> =") == 1)
    ck("TG7", "turning ON a gate that reaches beyond SD makes the box ask for the account's name (the flag comes from the table's beyond column, typed is the name, and it starts empty), and the order is check the needs, make the sentence, confirm, then run",
       "typed = ''" in mk and "if gbey<k> = 1 then beyond = 1" in mk and re.search(r"if beyond then\s*\n[^\n]*\n\s*typed = anm<av>", mk) is not None and "gbey<k> = gi<TK.G.BEYOND>" in pg
       and 0 < pg.find("gosub check.needs") < pg.find("gosub make.sentence") < pg.find("call $tk_confirm(") < pg.find("call $tk_run("))
    ck("TG8", "a gate that is off as delivered being turned ON is said so, with the tighter choice", "if gdef<k> = 'off' then loosen = 1" in mk and "Leaving it off is the tighter choice" in mk and "if loosen then" in mk)
    ck("TG9", "ssh and api are one setting: the per-gate words skip both columns, and the pair of final states gives one of both, ssh, api or none, in that order of cases",
       "if aq<av, k> # '' and k # rs and k # ra then" in mk and re.search(r"case fin<rs> = 1 and fin<ra> = 1\s*\n\s*rword = 'both'\s*\n\s*case fin<rs> = 1\s*\n\s*rword = 'ssh'\s*\n\s*case fin<ra> = 1\s*\n\s*rword = 'api'\s*\n\s*case 1\s*\n\s*rword = 'none'", mk) is not None)
    cn = block(pg, "check.needs")
    ck("TG10", "files-write needs files and files-admin needs files-write: refused by the page, in words, before the box, from the states the account WILL have",
       "if fin<fw> = 1 and fin<fi> # 1 then bad = 'files-write needs files" in cn and "if fin<fa> = 1 and fin<fw> # 1 then bad = 'files-admin needs files-write" in cn
       and re.search(r"gosub check\.needs\s*\n\s*if bad # '' then\s*\n\s*msg = bad\s*\n\s*return", pg) is not None)
    qc = block(pg, "queue.cell")
    ck("TG11", "sh and os are not queued for an account that is not a person (the verb refuses them in both directions), and a cell that is planned or not applicable queues nothing",
       "case (gids<k> = 'sh' or gids<k> = 'os') and aty<av> # 'USER'" in cw and "case gstat<k> # 'built'" in cw and "case ast<av, k> = 'na'" in cw
       and 0 < qc.find("gosub cell.why") < qc.find("if why # '' then") < qc.find("aq<av, k> ="))
    ck("TG12", "SDSYS is not a row (modify.account refuses it), and an account whose gates could not be read is not shown", "if id # 'sdsys' then" in pg and "call $tk_gates(names<i>, g, ainfo, gerr)\n      if gerr = '' then" in pg)
    rq = block(pg, "run.queue")
    ck("TG13", "after a command the queue of that account is cleared, the machine is read again and the page is drawn again, and what it shows is the verb's own words",
       re.search(r"call \$tk_run\(allow, sent, out, stat, err\)[\s\S]*?said = trim\(out<oi>\)[\s\S]*?aq<av, k> = ''[\s\S]*?gosub read\.all\s*\n\s*gosub draw\.all", rq) is not None)
    ck("TG14", "a cell takes its state from $tk_gates (administrator check inside), a queued cell shows the state it would have with a star, and nothing else decides whether a gate is on",
       "d = (if aq<av, k> # '' then aq<av, k> else s0)" in pg and "ct = (if d = 1 then 'ON' else 'off') : (if aq<av, k> # '' then '*' else '')" in pg and "s0 = ast<av, k>" in pg and "if gids<k> = g<j, 1> then ast<an, k> = g<j, 2>" in pg)
    heads = {}
    for r in built + [r for r in info_rows if len(r) == 15 and r[14] != "built"]:
        gid = r[0]
        m = re.search(r"case gid = '%s'\s*\n\s*hd = '([^']*)'" % re.escape(gid), pg)
        heads[gid] = m.group(1) if m else gid[:5]
    n = len(info_rows)
    ck("TG15", "the layout fits: the first cell is at column 3 + 20 + 6, the cells are 6 wide, every gate of the table has a heading of at most 5 characters and the headings differ, and the cells fit the 134 columns",
       "X0 = mat.x + 28" in pg and "CW = 6" in pg and "fmt('Account', '20L') : fmt('Kind', '6L')" in pg and 26 + 6 * n <= 134 and len(set(heads.values())) == len(heads) and all(len(h) <= 5 for h in heads.values()) and len(heads) == n, repr(heads))
    ck("TG16", "the filter has three modes and names them; the sessions are read with !listu and shown only for the account under the cursor", "flt = mod(flt + 1, 3)" in pg and pg.count("accounts of persons") == 1 and "call !listu(udata)" in pg and "if v<1, 9> = anm<av> then" in pg)
    ck("TG17", "the matrix has a [?] and F1, ? and a click show tool.gates.matrix, whose record exists", "call $tk_help('box', 'tool.gates.matrix', hm, 0, 0)" in pg and pg.count("tool.gates.matrix") == 2 and "call $tk_help('mark', mat.x + mat.w - 5, mat.y + 1, 0, 0)" in pg and raw["help"].split("\n")[0].strip() != "")
    # S.88 p5-U2b P10 (2 Nov 26): Ctrl-Q dropped the queue without a word
    la = block(pg, "leave.ask")
    ra = block(pg, "run.all")
    sets_done = [m.start() for m in re.finditer(r"^\s*done = 1\s*$", pg, re.M)]
    in_leave = [i for i in sets_done if (pg.find("leave.ask:") <= i < pg.find("leave.ask:") + len(la)) or (pg.find("run.all:") <= i < pg.find("run.all:") + len(ra))]
    ck("TG18", "Ctrl-Q (and File > Quit, which the bar gives as ctrl-q) asks leave.ask, and nothing else ends the page by setting done: leave.ask counts the queue of EVERY account (for av = 1 to an, final.of) and leaves at once only when none has one",
       re.search(r"case nm = 'ctrl-q'\s*\n\s*gosub leave\.ask\s*\n", pg) is not None and "call $tk_keys('add', keys, 'ctrl-q', 'quit', 'quit', '', 1)" in pg and len(sets_done) == 3 and in_leave == sets_done
       and re.search(r"for av = 1 to an\s*\n\s*gosub final\.of\s*\n\s*if qn > 0 then", la) is not None and re.search(r"if lq\.n = 0 then\s*\n\s*done = 1\s*\n\s*return", la) is not None
       and la.find("next av") < la.find("if lq.n = 0 then"), repr((len(sets_done), len(in_leave))))
    ck("TG19", "with something queued the question is $tk_confirm's box with three buttons, Cancel LAST (the last is the default, so Enter alone neither leaves nor runs); only 'alt' (Leave without them) leaves, "
               "'run' goes to run.all, anything else stays with the queue kept",
       la.count("call $tk_confirm(") == 1 and re.search(r"call \$tk_confirm\([^\n]*, '', lq\.res, lq\.msg, '[^']+', '&Run the changes,&Leave without them,&Cancel'\)", la) is not None
       and re.search(r"case lq\.res = 'alt'\s*\n\s*done = 1\s*\n\s*case lq\.res = 'run'\s*\n\s*gosub run\.all\s*\n\s*case 1\s*\n\s*msg = ", la) is not None
       and not re.search(r"\$tk_run|execute|aq<", la), la[-400:])
    ck("TG20", "Run the changes runs nothing itself: run.all only hands each account with a queue to run.queue (R's own path: check.needs, the box, the name, $tk_run), once each by name, "
               "and leaves only when no cell is queued afterwards; R's handler names the cursor's account before run.queue, which no longer reads the cursor",
       not re.search(r"\$tk_run|\$tk_confirm|execute|aq<", ra) and ra.count("gosub run.queue") == 1 and "lq.tried<-1> = anm<av>" in ra and "locate anm<lq.i> in lq.tried<1> setting lq.p else" in ra
       and re.search(r"case lq\.fail > 0\s*\n\s*msg = [^\n]*\n\s*case lq\.left = 0\s*\n\s*done = 1", ra) is not None and ra.find("gosub run.queue") < ra.find("lq.left = 0")
       and "if rq.ran and not(rq.ok) then" in ra and "rq.ok = (err = '' and stat >= 0)" in rq   # 2 Nov 26 review: a refused or failed command keeps the page
       and re.search(r"case nm = 'r'\s*\n\s*if nv > 0 then\s*\n\s*av = view<ci>\s*\n\s*gosub run\.queue", pg) is not None and "view<ci>" not in rq, ra[-300:])
    return rows


def sub(key, old, new):
    def f(raw):
        r = dict(raw)
        if old not in r[key]:
            raise KeyError("%s: %r is not in the file, so the mutant cannot be made" % (key, old[:60]))
        r[key] = r[key].replace(old, new, 1)
        return r
    return f


MUTANTS = [
    ("the page is opened for anyone", "TG2", sub("page", "call $tk_open('tool.gates', 'admin', ctx, err)", "call $tk_open('tool.gates', '', ctx, err)")),
    ("every account's verb runs the administrator's matrix", "TG1", sub("newvoc", "$tool_mygates", "$tool_gates")),
    ("the page reads before it opens the base", "TG2", sub("page", "   call $tk_open('tool.gates', 'admin', ctx, err)\n   if err # '' then\n      display err\n      stop\n   end\n", "   openpath @sdsys:@ds:'accounts' to acc.f0 then close acc.f0\n   call $tk_open('tool.gates', 'admin', ctx, err)\n   if err # '' then\n      display err\n      stop\n   end\n")),
    ("a second audit line", "TG2", sub("page", "   keys = ''\n", "   void kernel(K$AUDIT, 'tool x')\n   keys = ''\n")),
    ("the page may run another command", "TG3", sub("page", "allow = 'modify.account'", "allow = 'modify.account sh'")),
    ("the page runs the command itself", "TG3", sub("page", "call $tk_run(allow, sent, out, stat, err)", "execute sent capturing out")),
    ("the page writes the register", "TG3", sub("page", "      aq<av, k> = ''\n   next k\n   gosub redraw\n   msg = 'dropped", "      aq<av, k> = ''\n   next k\n   write 'x' to acc.f, 'y'\n   gosub redraw\n   msg = 'dropped")),
    ("the confirm box is skipped", "TG3", sub("page", "   if res = 'run' then\n      call $tk_run(", "   res = 'run'\n   if res = 'run' then\n      call $tk_run(")),
    ("a word comes from somewhere else", "TG4", sub("page", "words<-1> = (if aq<av, k> = 1 then gon<k> else goff<k>)", "words<-1> = (if aq<av, k> = 1 then gon<k> else gall<k>)")),
    ("the sentence names another account", "TG4", sub("page", "sent = 'modify.account ' : anm<av> : ' '", "sent = 'modify.account ' : anm<1> : ' '")),
    ("a key queues every cell on, past the test", "TG5", sub("page", "      case nm = 'u'\n         gosub drop.queue\n", "      case nm = 'u'\n         gosub drop.queue\n      case nm = 'k'\n         for ai.k = 1 to NG\n            aq<view<ci>, ai.k> = 1\n         next ai.k\n")),
    ("all on skips the test of a cell", "TG5", sub("page", "      gosub cell.why\n      if why = '' then\n         aq<av, k> = (if ast<av, k> = tv", "      why = ''\n      if why = '' then\n         aq<av, k> = (if ast<av, k> = tv")),
    ("all on runs the queue at once", "TG5", sub("page", "   gosub redraw\n   w.st = ", "   gosub run.queue\n   w.st = ")),
    ("all off queues on", "TG5", sub("page", "      case nm = 'n'\n         tv = 0", "      case nm = 'n'\n         tv = 1")),
    ("cell.why lets sh through for a group account", "TG5", sub("page", "      case (gids<k> = 'sh' or gids<k> = 'os') and aty<av> # 'USER'\n         why =", "      case 0\n         why =")),
    ("a gate already on is queued again", "TG5", sub("page", "aq<av, k> = (if ast<av, k> = tv then '' else tv)", "aq<av, k> = tv")),
    ("tighten queues ON", "TG5", sub("page", "         aq<av, k> = 0\n         n.q += 1", "         aq<av, k> = 1\n         n.q += 1")),
    ("tighten takes a gate that is on as delivered", "TG6", sub("page", "gstat<k> = 'built' and gdef<k> = 'off' and ast<av, k> = 1", "gstat<k> = 'built' and ast<av, k> = 1")),
    ("tighten queues sh for a group account", "TG6", sub("page", " and not(person.only and aty<av> # 'USER')", "")),
    ("no name is asked for a gate that reaches beyond SD", "TG7", sub("page", "      typed = anm<av>\n   end\n   el<-1> = 'A running session", "      typed = ''\n   end\n   el<-1> = 'A running session")),
    ("the beyond flag is read from the wrong column", "TG7", sub("page", "gbey<k> = gi<TK.G.BEYOND>", "gbey<k> = gi<TK.G.BEYOND - 1>")),
    ("the sentence is made before the needs are checked", "TG7", sub("page", "   gosub check.needs\n   if bad # '' then\n      msg = bad\n      return\n   end\n   gosub make.sentence", "   gosub make.sentence\n   gosub check.needs\n   if bad # '' then\n      msg = bad\n      return\n   end")),
    ("the delivered-off sentence is gone", "TG8", sub("page", "Leaving it off is the tighter choice", "Leaving it off is the other choice")),
    ("both is sent as ssh", "TG9", sub("page", "            rword = 'both'", "            rword = 'ssh'")),
    ("the route columns are also sent as words of their own", "TG9", sub("page", "if aq<av, k> # '' and k # rs and k # ra then", "if aq<av, k> # '' then")),
    ("files-write is allowed without files", "TG10", sub("page", "if fin<fw> = 1 and fin<fi> # 1 then bad =", "if fin<fw> = 1 and fin<fi> = 7 then bad =")),
    ("files-admin is allowed without files-write", "TG10", sub("page", "if fin<fa> = 1 and fin<fw> # 1 then bad =", "if @false then bad =")),
    ("sh is queued for a group account", "TG11", sub("page", "      case (gids<k> = 'sh' or gids<k> = 'os') and aty<av> # 'USER'\n         why =", "      case @false\n         why =")),
    ("Enter queues without the test", "TG11", sub("page", "   s0 = ast<av, k>\n   gosub cell.why\n", "   s0 = ast<av, k>\n   why = ''\n")),
    ("SDSYS is a row", "TG12", sub("page", "if id # 'sdsys' then", "if id # 'sdsysx' then")),
    ("the page is not drawn again after a command", "TG13", sub("page", "      gosub read.all\n      gosub draw.all\n   end else\n      msg = cmsg", "      msg = msg\n   end else\n      msg = cmsg")),
    ("the cell shows the queue as the state", "TG14", sub("page", "ct = (if d = 1 then 'ON' else 'off') : (if aq<av, k> # '' then '*' else '')", "ct = (if d = 1 then 'ON' else 'off')")),
    ("two gates have the same heading", "TG15", sub("page", "         hd = 'sh-wr'", "         hd = 'sh-rd'")),
    ("a heading is too long", "TG15", sub("page", "         hd = 'f-adm'", "         hd = 'files-admin'")),
    ("the cells start in another column", "TG15", sub("page", "X0 = mat.x + 28", "X0 = mat.x + 29")),
    ("the filter has a fourth mode", "TG16", sub("page", "flt = mod(flt + 1, 3)", "flt = mod(flt + 1, 4)")),
    ("the matrix has no [?]", "TG17", sub("page", "   call $tk_help('mark', mat.x + mat.w - 5, mat.y + 1, 0, 0)\n", "")),
]
M_P10 = len(MUTANTS)          # S.88 p5-U2b P10 (2 Nov 26): the leave question.  --selftest --from=M_P10 runs these alone
MUTANTS += [
    ("Ctrl-Q leaves at once again, dropping the queue", "TG18", sub("page", "      case nm = 'ctrl-q'\n         gosub leave.ask\n", "      case nm = 'ctrl-q'\n         done = 1\n")),
    ("only the cursor's account is counted", "TG18", sub("page", "   for av = 1 to an\n      gosub final.of\n      if qn > 0 then\n         lq.n += 1", "   for av = view<ci> to view<ci>\n      gosub final.of\n      if qn > 0 then\n         lq.n += 1")),
    ("Leave is the default button", "TG19", sub("page", "'&Run the changes,&Leave without them,&Cancel'", "'&Run the changes,&Cancel,&Leave without them'")),
    ("Cancel leaves too", "TG19", sub("page", "      case 1\n         msg = 'nothing was run; the queued changes", "      case 1\n         done = 1\n         msg = 'nothing was run; the queued changes")),
    ("the leave box runs the commands itself", "TG19", sub("page", "      case lq.res = 'run'\n         gosub run.all\n", "      case lq.res = 'run'\n         call $tk_run(allow, lq.sent, out, stat, err)\n")),
    ("Run the changes leaves although a queue is left", "TG20", sub("page", "      case lq.left = 0\n         done = 1", "      case 1\n         done = 1")),
    ("Run the changes leaves although a command failed", "TG20", sub("page", "      case lq.fail > 0\n", "      case @false\n")),
    ("a refused command counts as success", "TG20", sub("page", "      rq.ok = (err = '' and stat >= 0)", "      rq.ok = 1")),
    ("run.all runs the queue past R's box", "TG20", sub("page", "      lq.tried<-1> = anm<av>\n      gosub run.queue\n", "      lq.tried<-1> = anm<av>\n      gosub make.sentence\n      call $tk_run(allow, sent, out, stat, err)\n")),
    ("R's handler leaves the account unnamed", "TG20", sub("page", "         if nv > 0 then\n            av = view<ci>\n            gosub run.queue\n", "         if nv > 0 then\n            gosub run.queue\n")),
]


def load():
    raw = {}
    for k, p in FILES.items():
        try:
            with open(p, encoding="latin-1") as f:
                raw[k] = f.read()
        except OSError:
            raw[k] = ""
    return raw


def report(rows):
    bad = 0
    for i, what, ok, detail in rows:
        print("  [%s] %s %s%s" % ("PASS" if ok else "FAIL", i, what, "" if ok or not detail else "   <- " + str(detail)[:200]))
        bad += 0 if ok else 1
    return bad


def selftest(raw, start=0):
    base = [r[0] for r in checks(raw) if not r[2]]
    if base:
        print("selftest: the unchanged tree fails %s, so a mutant's own failure cannot be told from the tree's; run the plain check first" % base)
        return 1
    holes = 0
    if start:
        print("selftest: from mutant %d of %d (--from)" % (start, len(MUTANTS)))
    for name, want, mut in MUTANTS[start:]:
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
    print("selftest: %d mutants, %d not caught" % (len(MUTANTS) - start, holes))
    return 1 if holes else 0


def main(argv):
    raw = load()
    print("test-toolgates-units: tree %s" % os.path.dirname(GPL))
    if not raw["page"]:
        print("test-toolgates-units: CANNOT RUN - %s is not there" % FILES["page"])
        return 2
    rows = checks(raw)
    bad = report(rows)
    print("\ntest-toolgates-units: %d passed, %d failed" % (len(rows) - bad, bad))
    rc = 1 if bad else 0
    if "--selftest" in argv:
        start = next((int(a.split("=", 1)[1]) for a in argv if a.startswith("--from=")), 0)
        rc = (selftest(raw, start) or rc)
    return rc


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
