#!/usr/bin/env python3
"""test-toolremote-units.py - the remote access page, TOOL.REMOTE (`gpl.bp/tool_remote`), as invariants read off the source (S.75, administrator app A9).  Free: no install, no elevation, no sd.

    python gplbld/test-toolremote-units.py [--selftest]

WINDOWS PORT, 10 Nov 26 (RELEASE_1.1 228): from SD Core for Linux's guard of the same name.  A hands the terminal to REMOTE.API rather than running it
through the routine, because the Windows verb asks whether to restart SD when the listener moves to or from OFF (RM6).
13 Nov 26 Windows port - RELEASE_1.1 202: the sixth view is back (it was left out while remote administration over ssh was deferred, and RM16 held that
absence).  RM3, RM5, RM12 and RM16 are Linux's again, with one OS deviation in RM16: O (REMOTE.SDSYS ON) gives the TERMINAL to the verb, because the first
ON makes the account SDRADMIN and asks its Windows password; F (OFF) runs through the routine, as Linux's both do.  The guide is SD Core for Windows' own, in the SDCore4WindowsDocs clone beside this repository (SD_DOCS_ADMIN to
point elsewhere).

WHAT THIS IS, AND WHAT IT IS NOT.  It reads the page's BASIC as text, with comments removed.  ***IT RUNS NOTHING, SO IT CANNOT SAY THAT A DOOR OPENS OR THAT A SERVER IS DEFINED***: opening the API's
socket and the firewall is SDSYS's elevated helper's, which no free check is; that is a cycle and the page on a real install.  What a text check is for: the properties that make the page a FRONT END -
it opens the base for the administrator before it reads, the reports are the two verbs with NO keyword (they report and change nothing), a change is a keyword the page checked, behind a box,
and turning a door ON wants a word typed, DELETE.SERVER is asked of a server that is in the list under a name that passed the same test as the routine, SET.SERVER is built from fields checked in
the order that keeps a bad one out of the sentence and is run by the verb on the terminal (never with NO.QUERY, so that its own questions are asked of a person), the page writes nothing itself and
reads the netservers file only through !netdefs READ.  Those are ORDER and ABSENCE, and an edit that moves one still compiles.

--selftest breaks each invariant in the way an edit plausibly would and requires a check to notice; a mutant that nothing catches is a failure of the self-test.
"""

import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SD64 = os.path.normpath(os.path.join(HERE, ".."))
SDSYS = os.path.join(SD64, "sdsys")
GPL = os.path.join(SDSYS, "gpl.bp")
DOCS = os.path.join(os.environ.get("SD_DOCS_ADMIN") or os.path.normpath(os.path.join(SD64, "..", "..", "..", "SDCore4WindowsDocs", "Administrator", "markdown")),
                    "05-remote-access-and-the-machine.md")
