#!/usr/bin/env python3
"""test-toolsessions-units.py - the sessions and locks page, TOOL.SESSIONS (`gpl.bp/tool_sessions`), as invariants read off the source (S.75, administrator app A4).  Free: no install, no sudo, no sd.

    python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/test-toolsessions-units.py [--selftest]

WHAT THIS IS, AND WHAT IT IS NOT.  It reads the page's BASIC as text, with comments removed.  ***IT RUNS NOTHING, SO IT CANNOT SAY THAT A SESSION ENDS OR THAT A LOCK GOES***: that is
`sandbox-tool-sessions.py` (a private SD, live sessions holding locks, the real logout and unlock verbs, the disk and the user table as the evidence).  What a text check is for: the
properties that make the page a FRONT END - it opens the base for the administrator before it reads anything, it runs three commands through the one place that runs commands, each only
after the box was answered Run, it builds each command from values it has read and checked, it never offers to log out the session it runs in, and the characters it will put in a command
are the characters $tk_run lets through - which are mostly ORDER and ABSENCE, and an edit that moves one still compiles.

--selftest breaks each invariant in the way an edit plausibly would and requires a check to notice; a mutant that nothing catches is a failure of the self-test.
"""

import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SDSYS = os.path.normpath(os.path.join(HERE, "..", "sdsys"))
GPL = os.path.join(SDSYS, "gpl.bp")
FILES = {
    "page": os.path.join(GPL, "tool_sessions"),
    "run": os.path.join(GPL, "tk_run"),
    "voc": os.path.join(SDSYS, "voc_template", "tool.sessions"),
    "help": os.path.join(SDSYS, "helptext", "tool.sessions.page"),
}
NEWVOC = os.path.join(SDSYS, "newvoc", "tool.sessions")
SAFE = "abcdefghijklmnopqrstuvwxyz0123456789.-_"


def load():
    raw = {}
    for k, p in FILES.items():
        try:
            with open(p, encoding="latin-1") as f:
                raw[k] = f.read()
        except OSError:
            raw[k] = ""
    raw["newvoc_has"] = "1" if os.path.exists(NEWVOC) else ""
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


def block(text, label):
    """The text of an internal subroutine: from its label to the next label at the start of a line (or to END)."""
    m = re.search(r"^" + re.escape(label) + r":\s*$", text, re.M)
    if not m:
        return ""
    n = re.search(r"^[a-z][a-z.0-9]*:\s*$|^end\s*$", text[m.end():], re.M)
    return text[m.start(): m.end() + (n.start() if n else len(text))]


