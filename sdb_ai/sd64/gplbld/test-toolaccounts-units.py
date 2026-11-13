#!/usr/bin/env python3
"""test-toolaccounts-units.py - the accounts page, TOOL.ACCOUNTS (`gpl.bp/tool_accounts`), as invariants read off the source (S.75, administrator app A3).  Free: no install, no elevation, no sd.

    python C:/Users/Don/Projects/SDCore4Windows/sdb_ai/sd64/gplbld/test-toolaccounts-units.py [--selftest]

The Windows carry (10 Nov 2026, RELEASE_1.1 221) of Linux's guard of the same name.  Windows differences, each a check: the docs are
SDCore4WindowsDocs (SD_DOCS_CHECKOUT, else the checkout beside this one; absent, the guard says NO TREE and exits 2); an OTHER account's
directory is a full Windows path with forward slashes ($tk_runx refuses a backslash); X asks no REMOVE.HOME question (Windows DELETE.ACCOUNT
removes the profile of a Windows user SD made anyway); the page says Windows, never Linux, and its messages are 12870 and 15045 (Linux
11865 and 14045).

WHAT THIS IS, AND WHAT IT IS NOT.  It reads the page's BASIC as text, with comments removed.  ***IT RUNS NOTHING, SO IT CANNOT SAY THAT AN ACCOUNT IS MADE OR REMOVED***: creating and deleting an
account make and remove Windows users and groups, which only a real install can show.  What a text check is for: the properties that make the page a FRONT END - it opens the base for the
administrator before it reads, every command it builds is built from a name that passed the same test as the routines apply and in the order that keeps a bad name out of the sentence, it never
sends a destructive command without the account's name typed first, it hands the TERMINAL to a verb only after the box was answered Run and takes the screen again after it, it asks for a person
only on a group account, it writes nothing itself, and it never lists or changes SDSYS.  Those are ORDER and ABSENCE, and an edit that moves one still compiles.

--selftest breaks each invariant in the way an edit plausibly would and requires a check to notice; a mutant that nothing catches is a failure of the self-test.
"""

import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SD64 = os.path.normpath(os.path.join(HERE, ".."))
SDSYS = os.path.join(SD64, "sdsys")
GPL = os.path.join(SDSYS, "gpl.bp")
DOCROOT = os.environ.get("SD_DOCS_CHECKOUT") or os.path.normpath(os.path.join(SD64, "..", "..", "..", "SDCore4WindowsDocs"))
DOCS = os.path.join(DOCROOT, "Administrator", "markdown", "01-accounts-and-security.md")
FILES = {
    "page": os.path.join(GPL, "tool_accounts"),
    "voc": os.path.join(SDSYS, "voc_template", "tool.accounts"),
    "help": os.path.join(SDSYS, "helptext", "tool.accounts.page"),
    "doc": DOCS,
}
NEWVOC = os.path.join(SDSYS, "newvoc", "tool.accounts")
SAFE = "abcdefghijklmnopqrstuvwxyz0123456789.-_"
MSGS = (12870, 15045)


def load():
    raw = {}
    for k, p in FILES.items():
        try:
            with open(p, encoding="latin-1") as f:
                raw[k] = f.read()
        except OSError:
            raw[k] = ""
    raw["newvoc_has"] = "1" if os.path.exists(NEWVOC) else ""
    raw["msgs"] = "".join("1" if os.path.exists(os.path.join(SDSYS, "messages", str(n))) else "0" for n in MSGS)
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


WINPATH = "not(alpha(pth[1, 1])) or pth[2, 1] # ':' or pth[3, 1] # '/' or index(pth, '\\', 1) > 0 or index(pth, ' ', 1) > 0 or len(pth) > 200"