FILES = {
    "page": os.path.join(GPL, "tool_remote"),
    "voc": os.path.join(SDSYS, "voc_template", "tool.remote"),
    "help": os.path.join(SDSYS, "helptext", "tool.remote.page"),
    "doc": DOCS,
}
NEWVOC = os.path.join(SDSYS, "newvoc", "tool.remote")
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
    ck("RM0", "NULL CASE: the page, the VOC entry, the help record and the guide were found and are not empty (a check on nothing would pass)",
       len(pg) > 9000 and raw["voc"].strip() != "" and len(raw["help"].split("\n")) >= 4 and raw["doc"].strip() != "", "%d" % len(pg))
    ck("RM1", "the page is an internal program catalogued as $tool_remote, SDSYS's VOC has the verb for it, and the shared VOC (newvoc) has NO tool.remote",
       re.search(r"^\$internal\s*\nprogram \$tool_remote\s*\n\$catalog \$tool_remote\b", pg, re.M) is not None and raw["voc"].split("\n")[:3] == ["V", "CA", "$tool_remote"] and raw["newvoc_has"] == "",
       repr((raw["voc"][:30], raw["newvoc_has"])))
    i_open = pg.find("call $tk_open('tool.remote', 'admin', ctx, err)")
    i_audit = pg.find("kernel(K$AUDIT, 'tool start app=tool.remote')")
    i_first = min([x for x in (pg.find("gosub read.all"), pg.find("call $tk_run("), pg.find("call !netdefs")) if x >= 0] or [10 ** 9])
    ck("RM2", "the page opens the toolkit's base for the ADMINISTRATOR first (a refusal is shown and the program stops), before it reads or runs anything; its one audit line says it started",
       0 < i_open < i_audit < i_first and re.search(r"call \$tk_open\('tool\.remote', 'admin', ctx, err\)\s*\n\s*if err # '' then\s*\n\s*display err\s*\n\s*stop\s*\n\s*end", pg) is not None and pg.count("K$AUDIT") == 1,
       "open %s audit %s first %s" % (i_open, i_audit, i_first))
    cr = block(pg, "confirm.and.run")
    ch = block(pg, "confirm.and.hand.over")
    ck("RM3", "the routine runs remote.api, remote.ssh, delete.server and remote.sdsys (one allow list) and nothing else: $tk_run directly after the confirm box guarded by res = 'run', and in run.report for the three reports; "
       "the one other way a verb is run is the terminal hand-over (`execute sent` once, after the box and after $tk_close); no $tk_runx, os.execute, perform or chain",
       re.findall(r"\ballow = '([^']*)'", pg) == ["remote.api remote.ssh delete.server remote.sdsys"] and pg.count("call $tk_run(allow,") == 2 and "$tk_runx" not in pg
       and re.search(r"call \$tk_confirm\(sent, el, typed, res, cmsg\)\s*\n\s*if res = 'run' then\s*\n\s*call \$tk_run\(allow, sent, out, stat, err\)", cr) is not None
       and len(re.findall(r"\bexecute\b", pg)) == 1 and re.search(r"call \$tk_confirm\(sent, el, typed, res, cmsg\)\s*\n\s*if res # 'run' then\s*\n\s*msg = cmsg\s*\n\s*return\s*\n\s*end\s*\n\s*call \$tk_close\(ctx\)\s*\n\s*execute sent", ch) is not None
       and not re.search(r"\b(os\.execute|perform|chain)\b", pg), "")
    ck("RM4", "THE PAGE WRITES NOTHING ITSELF: no write, delete, writeseq, openseq, matwrite; the servers file is read only through !netdefs READ (no other operation of it), and the register only to list names",
       not re.search(r"^\s*(write|writeseq|writeseqf|writev|writeu|delete|deleteseq|openseq|matwrite|matwriteu)\b", pg, re.M) and set(re.findall(r"call !netdefs\('([A-Z]+)'", pg)) == {"READ"}
       and pg.count("openpath @sdsys : @ds : 'accounts'") == 1 and "if id # 'sdsys' then" in block(pg, "read.accounts"), "")
    rr = block(pg, "run.report")
    ra = block(pg, "read.all")
    ck("RM5", "the three reports are run as exactly 'remote.api', 'remote.ssh' and 'remote.sdsys' with NO keyword (so they report and change nothing), in read.all and nowhere else; a change is built only in do.api, do.ssh and do.sdsys",
       "cmd = 'remote.api'" in ra and "cmd = 'remote.ssh'" in ra and "cmd = 'remote.sdsys'" in ra and pg.count("cmd = ") == 3 and "call $tk_run(allow, cmd, rep, rstat, rerr)" in rr and pg.count("sent = 'remote.api ' : aw") == 1 and pg.count("sent = 'remote.ssh ' : sw") == 1, ra[:200])
    da = block(pg, "do.api")
    ds = block(pg, "do.ssh")
    ck("RM6", "A takes on, local or off only and S on or off only, tested BEFORE the sentence; turning a door ON wants the word OPEN typed (typed = 'OPEN' for on, null otherwise), and the box says what ON opens; "
       "A gives the terminal to REMOTE.API (its restart question is a person's to answer) and says a restart ends every session, while S runs through the routine",
       "if aw # 'on' and aw # 'local' and aw # 'off' then" in da and "if sw # 'on' and sw # 'off' then" in ds and da.count("typed = 'OPEN'") == 1 and ds.count("typed = 'OPEN'") == 1
       and re.search(r"case aw = 'on'\s*\n\s*typed = 'OPEN'", da) is not None and re.search(r"if sw = 'on' then\s*\n\s*typed = 'OPEN'", ds) is not None
       and 0 < da.find("if aw # 'on'") < da.find("sent = ") and 0 < ds.find("if sw # 'on'") < ds.find("sent = ") and "other computers on the network may connect" in da and "firewall" in ds
       and da.count("gosub confirm.and.hand.over") == 1 and "gosub confirm.and.run" not in da and "ends every session" in da
       and ds.count("gosub confirm.and.run") == 1 and "gosub confirm.and.hand.over" not in ds, da[:200])
    dx = block(pg, "do.delete")
    ck("RM7", "X deletes only a server that is in the list (the cursor on a row), under a name that passes plain.word BEFORE the sentence, and sends exactly 'delete.server ' + that name",
       "if nsrv = 0 or ci < 1 or ci > nsrv then" in dx and dx.count("sent = ") == 1 and "sent = 'delete.server ' : word" in dx and 0 < dx.find("gosub plain.word") < dx.find("if not(plain) then") < dx.find("sent = ") and "d = defs<ci>\n   word = d<1, 1>" in dx, dx[:200])
    dn = block(pg, "do.new")
    order = ["s.name = downcase", "s.host = downcase", "s.port = trim", "s.acc = trim", "s.pin = downcase", "s.mode = downcase", "s.accts = downcase", "sent = 'set.server '"]
    pos = [dn.find(o) for o in order]
    ck("RM8", "N checks every field in the order the verb lists them (name, host, port, account, pin, mode, local accounts) and builds the sentence only after all of them; the name is a lower case letter then letters and digits (16 at most), "
       "the host has only letters, digits, dot, hyphen and colon and does not start with a hyphen or a dot, the port is 1 to 65535, the pin is the word connect or 64 hexadecimal digits, the mode read or write, and each local account is a USER account of the list",
       all(x > 0 for x in pos) and pos == sorted(pos) and "s.name[1, 1] >= 'a' and s.name[1, 1] <= 'z'" in dn and "len(s.name) <= 16" in dn and "index('abcdefghijklmnopqrstuvwxyz0123456789.-:', s.host[q, 1], 1) = 0" in dn
       and "s.host[1, 1] # '-' and s.host[1, 1] # '.'" in dn and "(s.port + 0) < 1 or (s.port + 0) > 65535" in dn and "ok = (s.pin = 'connect')" in dn and "len(s.pin) = 64" in dn and "index('0123456789abcdef', s.pin[q, 1], 1) = 0" in dn
       and "s.mode # 'read' and s.mode # 'write' then" in dn and 0 < dn.find("call $tk_form('run'") < dn.find("call $tk_form('say'") < dn.rfind("call $tk_form('close'") < dn.find("sent = ") and dn.count("call $tk_form('close'") == 2 and "if index(@fm : unames : @fm, @fm : wd : @fm, 1) = 0 then ok = 0" in dn, str(pos))
    ck("RM9", "SET.SERVER is run by the VERB on the terminal and never with NO.QUERY (its replace question and its trust-this-key question are a person's to answer): the sentence has no no.query, ends in the hand-over, and the accounts clause is added only when accounts were given",
       "no.query" not in dn and dn.count("gosub confirm.and.hand.over") == 1 and "if s.accts # '' then sent := ' accounts ' : s.accts" in dn and dn.count("sent = ") == 1, dn[-300:])
    ck("RM10", "the hand-over gives the terminal back in order: the box, $tk_close, the verb, a pause for Enter, $tk_open for the ADMINISTRATOR again (a refusal there ends the page), the context regenerated, everything read and drawn again",
       0 < ch.find("call $tk_confirm") < ch.find("call $tk_close(ctx)") < ch.find("execute sent") < ch.find("input junk") < ch.find("call $tk_open('tool.remote', 'admin', ctx, err)") < ch.find("gen += 1") < ch.find("gosub read.all") < ch.find("gosub draw.all") and "done = 1" in ch, ch[:200])
    br = block(pg, "build.rows")
    sl = block(pg, "session.line")
    rl = block(pg, "route.line")
    ck("RM11", "the views: 1 the doors' own words, 2 one row for each USER account (the doors ssh, api, files, files-write, files-admin and the NET gate read through $tk_gates, the API winning over the files-only route in the words), "
       "3 the servers from !netdefs with the pin shortened to 16 digits, 4 the sessions with their kind from the flags, 5 the [api] section of the settings report",
       "case view = 1" in br and "case view = 2" in br and "case view = 3" in br and "case view = 4" in br and "pn[1, 16] : '...'" in br and "if gid = 'ssh' or gid = 'api' or gid = 'files' or gid = 'files-write' or gid = 'files-admin' or gid = 'net' then" in block(pg, "read.accounts")
       and "if gerr = '' and ainfo<1> = 'USER' then" in block(pg, "read.accounts") and "if cell.api = 'no' and cell.files = 'yes' then" in rl and "bitand(flg, USR$SDNET)" in sl and "bitand(flg, USR$SDVBSRVR)" in sl and "bitand(flg, USR$PHANTOM)" in sl and "inapi = (l[1, 5] = '[api]')" in ra, "")
    acts = sorted(set(re.findall(r"call \$tk_keys\('add', keys, '[^']+', '[^']+', '([a-z]+)'", pg)))
    ck("RM12", "the key table has exactly: help, doors, routes, servers, connected, tls, login, api, ssh, delete, new, sdsyson, sdsysoff, refresh, quit - and the Esc row that opens the menu bar (S.88 U4; it runs nothing); A and S act on the doors view only, X and N on the servers view only, O and F on the remote administration view only; the views are 1 to 6",
       acts == sorted(["help", "doors", "routes", "servers", "connected", "tls", "login", "api", "ssh", "delete", "new", "sdsyson", "sdsysoff", "refresh", "quit", "menu"])
       and "case nm = 'a' and view = 1" in pg and "case nm = 's' and view = 1" in pg and "case nm = 'x' and view = 3" in pg
       and "case nm = 'n' and view = 3" in pg and "case (nm = 'o' or nm = 'f') and view = 6" in pg and "case nm >= '1' and nm <= '6' and len(nm) = 1" in pg and "case nm = 'f1' or nm = '?'" in pg, " ".join(acts))
    dsd = block(pg, "do.sdsys")
    ck("RM16", "RELEASE_1.1 202, the remote administration view (Linux S.106): the two sentences are FIXED words (nothing typed reaches them); ON, which loosens, wants OPEN typed and GIVES THE TERMINAL to the verb "
       "(WINDOWS: the first ON makes SDRADMIN and asks its password); OFF runs through the routine after its box; the page parses no secret=, recovery= or authenticator line",
       sorted(re.findall(r"sent = '([^']*)'", dsd)) == ["remote.sdsys off", "remote.sdsys on"] and dsd.count("sent = ") == 2 and dsd.count("typed = 'OPEN'") == 1
       and re.search(r"sent = 'remote.sdsys on'\s*\n\s*typed = 'OPEN'", dsd) is not None and dsd.count("gosub confirm.and.hand.over") == 1 and dsd.count("gosub confirm.and.run") == 1
       and 0 < dsd.find("sent = 'remote.sdsys on'") < dsd.find("gosub confirm.and.hand.over") < dsd.find("sent = 'remote.sdsys off'") < dsd.find("gosub confirm.and.run")
       and "view = 6" in pg and not re.search(r"secret=|recovery=|authenticator", pg.lower()), dsd[:200])
    ck("RM13", "the page waits for a key with no timeout and reads again only when it opens, on F5 and after a command or a hand-over",
       "screen key returning nm" in pg and "timeout" not in pg and pg.count("gosub read.all") == 4, "read.all x%d" % pg.count("gosub read.all"))
    ck("RM14", "the page has a [?] and F1, ? and a click show tool.remote.page, whose record exists with a title, the remote access page of the administrator guide (which has a section on tool.remote) and a body",
       pg.count("'tool.remote.page'") == 2 and "call $tk_help('mark', mk.x, mk.y, 0, 0)" in pg and "call $tk_help('hit', mev, mk.x, mk.y, hit.m)" in pg and raw["help"].split("\n")[0].strip() != ""
       and raw["help"].split("\n")[1].strip() == "administrator-05-remote-access-and-the-machine" and raw["help"].split("\n")[2].strip() != "" and "## Everything that reaches SD from outside, on one screen: `tool.remote`" in raw["doc"], "")
    dl = block(pg, "draw.all")
    dsl = block(pg, "draw.list")
    dd = block(pg, "draw.detail")
    pwd = block(pg, "plain.word")
    ld = block(pg, "lay.declare")
    lg = block(pg, "lay.get")
    ck("RM15", "the layout is the service's (S.88 L2): three panes declared at the 140 by 43 sizes (rows 1-6, 7-26, 27-39: 138 by 6, 138 by 20 stretching, 138 by 13), the boxes drawn at the panes' rectangles, the top text 6 narrower than the box's text so the [?] is clear, "
             "the header under the list's border, the rows counted from the pane (VR = list height - 3, 17 at 140 by 43; DV = detail height - 2, 11), every text as wide as the box's text (tw = width - 4, 134), the layout declared again after the terminal came back; plain.word is the routine's own test",
       "'top' : @vm : 1 : @vm : 1 : @vm : 6 : @vm : 138 : @vm : '' : @vm : '' : @vm : '' : @vm : 'stretch'" in ld and "'list' : @vm : 2 : @vm : 1 : @vm : 20 : @vm : 138 : @vm : '' : @vm : 'stretch' : @vm : 1 : @vm : 'stretch'" in ld
       and "'detail' : @vm : 3 : @vm : 1 : @vm : 13 : @vm : 138 : @vm : '' : @vm : '' : @vm : '' : @vm : 'stretch'" in ld and "call $tk_layout('declare', ctx, d, lay.err)" in ld
       and "screen box at top.x,top.y size top.w,top.h" in dl and "screen box at lst.x,lst.y size lst.w,lst.h" in dl and "screen box at det.x,det.y size det.w,det.h" in dl
       and "VR = lst.h - 3" in lg and "DV = det.h - 2" in lg and "tw = lst.w - 4" in lg and "mk.x = top.x + top.w - 5" in lg and "mk.y = top.y + 1" in lg
       and "attr 'bold' width tw - 6" in block(pg, "draw.top") and "at tx,lst.y + 1 attr 'header'" in dsl and "at tx,lst.y + 1 + r attr rat width tw" in dsl and "if n <= DV then" in dd and "at tx,det.y + n width tw" in dd
       and "call $tk_layout('refresh', ctx, '', lay.chg)\n            gosub lay.get" in pg and "gosub lay.declare" in pg.rpartition("call $tk_open(")[2] and pg.count("call $tk_open(") == 2
       and re.search(r"\b(134|138|136|17)\b", re.sub(r"(?m)^   d<\d> = .*$", "", pg)) is None
       and ("index('%s', word[pi, 1], 1) = 0" % SAFE) in pwd, "")
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
    ("the page is opened for anyone", "RM2", sub("page", "call $tk_open('tool.remote', 'admin', ctx, err)", "call $tk_open('tool.remote', '', ctx, err)")),
    ("the page runs a report before it opens the base", "RM2", sub("page", "   call $tk_open('tool.remote', 'admin', ctx, err)\n   if err # '' then\n      display err\n      stop\n   end\n", "   call $tk_run(allow, 'remote.api', o0, s0, e0)\n   call $tk_open('tool.remote', 'admin', ctx, err)\n   if err # '' then\n      display err\n      stop\n   end\n")),
    ("an ordinary account gets the verb", "RM1", setkey("newvoc_has", "1")),
    ("the page may run another command", "RM3", sub("page", "allow = 'remote.api remote.ssh delete.server remote.sdsys'", "allow = 'remote.api remote.ssh delete.server remote.sdsys set.server'")),
    ("the page runs with the loose routine", "RM3", sub("page", "      call $tk_run(allow, sent, out, stat, err)\n      gosub read.all", "      call $tk_runx(allow, sent, out, stat, err)\n      gosub read.all")),
    ("the box is skipped", "RM3", sub("page", "   call $tk_confirm(sent, el, typed, res, cmsg)\n   if res = 'run' then", "   res = 'run'\n   if res = 'run' then")),
    ("the terminal is handed over before the box", "RM3", sub("page", "   call $tk_confirm(sent, el, typed, res, cmsg)\n   if res # 'run' then\n      msg = cmsg\n      return\n   end\n   call $tk_close(ctx)\n   execute sent", "   call $tk_close(ctx)\n   execute sent")),
    ("a second execute", "RM3", sub("page", "   keys = ''\n", "   execute 'who' capturing xx\n   keys = ''\n")),
    ("the page writes a record", "RM4", sub("page", "   keys = ''\n", "   write 'x' to acc.f, 'y'\n   keys = ''\n")),
    ("the page rewrites the servers", "RM4", sub("page", "   call !netdefs('READ', defs, nderr)", "   call !netdefs('WRITE', defs, nderr)")),
    ("the report is run with a keyword", "RM5", sub("page", "   cmd = 'remote.api'\n", "   cmd = 'remote.api off'\n")),
    ("A takes any word", "RM6", sub("page", "   if aw # 'on' and aw # 'local' and aw # 'off' then", "   if 0 then")),
    ("on needs no typed word", "RM6", sub("page", "      case aw = 'on'\n         typed = 'OPEN'", "      case aw = 'on'\n         typed = ''")),
    ("ssh on needs no typed word", "RM6", sub("page", "   if sw = 'on' then\n      typed = 'OPEN'", "   if sw = 'on' then\n      typed = ''")),
    ("A runs REMOTE.API through the routine, where its restart question has nobody to answer it", "RM6", sub("page", "takes effect at once.'\n   gosub confirm.and.hand.over", "takes effect at once.'\n   gosub confirm.and.run")),
    ("A no longer says a restart ends every session", "RM6", sub("page", "'A restart ends every session, this one too;", "'A restart may follow;")),
    ("S hands the terminal over", "RM6", sub("page", "takes effect at once.'\n   gosub confirm.and.run", "takes effect at once.'\n   gosub confirm.and.hand.over")),
    ("X deletes without a server under the cursor", "RM7", sub("page", "   if nsrv = 0 or ci < 1 or ci > nsrv then\n      msg = 'there is no server to delete'\n      return\n   end\n", "")),
    ("X sends the first server", "RM7", sub("page", "   d = defs<ci>\n   word = d<1, 1>\n   gosub plain.word", "   d = defs<1>\n   word = d<1, 1>\n   gosub plain.word")),
    ("X skips the name test", "RM7", sub("page", "   word = d<1, 1>\n   gosub plain.word\n   if not(plain) then", "   word = d<1, 1>\n   plain = 1\n   if not(plain) then")),
    ("a server name may start with a digit", "RM8", sub("page", "s.name[1, 1] >= 'a' and s.name[1, 1] <= 'z'", "s.name[1, 1] >= '0'")),
    ("a host may start with a hyphen", "RM8", sub("page", " and s.host[1, 1] # '-' and s.host[1, 1] # '.')", ")")),
    ("a port above 65535", "RM8", sub("page", "(s.port + 0) > 65535", "(s.port + 0) > 99999")),
    ("any pin is accepted", "RM8", sub("page", "   if not(ok) and len(s.pin) = 64 then", "   if not(ok) and len(s.pin) > 0 then")),
    ("the local accounts are not tested", "RM8", sub("page", "         if index(@fm : unames : @fm, @fm : wd : @fm, 1) = 0 then ok = 0\n", "")),
    ("SET.SERVER is run with no.query", "RM9", sub("page", "   sent = 'set.server ' : s.name : ' ' : s.host : ' ' : s.port : ' ' : s.acc : ' ' : s.pin : ' ' : s.mode\n", "   sent = 'set.server ' : s.name : ' ' : s.host : ' ' : s.port : ' ' : s.acc : ' ' : s.pin : ' ' : s.mode : ' no.query'\n")),
    ("the page does not take the screen back", "RM10", sub("page", "   call $tk_open('tool.remote', 'admin', ctx, err)\n   if err # '' then\n      display err\n      done = 1\n      return\n   end\n", "")),
    ("a session is of one kind", "RM11", sub("page", "      case bitand(flg, USR$SDNET)\n         kind = 'sdnet'\n", "")),
    ("an other account is listed in the routes", "RM11", sub("page", "if gerr = '' and ainfo<1> = 'USER' then", "if gerr = '' then")),
    ("a key is added to the table", "RM12", sub("page", "   call $tk_keys('add', keys, 'n', 'new', 'new', 'Servers', 1)\n", "   call $tk_keys('add', keys, 'n', 'new', 'new', 'Servers', 1)\n   call $tk_keys('add', keys, 'k', 'kill', 'kill', '', 1)\n")),
    ("A acts on every view", "RM12", sub("page", "      case nm = 'a' and view = 1\n", "      case nm = 'a'\n")),
    ("O and F act on every view", "RM12", sub("page", "      case (nm = 'o' or nm = 'f') and view = 6\n", "      case (nm = 'o' or nm = 'f')\n")),
    ("the sixth view key is lost", "RM12", sub("page", "      case nm >= '1' and nm <= '6' and len(nm) = 1", "      case nm >= '1' and nm <= '5' and len(nm) = 1")),
    ("the login view's report is run with a keyword", "RM5", sub("page", "   cmd = 'remote.sdsys'\n", "   cmd = 'remote.sdsys on'\n")),
    ("remote administration is opened with no typed word", "RM16", sub("page", "      sent = 'remote.sdsys on'\n      typed = 'OPEN'\n", "      sent = 'remote.sdsys on'\n      typed = ''\n")),
    ("ON runs through the routine, where its password prompt has nobody to answer it", "RM16", sub("page", "Shut again with F.'\n      gosub confirm.and.hand.over", "Shut again with F.'\n      gosub confirm.and.run")),
    ("OFF is handed the terminal", "RM16", sub("page", "as delivered.'\n      gosub confirm.and.run", "as delivered.'\n      gosub confirm.and.hand.over")),
    ("the sentence takes a typed word", "RM16", sub("page", "      sent = 'remote.sdsys off'\n", "      sent = 'remote.sdsys ' : sw\n")),
    ("the page reads a secret", "RM16", sub("page", "   sd.out = rep\n", "   sd.out = rep\n   if index(rep, 'secret=', 1) then msg = 'x'\n")),
    ("the page reads on a timer", "RM13", sub("page", "      screen key returning nm\n", "      screen key timeout 3 returning nm\n")),
    ("the help key names a record that does not exist", "RM14", sub("page", "call $tk_help('box', 'tool.remote.page', hm, 0, 0)\n         if hm # '' then msg = hm\n      case nm = 'f6'", "call $tk_help('box', 'tool.remote.nopage', hm, 0, 0)\n         if hm # '' then msg = hm\n      case nm = 'f6'")),     # 1 Nov 26: F6 (the AI line) is the case after help
    ("the help record names no page", "RM14", sub("help", "05-remote-access-and-the-machine", "")),
    ("the list box overruns the detail", "RM15", sub("page", "d<2> = 'list' : @vm : 2 : @vm : 1 : @vm : 20 :", "d<2> = 'list' : @vm : 2 : @vm : 1 : @vm : 21 :")),
    ("the page draws a box at a literal place again", "RM15", sub("page", "screen box at lst.x,lst.y size lst.w,lst.h title t.list", "screen box at 1,7 size 138,20 title t.list")),
    ("the terminal comes back and the panes are not declared again", "RM15", sub("page", "   gosub lay.declare                                           ;* the new context holds no panes; the window may be another size\n", "")),
    ("the resize no longer asks the layout again", "RM15", sub("page", "            call $tk_layout('refresh', ctx, '', lay.chg)\n", "")),
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
    print("test-toolremote-units: tree %s" % SDSYS)
    if not raw["page"]:
        print("test-toolremote-units: CANNOT RUN - %s is not there" % FILES["page"])
        return 2
    rows = checks(raw)
    bad = report(rows)
    print("\ntest-toolremote-units: %d passed, %d failed" % (len(rows) - bad, bad))
    rc = 1 if bad else 0
    if "--selftest" in argv:
        rc = (selftest(raw) or rc)
    return rc


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