def checks(raw):
    rows = []

    def ck(i, what, ok, detail=""):
        rows.append((i, what, bool(ok), detail))

    pg = strip_bas(raw["page"])
    ck("SS0", "NULL CASE: the page, the VOC entry and the help record were found and are not empty (a check on nothing would pass)",
       len(pg) > 9000 and raw["voc"].strip() != "" and len(raw["help"].split("\n")) >= 5 and len(raw["run"]) > 500, "%d" % len(pg))
    ck("SS1", "the page is an internal program catalogued as $tool_sessions, SDSYS's VOC has it as a verb for that program, and the shared VOC (newvoc) has NO tool.sessions: an ordinary account has no such verb",
       re.search(r"^\$internal\s*\nprogram \$tool_sessions\s*\n\$catalog \$tool_sessions\b", pg, re.M) is not None and raw["voc"].split("\n")[:3] == ["V", "CA", "$tool_sessions"] and raw["newvoc_has"] == "",
       repr((raw["voc"][:30], raw["newvoc_has"])))
    i_open = pg.find("call $tk_open('tool.sessions', 'admin', ctx, err)")
    i_audit = pg.find("kernel(K$AUDIT, 'tool start app=tool.sessions')")
    i_listu = pg.find("call !listu(udata)")
    ck("SS2", "it opens the toolkit's base for the ADMINISTRATOR first (a refusal is shown and the program stops), before it reads a session or a lock; the audit line that says it started comes before any read, and the only other audit line is audit.run's",
       0 < i_open < i_audit < i_listu and re.search(r"call \$tk_open\('tool\.sessions', 'admin', ctx, err\)\s*\n\s*if err # '' then\s*\n\s*display err\s*\n\s*stop\s*\n\s*end", pg) is not None
       and pg.count("K$AUDIT") == 2 and pg.find("gosub read.all") > i_audit and pg.find("K$AUDIT", i_audit + 10) > pg.find("audit.run:"),
       "open %s, audit %s, listu %s" % (i_open, i_audit, i_listu))
    ck("SS3", "it runs THREE commands, logout, unlock and inhibit.login, through $tk_run and nowhere else: one allow list, three calls of $tk_run, each directly after a confirm box and guarded by res = 'run'; no execute, perform, chain, write or delete",
       re.findall(r"\ballow = '([^']*)'", pg) == ["logout unlock inhibit.login"] and pg.count("call $tk_run(allow, sent, out, stat, err)") == 3
       and len(re.findall(r"call \$tk_confirm\(sent, el, (?:typed|notyped), res, cmsg\)\s*\n\s*if res = 'run' then\s*\n\s*call \$tk_run\(allow, sent, out, stat, err\)", pg)) == 3
       and not re.search(r"^\s*(?:execute|os\.execute|perform|chain|write[uv]?|delete[uv]?|matwrite[u]?|openseq|openpath|writeseq)\b", pg, re.M),
       "run %d" % pg.count("call $tk_run("))
    lo = block(pg, "do.logout")
    i_own = lo.find("if uid = @userno then")
    i_sent = lo.find("sent = 'logout ' : uid")
    ck("SS4", "LOGOUT: the session you are in is refused BEFORE the sentence is built, and a session whose logout is pending is NOT refused (asking again is how a dead one is cleared); the sentence is 'logout ' + the user number read from the list; the number is typed again (typed = uid)",
       0 < i_own < i_sent and lo.count("sent = ") == 1 and "typed = uid" in lo and "uid = v<1, 1>" in lo and "call $tk_confirm(sent, el, typed, res, cmsg)" in lo and "USR$LOGOUT" not in lo
       and re.search(r"if uid = @userno then\s*\n\s*msg = '[^']*'\s*\n\s*return\s*\n\s*end", lo) is not None, "%s %s" % (i_own, i_sent))
    us = block(pg, "unlock.sentence")
    ck("SS5", "UNLOCK: a waiting row is refused; the file number and the user number must be numbers the verb takes (1 to 4 and 1 to 5 digits); a file lock is 'filelock'; a record lock carries the record id only after plain.word; the words come from the lock read",
       "case utyp = 'WAIT'" in us and "not(ufile matches '1-4N') or not(uuser matches '1-5N')" in us and "usent = 'unlock file ' : ufile : ' user ' : uuser : ' filelock'" in us
       and "usent = 'unlock file ' : ufile : ' user ' : uuser : ' ' : uid2" in us and 0 <= us.find("gosub plain.word") < us.find("usent = 'unlock file ' : ufile : ' user ' : uuser : ' ' : uid2")
       and re.search(r"gosub plain\.word\s*\n\s*if plain then\s*\n\s*usent = 'unlock file ' : ufile : ' user ' : uuser : ' ' : uid2", us) is not None
       and us.count("usent = ") >= 3 and "ufile = locks<lk, 1>" in us and "uuser = locks<lk, 3>" in us and "uid2 = downcase(locks<lk, 5>)" in us)
    pw = block(pg, "plain.word")
    run_has = re.search(r"a-z, 0-9, dot, dash and underscore", raw["run"]) is not None
    ck("SS6", "plain.word lets through exactly what $tk_run lets through (a-z, 0-9, dot, dash, underscore) and refuses the words UNLOCK itself reads as keywords: all, file, user, filelock, tasklock",
       ("index('%s', word[pi, 1], 1) = 0" % SAFE) in pw and "plain = (word # '')" in pw and all(("word = '%s'" % w) in pw for w in ("all", "file", "user", "filelock", "tasklock")) and run_has,
       pw[:200])
    di = block(pg, "do.inhibit")
    ck("SS7", "INHIBIT.LOGIN: 'on' only when logins are allowed (inh is empty) and 'off' only when they are inhibited; both are shown in a box with what they do and the state is read again afterwards",
       re.search(r"if inh = '' then\s*\n\s*sent = 'inhibit\.login on'", di) is not None and "sent = 'inhibit.login off'" in di and di.count("sent = ") == 2
       and re.search(r"gosub read\.all\s*\n\s*gosub draw\.all", di) is not None)
    ra = block(pg, "read.all")
    ck("SS8", "the sessions come from !listu, the locks from getlocks('', 0) and the login inhibit from !login_inhibit('STATE'); a refresh puts the cursor back on the same user number and the same lock (file, user, type, id), not the same row number",
       "call !listu(udata)" in ra and "locks = getlocks('', 0)" in ra and "call !login_inhibit('STATE', inh, ierr)" in ra and "del locks<1>" in ra and "sel.u = udata<cs, 1>" in ra and "sel.l = lkey" in ra
       and re.search(r"for i = 1 to ns\s*\n\s*if udata<i, 1> = sel\.u then\s*\n\s*cs = i", ra) is not None and re.search(r"for lk = 1 to nl\s*\n\s*gosub lock\.key\s*\n\s*if lkey = sel\.l then\s*\n\s*cl = lk", ra) is not None
       and "lkey = locks<lk, 1> : '|' : locks<lk, 3> : '|' : locks<lk, 4> : '|' : locks<lk, 5>" in block(pg, "lock.key"))
    tr = block(pg, "timed.refresh")
    ck("SS9", "the lists are read every three seconds while the page waits for a key, and written again only when what was read differs from what was shown",
       "screen key timeout 3 returning nm" in pg and "gosub timed.refresh" in pg and "old.sig = sig" in tr and "if sig # old.sig then" in tr and "sig = udata : @fm : locks : @fm : inh" in ra)
    acts = sorted(set(re.findall(r"call \$tk_keys\('add', keys, '[^']+', '[^']+', '([a-z]+)'", pg)))
    ck("SS10", "the key table has exactly: help, switch, logout, unlock, inhibit, refresh, quit; L belongs to the sessions list and U to the locks list, in the table and in the dispatch",
       acts == sorted(["help", "switch", "logout", "unlock", "inhibit", "refresh", "quit"]) and "'l', 'logout', 'logout', 'Sessions'" in pg and "'u', 'unlock', 'unlock', 'Locks'" in pg
       and "case nm = 'l' and pane = 1" in pg and "case nm = 'u' and pane = 2" in pg, " ".join(acts))
    ck("SS11", "after a command the lists are read again and the whole page is drawn again, and what the status line shows is the verb's own first line",
       len(re.findall(r"call \$tk_run\(allow, sent, out, stat, err\)[\s\S]*?gosub first\.line[\s\S]*?gosub read\.all\s*\n\s*gosub draw\.all", pg)) == 3 and "trim(out<oi>) # ''" in block(pg, "first.line") and "for oi = 1 to dcount(out, @fm)" in block(pg, "first.line"))
    ck("SS12", "the page has a [?] and F1, ? and a click show tool.sessions.page, whose record exists with a title, a documentation page and a body",
       pg.count("'tool.sessions.page'") == 2 and "call $tk_help('mark', 134, 2, 0, 0)" in pg and "call $tk_help('hit', mev, 134, 2, hit.m)" in pg
       and raw["help"].split("\n")[0].strip() != "" and raw["help"].split("\n")[1].strip() == "02-sessions-and-locks" and raw["help"].split("\n")[2].strip() != "")
    dl = block(pg, "draw.all")
    dsn = block(pg, "draw.sessions")
    dlk = block(pg, "draw.locks")
    dr = block(pg, "draw.row")
    ck("SS13", "the layout fits the 140 by 43 frame: three boxes (rows 1-15, 16-29, 30-39), 11 session rows at y 3-13 with the counts at 14, 10 lock rows at y 18-27 with the lock limit at 28, 7 lines of explanation at y 31-37 and the hint at 38",
       "screen box at 1,1 size 138,15" in dl and "screen box at 1,16 size 138,14" in dl and "screen box at 1,30 size 138,10" in dl and "VS = 11" in pg and "VL = 10" in pg
       and "at 3,2 + r attr rat" in dsn and "at 3,14 attr" in dsn and "at 3,17 + r attr rat" in dlk and "at 3,28 attr" in dlk and "for r = 1 to 7" in dr and "at 3,30 + r width 134" in dr and "at 3,38 attr" in dr)
    ck("SS14", "the kind of a session comes from the kernel's flag bits, SDNet before API before phantom (the SDNet flag sets the API one too); 'you' and '(logout pending)' come from @userno and USR$LOGOUT",
       re.search(r"case bitand\(flg, USR\$SDNET\)\s*\n\s*kind = 'sdnet'\s*\n\s*case bitand\(flg, USR\$SDVBSRVR\)\s*\n\s*kind = 'api'\s*\n\s*case bitand\(flg, USR\$PHANTOM\)\s*\n\s*kind = 'phantom'", block(pg, "session.line")) is not None
       and "if v<1, 1> = @userno then stt = 'you'" in block(pg, "session.line") and "bitand(flg, USR$LOGOUT)" in block(pg, "session.line"))
    ck("SS15", "a lock whose user number is not among the sessions is marked 'no session', and the explanation says U releases it; for a live holder it says L on the session clears a dead one and releases every lock it held",
       "holder = 'no session'" in block(pg, "holder.of") and "if udata<hi, 1> = uid then" in block(pg, "holder.of") and "U releases it now" in block(pg, "row.lock")
       and "L on its row in the sessions list clears the entry and releases every lock it held" in block(pg, "row.lock") and "sd -cleanup" not in pg)
    ar = block(pg, "audit.run")
    ck("SS16", "every command the page ran is audited, once, after $tk_run answered without an error: audit.run writes 'tool run app=tool.sessions command=' + the sentence + the status, and it is called in the else branch of each run, before the status line is made",
       "void kernel(K$AUDIT, 'tool run app=tool.sessions command=' : sent : ' status=' : stat)" in ar and pg.count("gosub audit.run") == 3
       and len(re.findall(r"if err # '' then\s*\n\s*msg = err\s*\n\s*end else\s*\n\s*gosub audit\.run\s*\n\s*gosub first\.line", pg)) == 3)
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