def checks(raw):
    rows = []

    def ck(i, what, ok, detail=""):
        rows.append((i, what, bool(ok), detail))

    pg = strip_bas(raw["page"])
    ck("AC0", "NULL CASE: the page, the VOC entry, the help record and the guide were found and are not empty (a check on nothing would pass)",
       len(pg) > 8000 and raw["voc"].strip() != "" and len(raw["help"].split("\n")) >= 4 and raw["doc"].strip() != "", "%d" % len(pg))
    ck("AC1", "the page is an internal program catalogued as $tool_accounts, SDSYS's VOC has the verb for it, and the shared VOC (newvoc) has NO tool.accounts",
       re.search(r"^\$internal\s*\nprogram \$tool_accounts\s*\n\$catalog \$tool_accounts\b", pg, re.M) is not None and raw["voc"].split("\n")[:3] == ["V", "CA", "$tool_accounts"] and raw["newvoc_has"] == "",
       repr((raw["voc"][:30], raw["newvoc_has"])))
    i_open = pg.find("call $tk_open('tool.accounts', 'admin', ctx, err)")
    i_audit = pg.find("kernel(K$AUDIT, 'tool start app=tool.accounts')")
    i_first = min([x for x in (pg.find("openpath"), pg.find("call !listu"), pg.find("call $tk_gates"), pg.find("gosub read.all")) if x >= 0] or [10 ** 9])
    ck("AC2", "the page opens the toolkit's base for the ADMINISTRATOR first (a refusal is shown and the program stops), before it reads anything; its one audit line says it started",
       0 < i_open < i_audit < i_first and re.search(r"call \$tk_open\('tool\.accounts', 'admin', ctx, err\)\s*\n\s*if err # '' then\s*\n\s*display err\s*\n\s*stop\s*\n\s*end", pg) is not None and pg.count("K$AUDIT") == 1,
       "open %s audit %s first %s" % (i_open, i_audit, i_first))
    cr = block(pg, "confirm.and.run")
    ch = block(pg, "confirm.and.hand.over")
    ck("AC3", "the commands run through the routines are modify.account and create.account only (one allow list), through $tk_run or $tk_runx directly after the confirm box and guarded by res = 'run', each exactly once; "
       "the only other way a verb is run is the terminal hand-over, which is `execute sent` once, after the box and after $tk_close; nothing else executes, performs or chains",
       re.findall(r"\ballow = '([^']*)'", pg) == ["modify.account create.account"] and pg.count("call $tk_run(allow, sent, out, stat, err)") == 1 and pg.count("call $tk_runx(allow, sent, out, stat, err)") == 1
       and re.search(r"call \$tk_confirm\(sent, el, typed, res, cmsg\)\s*\n\s*if res = 'run' then\s*\n\s*if use\.x then\s*\n\s*call \$tk_runx", cr) is not None
       and len(re.findall(r"\bexecute\b", pg)) == 1 and re.search(r"call \$tk_confirm\(sent, el, typed, res, cmsg\)\s*\n\s*if res # 'run' then\s*\n\s*msg = cmsg\s*\n\s*return\s*\n\s*end\s*\n\s*call \$tk_close\(ctx\)\s*\n\s*execute sent", ch) is not None
       and not re.search(r"\b(os\.execute|perform|chain)\b", pg), "")
    ck("AC4", "THE PAGE WRITES NOTHING ITSELF: no write, delete, writeseq, openseq, matwrite, no ospath with OS$DELETE or OS$CHOWN; the register is opened only to be read and SDSYS is never listed",
       not re.search(r"\b(write|writeseq|writeseqf|writev|writeu|delete|deleteseq|openseq|matwrite|matwriteu|overwrite|append)\b", pg.replace("delete.account", "").replace("delperson", "").replace("sub.word = 'delete'", "").replace("'delete'", "").replace("do.delete", "").replace("case nm = 'delete'", ""))
       and "if id # 'sdsys' then" in block(pg, "read.all") and pg.count("openpath @sdsys : @ds : 'accounts'") == 3, "")
    pwd = block(pg, "plain.word")
    ck("AC5", "plain.word lets through exactly what $tk_run lets through (a-z, 0-9, dot, dash, underscore), and at most 32 characters, and refuses an empty name",
       ("index('%s', word[pi, 1], 1) = 0" % SAFE) in pwd and "plain = (word # '' and len(word) <= 32)" in pwd, pwd[:160])
    su = block(pg, "do.suspend")
    ck("AC6", "S sends 'modify.account <name> suspended' or '... unsuspended' (whichever the account is not), for an account of the list, after the name passed plain.word and before anything else is built",
       su.count("sent = ") == 2 and "sent = 'modify.account ' : anm<ci> : ' unsuspended'" in su and "sent = 'modify.account ' : anm<ci> : ' suspended'" in su and "if asusp<ci> = 1 then" in su and 0 < su.find("gosub plain.word") < su.find("if not(plain) then") < su.find("sent = "), su[:200])
    pe = block(pg, "do.person")
    ck("AC7", "A and R work on a GROUP account only (refused in words for any other kind), ask for a Windows user whose name passes plain.word BEFORE the sentence, and send 'modify.account <group> add|delete <user>'",
       "if akind<ci> # 'GROUP' then" in pe and "sent = 'modify.account ' : anm<ci> : ' ' : sub.word : ' ' : word" in pe and pe.count("sent = ") == 1 and 0 < pe.find("if akind<ci> # 'GROUP' then") < pe.find("screen ask") < pe.find("gosub plain.word", pe.find("screen ask")) < pe.find("sent = ")
       and "sub.word = 'add'" in pg and "sub.word = 'delete'" in pg, pe[:200])
    cc = block(pg, "do.create")
    ck("AC8", "C asks the kind (user, group or other only), a name that passes plain.word and is not an account already (nor sdsys), and then what the kind needs, in that order and BEFORE any sentence: a user account the doors (none, ssh, api or both), "
       "an other account a full Windows path with forward slashes and no space or backslash; a group account is made with no.query after the box; a user account is handed the terminal",
       "case kd # 'user' and kd # 'group' and kd # 'other'" in cc and "call $tk_form('open', ctx, spec, fv, fo)" in cc and 0 < cc.find("call $tk_form('run'") < cc.find("call $tk_form('say'") < cc.rfind("call $tk_form('close'") < cc.find("sent = ")
       and cc.count("call $tk_form('close'") == 2 and "if px > 0 or word = 'sdsys' then" in cc and "rt # 'none' and rt # 'ssh' and rt # 'api' and rt # 'both'" in cc and WINPATH in cc
       and "sent = 'create.account group ' : nn : ' no.query'" in cc and "sent = 'create.account user ' : nn : ' ' : rt" in cc and "sent = 'create.account other ' : nn : ' ' : pth : ' no.query'" in cc
       and 0 < cc.find("case kd # 'user'") < cc.find("gosub plain.word") < cc.find("if px > 0") < cc.find("sent = ") and cc.count("gosub confirm.and.hand.over") == 1 and cc.count("gosub confirm.and.run") == 2 and "use.x = 1" in cc, cc[:200])
    dd = block(pg, "do.delete")
    ck("AC9", "X refuses a name that does not pass plain.word, asks NO REMOVE.HOME question (Windows removes the profile anyway), types the ACCOUNT'S OWN NAME into the box (typed = anm<ci>) before it can run, and hands the terminal to the verb",
       "gosub plain.word" in dd and "screen ask" not in dd and "remove.home" not in dd.lower() and "typed = anm<ci>" in dd and dd.count("gosub confirm.and.hand.over") == 1
       and 0 < dd.find("gosub plain.word") < dd.find("sent = 'delete.account '") < dd.find("typed = anm<ci>") < dd.find("gosub confirm.and.hand.over"), dd[:200])
    ck("AC10", "the hand-over gives the terminal back in order: the box, $tk_close, the verb, a pause for Enter, $tk_open for the ADMINISTRATOR again (a refusal there ends the page), the context regenerated, everything read and drawn again",
       0 < ch.find("call $tk_confirm") < ch.find("call $tk_close(ctx)") < ch.find("execute sent") < ch.find("input junk") < ch.find("call $tk_open('tool.accounts', 'admin', ctx, err)") < ch.find("gen += 1") < ch.find("gosub read.all") < ch.find("gosub draw.all")
       and "done = 1" in ch, ch[:200])
    acts = sorted(set(re.findall(r"call \$tk_keys\('add', keys, '[^']+', '[^']+', '([a-z]+)'", pg)))
    ck("AC11", "the key table has exactly: help, create, suspend, addperson, delperson, delete, refresh, quit, menu, find; the dispatch has C, S, A, R, X, F1/?, F5 and Ctrl-Q",
       acts == sorted(["help", "create", "suspend", "addperson", "delperson", "delete", "refresh", "quit", "menu", "find"]) and all(("case nm = '%s'" % k) in pg for k in ("c", "s", "a", "r", "x", "f5", "ctrl-q")) and "case nm = 'f1' or nm = '?'" in pg, " ".join(acts))
    ck("AC12", "the page waits for a key with no timeout and reads again only when it opens, on F5 and after a command or a hand-over",
       "screen key returning nm" in pg and "timeout" not in pg and pg.count("gosub read.all") == 4, "read.all x%d" % pg.count("gosub read.all"))
    ck("AC13", "the page has a [?] and F1, ? and a click show tool.accounts.page, whose record exists with a title, the accounts and security page of the administrator guide (which has a section on tool.accounts) and a body",
       pg.count("'tool.accounts.page'") == 2 and "call $tk_help('mark', top.x + top.w - 5, top.y + 1, 0, 0)" in pg and "call $tk_help('hit', mev, top.x + top.w - 5, top.y + 1, hit.m)" in pg and raw["help"].split("\n")[0].strip() != ""
       and raw["help"].split("\n")[1].strip() == "administrator-01-accounts-and-security" and raw["help"].split("\n")[2].strip() != "" and "### The accounts on one screen: `tool.accounts`" in raw["doc"], "")
    dl = block(pg, "draw.all")
    dsl = block(pg, "draw.list")
    dd2 = block(pg, "draw.detail")
    dc = block(pg, "declare.layout")
    gr = block(pg, "get.rects")
    ck("AC14", "the layout is the layout service's (S.88 L2): three panes declared at the 140 by 43 sizes (rows 6, 20 and 13 of 138), their rectangles asked of $tk_layout and drawn as boxes, also again after a verb was given the terminal (the new $tk_open has no panes); "
       "the top text narrower than its box so the [?] is clear, the list rows are the box's less 3 under a heading, the account under the cursor in the detail box's rows (less 2)",
       "ld<1> = 'counts' : @vm : 1 : @vm : 1 : @vm : 6 : @vm : 138" in dc and "ld<2> = 'list' : @vm : 2 : @vm : 1 : @vm : 20 : @vm : 138" in dc and "ld<3> = 'detail' : @vm : 3 : @vm : 1 : @vm : 13 : @vm : 138" in dc
       and "call $tk_layout('declare', ctx, ld, perr)" in dc and "VA = lst.h - 3" in gr and "DR = det.h - 2" in gr
       and "screen box at top.x,top.y size top.w,top.h" in dl and "screen box at lst.x,lst.y size lst.w,lst.h" in dl and "screen box at det.x,det.y size det.w,det.h" in dl
       and "attr 'bold' width ttw - 6" in block(pg, "draw.top") and re.search(r"call \$tk_open\('tool\.accounts', 'admin', ctx, err\)\s*\n\s*if err # '' then\s*\n\s*display err\s*\n\s*done = 1\s*\n\s*return\s*\n\s*end\s*\n(?:\s*call \$tk_aipage\('again', ctx, keys, '', '', aout\)[^\n]*\n)?\s*gen \+= 1\s*\n\s*ctx<TK\.C\.GEN> = gen\s*\n\s*gosub declare\.layout", pg) is not None
       and "at lst.x + 2,lst.y + 1 attr 'header'" in dsl and "at lst.x + 2,lst.y + 1 + r attr rat" in dsl and "for r = 1 to DR" in dd2 and "at det.x + 2,det.y + r width dtw" in dd2, "")
    used = sorted(set(int(n) for n in re.findall(r"sysmsg\((\d+)", pg)))
    ck("AC15", "WINDOWS: the page and its help say Windows and never Linux, a root helper or /etc; its messages are 12870 and 15045 (Linux 11865 and 14045 + 1005/1000), and both exist",
       "linux" not in pg.lower() and "root helper" not in pg and "/etc/" not in pg and "linux" not in raw["help"].lower() and "Windows" in pg and "Windows" in raw["help"]
       and used == list(MSGS) and raw["msgs"] == "11", repr((used, raw["msgs"])))
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
    ("the page is opened for anyone", "AC2", sub("page", "call $tk_open('tool.accounts', 'admin', ctx, err)", "call $tk_open('tool.accounts', '', ctx, err)")),
    ("the page reads before it opens the base", "AC2", sub("page", "   call $tk_open('tool.accounts', 'admin', ctx, err)\n   if err # '' then\n      display err\n      stop\n   end\n", "   openpath @sdsys : @ds : 'accounts' to acc0 else null\n   call $tk_open('tool.accounts', 'admin', ctx, err)\n   if err # '' then\n      display err\n      stop\n   end\n")),
    ("an ordinary account gets the verb", "AC1", setkey("newvoc_has", "1")),
    ("the page may run another command", "AC3", sub("page", "allow = 'modify.account create.account'", "allow = 'modify.account create.account delete.account'")),
    ("the box is skipped for the routines", "AC3", sub("page", "   call $tk_confirm(sent, el, typed, res, cmsg)\n   if res = 'run' then\n      if use.x then", "   res = 'run'\n   if res = 'run' then\n      if use.x then")),
    ("the terminal is handed over before the box", "AC3", sub("page", "   call $tk_confirm(sent, el, typed, res, cmsg)\n   if res # 'run' then\n      msg = cmsg\n      return\n   end\n   call $tk_close(ctx)\n   execute sent", "   call $tk_close(ctx)\n   execute sent")),
    ("a second execute", "AC3", sub("page", "   keys = ''\n", "   execute 'who' capturing xx\n   keys = ''\n")),
    ("the page writes a record", "AC4", sub("page", "   keys = ''\n", "   write 'x' to acc.f, 'y'\n   keys = ''\n")),
    ("SDSYS is listed", "AC4", sub("page", "         if id # 'sdsys' then\n            locate", "         if 1 then\n            locate")),
    ("the safe-word test lets a space through", "AC5", sub("page", "abcdefghijklmnopqrstuvwxyz0123456789.-_", "abcdefghijklmnopqrstuvwxyz0123456789.-_ ")),
    ("an empty name is a word", "AC5", sub("page", "plain = (word # '' and len(word) <= 32)", "plain = 1")),
    ("S always sends suspended", "AC6", sub("page", "      sent = 'modify.account ' : anm<ci> : ' unsuspended'", "      sent = 'modify.account ' : anm<ci> : ' suspended'")),
    ("S skips the safe-word test", "AC6", sub("page", "   word = anm<ci>\n   gosub plain.word\n   if not(plain) then\n      call $tk_badch(word, bad.ch)                   ;* 9 Nov 26 (S.186): say which character\n      if bad.ch = '' then bad.ch = 'more than 32 characters'\n      msg = 'this account name has ' : bad.ch : ', which this page will not put in a command; use modify.account at the prompt'\n      return\n   end\n   use.x = 0\n   typed = ''\n   el = ''\n   if asusp<ci> = 1 then", "   use.x = 0\n   typed = ''\n   el = ''\n   if asusp<ci> = 1 then")),
    ("A works on any kind of account", "AC7", sub("page", "   if akind<ci> # 'GROUP' then\n      msg = anm<ci> : ' is not a group account", "   if 0 then\n      msg = anm<ci> : ' is not a group account")),
    ("the person's name is not tested", "AC7", sub("page", "   word = trim(pu)\n   gosub plain.word\n   if not(plain) then", "   word = trim(pu)\n   plain = 1\n   if not(plain) then")),
    ("C allows any kind", "AC8", sub("page", "case kd # 'user' and kd # 'group' and kd # 'other'", "case 0")),
    ("C allows an account that exists", "AC8", sub("page", "if px > 0 or word = 'sdsys' then", "if 0 then")),
    ("C leaves the form open on every way out", "AC8", sub("page", "      if fans # 'ok' then\n         call $tk_form('close', ctx, '', '', '')\n", "      if fans # 'ok' then\n")),
    ("C does not say a refusal in the form", "AC8", sub("page", "      call $tk_form('say', ctx, fbad, fid, '')\n", "      msg = fbad\n")),
    ("C allows another door word", "AC8", sub("page", "rt # 'none' and rt # 'ssh' and rt # 'api' and rt # 'both'", "rt # 'none' and rt # 'root' and rt # 'ssh' and rt # 'api' and rt # 'both'")),
    ("C allows a relative path", "AC8", sub("page", WINPATH, "index(pth, ' ', 1) > 0 or len(pth) > 200")),
    ("C allows a backslash path that $tk_runx would refuse", "AC8", sub("page", "or index(pth, '\\', 1) > 0 ", "")),
    ("C keeps Linux's path rule", "AC8", sub("page", WINPATH, "pth[1, 1] # '/' or index(pth, ' ', 1) > 0 or len(pth) > 200")),
    ("a group account is made without no.query", "AC8", sub("page", "' no.query'\n         typed = ''\n         el = ''\n         el<-1> = 'A group account", "''\n         typed = ''\n         el = ''\n         el<-1> = 'A group account")),
    ("X needs no typed name", "AC9", sub("page", "   typed = anm<ci>\n", "   typed = ''\n")),
    ("X asks Linux's remove.home question", "AC9", sub("page", "   sent = 'delete.account ' : anm<ci>\n", "   sent = 'delete.account ' : anm<ci>\n   screen ask 'Also remove the home directory?' width 4 value 'n' title 'x' returning rh.a else return\n   if rh.a = 'y' then sent := ' remove.home'\n")),
    ("X skips the name test", "AC9", sub("page", "   word = anm<ci>\n   gosub plain.word\n   if not(plain) then\n      call $tk_badch(word, bad.ch)                   ;* 9 Nov 26 (S.186): say which character\n      if bad.ch = '' then bad.ch = 'more than 32 characters'\n      msg = 'this account name has ' : bad.ch : ', which this page will not put in a command; use delete.account at the prompt'\n      return\n   end\n", "")),
    ("the page does not take the screen back", "AC10", sub("page", "   call $tk_open('tool.accounts', 'admin', ctx, err)\n   if err # '' then\n      display err\n      done = 1\n      return\n   end\n   call $tk_aipage('again'", "   call $tk_aipage('again'")),
    ("the page does not read after a hand-over", "AC10", sub("page", "   gosub declare.layout                                         ;* the new $tk_open has no panes\n   gosub read.all\n   gosub draw.all\n   msg = 'back from '", "   gosub declare.layout                                         ;* the new $tk_open has no panes\n   gosub draw.all\n   msg = 'back from '")),
    ("a key is added to the table", "AC11", sub("page", "   call $tk_keys('add', keys, 'x', 'delete', 'delete', '', 1)\n", "   call $tk_keys('add', keys, 'x', 'delete', 'delete', '', 1)\n   call $tk_keys('add', keys, 'k', 'kill', 'kill', '', 1)\n")),
    ("the page reads on a timer", "AC12", sub("page", "      screen key returning nm\n", "      screen key timeout 3 returning nm\n")),
    ("the help key names a record that does not exist", "AC13", sub("page", "call $tk_help('box', 'tool.accounts.page', hm, 0, 0)\n         if hm # '' then msg = hm\n      case nm = 'f6'", "call $tk_help('box', 'tool.accounts.nopage', hm, 0, 0)\n         if hm # '' then msg = hm\n      case nm = 'f6'")),
    ("the help record names no page", "AC13", sub("help", "01-accounts-and-security", "")),
    ("the list box overruns the detail", "AC14", sub("page", "ld<2> = 'list' : @vm : 2 : @vm : 1 : @vm : 20", "ld<2> = 'list' : @vm : 2 : @vm : 1 : @vm : 21")),
    ("the layout is not declared again after a verb had the terminal", "AC14", sub("page", "   gosub declare.layout                                         ;* the new $tk_open has no panes\n   gosub read.all", "   gosub read.all")),
    ("the page keeps a Linux sentence", "AC15", sub("page", "Nothing changes in Windows.'", "Nothing changes in Linux.'")),
    ("the page keeps Linux's message number", "AC15", sub("page", "sysmsg(12870)", "sysmsg(11865)")),
    ("a message file is missing", "AC15", setkey("msgs", "10")),
    ("the help keeps Linux's /etc/group", "AC15", sub("help", "the Windows groups give them", "/etc/group give them (Linux)")),
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
    print("test-toolaccounts-units: tree %s" % SDSYS)
    print("test-toolaccounts-units: guide %s" % DOCS)
    if not raw["page"]:
        print("test-toolaccounts-units: CANNOT RUN - %s is not there" % FILES["page"])
        return 2
    if not raw["doc"]:
        print("test-toolaccounts-units: NO TREE - the guide is not there (set SD_DOCS_CHECKOUT to the SDCore4WindowsDocs checkout)")
        return 2
    rows = checks(raw)
    bad = report(rows)
    print("\ntest-toolaccounts-units: %d passed, %d failed" % (len(rows) - bad, bad))
    rc = 1 if bad else 0
    if "--selftest" in argv:
        rc = (selftest(raw) or rc)
    return rc


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