MUTANTS = [
    ("the page is opened for anyone", "SS2", sub("page", "call $tk_open('tool.sessions', 'admin', ctx, err)", "call $tk_open('tool.sessions', '', ctx, err)")),
    ("the page reads before it opens the base", "SS2", sub("page", "   call $tk_open('tool.sessions', 'admin', ctx, err)\n   if err # '' then\n      display err\n      stop\n   end\n", "   call !listu(udata)\n   call $tk_open('tool.sessions', 'admin', ctx, err)\n   if err # '' then\n      display err\n      stop\n   end\n")),
    ("a second start audit line", "SS2", sub("page", "   keys = ''\n", "   void kernel(K$AUDIT, 'tool x')\n   keys = ''\n")),
    ("the start audit line comes after the first read", "SS2", sub("page", "   void kernel(K$AUDIT, 'tool start app=tool.sessions')\n", "   call !listu(udata)\n   void kernel(K$AUDIT, 'tool start app=tool.sessions')\n")),
    ("an ordinary account gets the verb", "SS1", setkey("newvoc_has", "1")),
    ("the page may run another command", "SS3", sub("page", "allow = 'logout unlock inhibit.login'", "allow = 'logout unlock inhibit.login sh'")),
    ("the page runs a command itself", "SS3", sub("page", "      call $tk_run(allow, sent, out, stat, err)\n      if err # '' then\n         msg = err\n      end else\n         gosub audit.run\n         gosub first.line\n         msg = (if said # '' then said[1, 130] else 'released')", "      execute sent capturing out\n      if err # '' then\n         msg = err\n      end else\n         gosub audit.run\n         gosub first.line\n         msg = (if said # '' then said[1, 130] else 'released')")),
    ("the unlock box is skipped", "SS3", sub("page", "   call $tk_confirm(sent, el, notyped, res, cmsg)\n   if res = 'run' then\n      call $tk_run(allow, sent, out, stat, err)\n      if err # '' then\n         msg = err\n      end else\n         gosub audit.run\n         gosub first.line\n         msg = (if said # '' then said[1, 130] else 'released')", "   res = 'run'\n   if res = 'run' then\n      call $tk_run(allow, sent, out, stat, err)\n      if err # '' then\n         msg = err\n      end else\n         gosub audit.run\n         gosub first.line\n         msg = (if said # '' then said[1, 130] else 'released')")),
    ("the page writes a file", "SS3", sub("page", "   notyped = ''", "   notyped = ''\n   write 'x' to acc.f, 'y'")),
    ("the session you are in can be logged out", "SS4", sub("page", "   if uid = @userno then\n      msg = 'that is the session you are in; Ctrl-Q leaves the page'\n      return\n   end\n", "")),
    ("a pending logout is refused (a dead session could then never be cleared)", "SS4", sub("page", "   if uid = @userno then\n      msg = 'that is the session you are in; Ctrl-Q leaves the page'\n      return\n   end\n", "   if uid = @userno then\n      msg = 'that is the session you are in; Ctrl-Q leaves the page'\n      return\n   end\n   if bitand(v<1, 4>, USR$LOGOUT) then\n      msg = 'pending'\n      return\n   end\n")),
    ("the number is not typed again", "SS4", sub("page", "   typed = uid\n", "   typed = ''\n")),
    ("logout takes the cursor's number from the wrong place", "SS4", sub("page", "   uid = v<1, 1>\n   if uid = @userno then", "   uid = v<1, 2>\n   if uid = @userno then")),
    ("a waiting row can be unlocked", "SS5", sub("page", "      case utyp = 'WAIT'\n         uwhy = 'A waiting row is not a lock.'", "      case @false\n         uwhy = 'A waiting row is not a lock.'")),
    ("a file lock is released as a record", "SS5", sub("page", "usent = 'unlock file ' : ufile : ' user ' : uuser : ' filelock'", "usent = 'unlock file ' : ufile : ' user ' : uuser : ' all'")),
    ("the record id is used without the safe-word test", "SS5", sub("page", "         word = uid2\n         gosub plain.word\n         if plain then", "         word = uid2\n         plain = 1\n         if plain then")),
    ("the user number is not checked", "SS5", sub("page", "not(ufile matches '1-4N') or not(uuser matches '1-5N')", "not(ufile matches '1-4N')")),
    ("the safe-word test lets a space through", "SS6", sub("page", "abcdefghijklmnopqrstuvwxyz0123456789.-_", "abcdefghijklmnopqrstuvwxyz0123456789.-_ ")),
    ("the keyword all is a record id", "SS6", sub("page", "word = 'all' or ", "")),
    ("the keyword filelock is a record id", "SS6", sub("page", " or word = 'filelock'", "")),
    ("an empty record id is a word", "SS6", sub("page", "plain = (word # '')", "plain = 1")),
    ("inhibit.login on is sent while logins are inhibited", "SS7", sub("page", "   if inh = '' then\n      sent = 'inhibit.login on'", "   if inh # '' then\n      sent = 'inhibit.login on'")),
    ("inhibit.login is not read again", "SS7", sub("page", "      gosub read.all\n      gosub draw.all\n   end else\n      msg = cmsg\n   end\n   return\n\nend", "      gosub draw.all\n   end else\n      msg = cmsg\n   end\n   return\n\nend")),
    ("the locks come from somewhere else", "SS8", sub("page", "locks = getlocks('', 0)", "locks = getlocks('', @userno)")),
    ("the cursor is kept by row number", "SS8", sub("page", "      for i = 1 to ns\n         if udata<i, 1> = sel.u then", "      for i = 1 to 0\n         if udata<i, 1> = sel.u then")),
    ("a lock is told from another by file alone", "SS8", sub("page", "lkey = locks<lk, 1> : '|' : locks<lk, 3> : '|' : locks<lk, 4> : '|' : locks<lk, 5>", "lkey = locks<lk, 1>")),
    ("the page waits for a key for ever", "SS9", sub("page", "screen key timeout 3 returning nm", "screen key returning nm")),
    ("the timer always redraws", "SS9", sub("page", "   if sig # old.sig then\n      gosub draw.lists", "   if @true then\n      gosub draw.lists")),
    ("a key logs out from the locks list", "SS10", sub("page", "case nm = 'l' and pane = 1", "case nm = 'l'")),
    ("a key queues something else", "SS10", sub("page", "call $tk_keys('add', keys, 'i', 'logins', 'inhibit', '', 1)", "call $tk_keys('add', keys, 'i', 'logins', 'inhibit', '', 1)\n   call $tk_keys('add', keys, 'a', 'all', 'all', '', 1)")),
    ("the page shows its old rows after a command", "SS11", sub("page", "         msg = (if said # '' then said[1, 130] else 'asked user ' : uid : ' to end; the list is read again every three seconds')\n      end\n      gosub read.all\n      gosub draw.all", "         msg = (if said # '' then said[1, 130] else 'asked user ' : uid : ' to end; the list is read again every three seconds')\n      end\n      gosub draw.all")),
    ("the help key names a record that does not exist", "SS12", sub("page", "call $tk_help('box', 'tool.sessions.page', hm, 0, 0)\n         if hm # '' then msg = hm\n      case nm = 'f5'", "call $tk_help('box', 'tool.sessions.nopage', hm, 0, 0)\n         if hm # '' then msg = hm\n      case nm = 'f5'")),
    ("the help record names no page", "SS12", sub("help", "02-sessions-and-locks", "")),
    ("the locks box overruns the explanation", "SS13", sub("page", "screen box at 1,16 size 138,14 title 'Locks'", "screen box at 1,16 size 138,15 title 'Locks'")),
    ("a lock row is drawn on the border", "SS13", sub("page", "   screen text s at 3,28 attr 'bold' width 134", "   screen text s at 3,29 attr 'bold' width 134")),
    ("API before SDNet", "SS14", sub("page", "      case bitand(flg, USR$SDNET)\n         kind = 'sdnet'\n      case bitand(flg, USR$SDVBSRVR)\n         kind = 'api'", "      case bitand(flg, USR$SDVBSRVR)\n         kind = 'api'\n      case bitand(flg, USR$SDNET)\n         kind = 'sdnet'")),
    ("every holder is signed on", "SS15", sub("page", "   holder = 'no session'\n", "   holder = 'signed on'\n")),
    ("a command is run without an audit line (unlock)", "SS16", sub("page", "         gosub audit.run\n         gosub first.line\n         msg = (if said # '' then said[1, 130] else 'released')", "         gosub first.line\n         msg = (if said # '' then said[1, 130] else 'released')")),
    ("the audit line is written even when the command did not run", "SS16", sub("page", "      call $tk_run(allow, sent, out, stat, err)\n      if err # '' then\n         msg = err\n      end else\n         gosub audit.run\n         gosub first.line\n         msg = (if said # '' then said[1, 130] else 'done')", "      call $tk_run(allow, sent, out, stat, err)\n      gosub audit.run\n      if err # '' then\n         msg = err\n      end else\n         gosub first.line\n         msg = (if said # '' then said[1, 130] else 'done')")),
    ("the audit line names the wrong thing", "SS16", sub("page", "'tool run app=tool.sessions command=' : sent : ' status=' : stat", "'tool run app=tool.sessions command=' : uid : ' status=' : stat")),
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
    print("test-toolsessions-units: tree %s" % os.path.dirname(GPL))
    if not raw["page"]:
        print("test-toolsessions-units: CANNOT RUN - %s is not there" % FILES["page"])
        return 2
    rows = checks(raw)
    bad = report(rows)
    print("\ntest-toolsessions-units: %d passed, %d failed" % (len(rows) - bad, bad))
    rc = 1 if bad else 0
    if "--selftest" in argv:
        rc = (selftest(raw) or rc)
    return rc


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
