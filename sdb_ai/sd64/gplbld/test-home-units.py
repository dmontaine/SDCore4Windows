#!/usr/bin/env python3
"""test-home-units.py - the home screen and where an account starts (S.75, plan .claude/plan-fullscreen-toolkit.md section 13), as invariants read off the source.

  python sdb_ai/sd64/gplbld/test-home-units.py
  python sdb_ai/sd64/gplbld/test-home-units.py --selftest
  (13 Nov 26 Windows port - from Linux b1d496df, RELEASE_1.1 254: message ids are Linux's + 1005; H17 and its mutant are out, because
  Windows has no sandbox-fromtree.py; the text below is Linux's.)

No sudo, no install, no sd.  Exit 0 every check passed, 1 a check failed, 2 it could not run.

WHAT IT HOLDS.  The sign-on hook is called only on a terminal (a piped session must never have its commands read as keys, and the bootstrap runs before the routine exists), at the
two places the plan names, and the routine itself refuses in the order the plan gives; the three programs that share the named common /TKHOME/ declare it alike; the Terminal tile
leaves the screen and sets the flag EXIT reads; EXIT does what QUIT does without the flag; SET.START.DEFAULT asks for the administrator first; MODIFY.ACCOUNT's three words, the
register field, the messages and the VOC entries are all there; the sandbox starts at the terminal; the panel draws only its own rows; the scroll bar's style is dark grey.
Since 2 Nov 26 (S.88 U9, H81-H84): the menu bar is the toolkit's ($tk_menubar, from the key table), every menu action has a key, a tile that is off has a reason, and / finds a
tile through $tk_pickrec 'list' without starting it.  `--selftest --from=N` runs the mutants from N on (M_U9 is the first of U9's).
9 Nov 26 (S.187): the Bypass programs tile ('viewers', tool.viewers) was removed from the home screen with the pdf verb (owner: pdf only works at the machine's own display); it is gone
from ADMIN_TILES, !viewlist is gone from H28a's list, and the mutant that built it for everyone now builds the Audit trail tile for everyone (the check that caught it keeps a mutant).

***IT READS THE SOURCE AS TEXT AND DOES NOT RUN BASIC.***  That the screen appears, the keys move the focus, EXIT comes back and a session starts where it should is
sandbox-home.py.  A green run here is evidence that nothing has deleted or reordered the code that makes those rows true.

--selftest mutates the source in the ways this could plausibly be broken and requires each mutation to be CAUGHT and each mutation to match its text exactly once.
"""

import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SDSYS = os.path.abspath(os.path.join(HERE, os.pardir, "sdsys"))
GPL = os.path.join(SDSYS, "gpl.bp")
PROGS = ("tool_home", "home_entry", "home_off", "home_pins", "home_recent", "mymenu", "tool_menus", "exit", "setstart", "settile", "cproc", "modifya", "sl_theme")
MSGS = tuple(str(n) for n in range(12868, 12892) if n != 12884) + tuple(str(n) for n in range(12961, 12967))       # 12884 was "tiles off for every account": there is no such setting (per account only); 12961-12966 are the sub-menus and the Recent group (26 Oct 26)
STANDARD = "editor ide terminal keys switch signout files voc dict query bulk catalog test recent".split()        # the ids SET.TILE and the menu management page know: the tiles the page draws, and recent (the group)


def strip(src):
    """The code: full-line comments and ;* tails removed."""
    out = []
    for ln in src.split("\n"):
        if ln.lstrip().startswith("*"):
            continue
        out.append(re.sub(r"\s*;\*.*$", "", ln))
    return "\n".join(out)


def ordered(text, *parts):
    """True when every part is found, each after the one before."""
    pos = -1
    for p in parts:
        k = text.find(p, pos + 1)
        if k < 0:
            return False
        pos = k
    return True


def between(text, a, b):
    i = text.find(a)
    if i < 0:
        return ""
    j = text.find(b, i + len(a))
    return text[i:j] if j >= 0 else text[i:]


def read(path):
    with open(path, encoding="latin-1") as f:
        return f.read()


def load():
    src = {n: read(os.path.join(GPL, n)) for n in PROGS}
    src["keys.h"] = read(os.path.join(SDSYS, "syscom", "keys.h"))
    src["files"] = {p: os.path.exists(os.path.join(SDSYS, p)) for p in (
        "newvoc/home", "newvoc/exit", "voc_template/home", "voc_template/exit", "voc_template/set.start.default", "newvoc/set.start.default", "voc_template/set.tile", "newvoc/set.tile", "newvoc/my.menu", "voc_template/my.menu", "voc_template/tool.menus", "newvoc/tool.menus")}
    src["tool.verbs"] = sorted(n for n in os.listdir(os.path.join(SDSYS, "voc_template")) if n.startswith("tool."))     # every administrator page has a verb of this form
    src["menu.n"] = read(os.path.join(SDSYS, "newvoc", "menu")) if os.path.exists(os.path.join(SDSYS, "newvoc", "menu")) else ""
    src["menu.t"] = read(os.path.join(SDSYS, "voc_template", "menu")) if os.path.exists(os.path.join(SDSYS, "voc_template", "menu")) else ""
    src["msgs"] = {n: read(os.path.join(SDSYS, "messages", n)) if os.path.exists(os.path.join(SDSYS, "messages", n)) else None for n in MSGS}
    return src


def checks(s):
    rows = []

    def ck(name, ok, detail=""):
        rows.append((name, bool(ok), detail))

    th = strip(s["tool_home"])
    he = strip(s["home_entry"])
    ex = strip(s["exit"])
    ss = strip(s["setstart"])
    cp = strip(s["cproc"])
    md = strip(s["modifya"])
    kh = strip(s["keys.h"])

    ck("H0 the sources were found (the null case: nothing to compare passes every row)", all(len(th) > 3000 for _ in [0]) and len(he) > 500 and len(ex) > 100 and len(ss) > 800 and len(cp) > 50000 and len(md) > 20000,
       "%d %d %d %d %d %d" % (len(th), len(he), len(ex), len(ss), len(cp), len(md)))
    ck("H1 the register field: ACC$START is field 16, and no other ACC$ name uses 16", re.search(r"\$define ACC\$START\s+16\b", kh) is not None
       and len(re.findall(r"\$define ACC\$[A-Z.]+\s+16\b", kh)) == 1)

    common = "common /tkhome/ hflag, hlogto, hstart, hrefused"
    ck("H2 tool_home, home_entry and exit declare the named common alike: " + common, all(common in x for x in (th, he, ex)))
    # 7 Nov 26 S.164 (owner: "Yes, always sign out"): a home screen that could not OPEN signs a menu-start session out, whatever the Terminal tile says.
    ck("H2b S.164: tool_home sets hrefused when $tk_open refuses at the START, and home_entry clears it before the EXECUTE and, after it, "
       "signs out with 15015 when it is set - BEFORE the Terminal tile is asked",
       th.count("call $tk_open('home', '', ctx, err)\n   if err # '' then\n      hrefused = 1") == 1
       and ordered(he, "hrefused = 0", "execute 'home'", "if hrefused then\n      display sysmsg(15015)", "execute 'quit'", "call !home_off(@who, off)"))
    # 7 Nov 26 S.168 (owner: "sdsys should start at the prompt always"): the administrator returns BEFORE the start setting is read, so no start word, default or
    #   window decides for it; it is the only session that does, and nothing else in the entry is asked first but the terminal, the API server and the LOGTO tests.
    ck("H2d S.168: home_entry returns for the administrator (K$ADMINISTRATOR) after the terminal / API / LOGTO tests and BEFORE it reads the register or start.default, "
       "and the administrator is asked nowhere else in it",
       ordered(he, "if why = 'logto' then", "if kernel(K$ADMINISTRATOR, -1) then return", "start = ''", "openpath @sdsys : @ds : 'accounts' to acc.f then", "openseq @sdsys : @ds : 'start.default'")
       and he.count("K$ADMINISTRATOR") == 1)
    rop = between(th, "\nreopen:\n", "\n   return\n")
    ck("H2c S.164: a reopen after a command does NOT sign out on a small window: it waits in $sl_guard's size lock while $sl_need says the window is too small, "
       "and only the lock's quit leaves (signing out a session's own screen), all before $tk_open is asked",
       ordered(rop, "loop\n      call $sl_need('home', TK.MINW, TK.MINH, need.msg, '')", "while need.msg # '' do",
               "call $sl_guard('home', TK.MINW, TK.MINH, TK.MINW - 1, TK.MINH - 1, guard.res, 'layout')", "if guard.res = 'quit' then",
               "if menu.session then hrefused = 1", "call $tk_open('home', '', ctx, err)"), rop[:300])

    ck("H3 tool_home: a session with no terminal is refused BEFORE the screen is asked for (@tty must begin /dev/, message 12868), and hlogto starts at 0",
       0 < th.find("if @tty[1, 5] # '/dev/' then") < th.find("sysmsg(12868)") < th.find("call $tk_open('home', '', ctx, err)") and "hlogto = 0" in th)
    ck("H3b ...it is a user app (audience null: the page differs, nobody is refused) and the administrator's page is the kernel's answer, not a name",
       "call $tk_open('home', '', ctx, err)" in th and "is.admin = kernel(K$ADMINISTRATOR, -1)" in th and "if is.admin then ctx<TK.C.AUD> = sysmsg(12808)" in th)
    cmds = re.findall(r"act = '(cmd:[^']*|menu:[^']*|terminal|switch|signout|back)' ; pal", th)       # the rows of the table (the case lines of start.tile also say act = ...)
    ADMIN_TILES = {"menus": "tool.menus", "audit": "tool.audit", "config": "tool.config", "backups": "tool.backups", "entries": "tool.entries",
                   "accounts": "tool.accounts", "sessions": "tool.sessions", "gates": "tool.gates", "jobs": "tool.jobs", "remote": "tool.remote", "ai": "tool.ai"}   # jobs: S.102 (2 Nov 26)
    PENDING_VERBS = {"tool.audit"}      # 13 Nov 26 Windows: tiles whose verbs RELEASE_1.1 247 owes (H28); tool.ai left it with RELEASE_1.1 246, which carries the verb
    DEV_TILES = {"files": "tool.files", "voc": "tool.voc", "dict": "tool.dict", "query": "tool.query", "bulk": "tool.bulk", "catalog": "tool.catalog", "test": "tool.test"}            # the development apps (DV), for every account; each adds its tile in the commit that builds it (plan 13.2)
    ck("H4 tool_home: every tile of the table has a fixed action (cmd:sed, ide, tool.keys, my.menu, the development apps and the eleven administrator pages), terminal, switch, signout or back (the Back tile of a sub-menu page); the ONLY other action is a person's own program (H25); and no tile of the delivered page opens a sub-menu (no menu:<name>)",
       sorted(cmds) == sorted(["cmd:sed", "cmd:ide", "terminal", "cmd:tool.keys", "switch", "signout", "back", "cmd:my.menu"] + ["cmd:" + v for v in ADMIN_TILES.values()] + ["cmd:" + v for v in DEV_TILES.values()]), repr(cmds))
    ck("H4b ...execute is given only a sentence from that table, 'quit', or the logto of an account picked from the register list",
       sorted(re.findall(r"execute ([^\n]+)", th)) == sorted(["sentence trapping aborts", "'quit'", "'quit'", "'logto ' : acct trapping aborts"]), repr(re.findall(r"execute ([^\n]+)", th)))     # 'quit' twice: sign out, and the confined account; the two that run what is not HOME's own are trapped (28 Oct 26, S.88 phase 2)
    fin = between(th, "\nfinish:\n", "\nreturn")
    t0 = fin.find("outcome = 'terminal'")
    ck("H5 the Terminal tile: the screen is given back FIRST, then the flag is set and the banner (12869) shown; the program then ends and the real prompt is there",
       0 < t0 < fin.find("call $tk_close(ctx)", t0) < fin.find("hflag = (if menu.session then 1 else 2)") < fin.find("sysmsg(12869)"), fin[:500])
    s0 = fin.find("outcome = 'signout'")
    ck("H5b ...sign out gives the screen back, then runs QUIT; every other way out gives it back too",
       0 < s0 < fin.find("call $tk_close(ctx)", s0) < fin.find("execute 'quit'", s0) and "case 1\n         call $tk_close(ctx)" in fin, fin[:500])
    ck("H5c ...WITH THE TERMINAL TILE OFF no way out of the screen but sign out leads to the prompt: that case is the FIRST of finish, gives the screen back (unless it was already) and runs QUIT",
       0 < fin.find("case terminal.off and outcome # 'signout'") < fin.find("case outcome = 'closed'") and 0 < fin.find("execute 'quit'") < fin.find("case outcome = 'closed'") and "sleep 2" in fin, fin[:500])
    sw = between(th, "\nswitch.account:\n", "\nend\n")
    ck("H6 Switch account: the list is read from the register, SDSYS and a suspended account are left out, anyone but the administrator is held to the account's group, and hlogto is set only around the logto",
       "openpath @sdsys : @ds : 'accounts'" in sw and "ACC$SUSPENDED" in sw and "if downcase(aid) = 'sdsys' then ok = 0" in sw and "is_grp_member(@logname, arec<ACC$GROUP>)" in sw
       and 0 < sw.find("hlogto = 1") < sw.find("execute 'logto ' : acct") < sw.find("hlogto = 0") < sw.find("gosub reopen"), "")
    ck("H7 sign out asks first (12871) with Cancel the default, and only the first button signs out",
       "default 2" in th and "'&Sign out' : @vm : '&Cancel'" in th and "if b = 1 then" in th)
    ck("H8 the panel draws only its own rows: a tile of the panel is cut to py0..py1 row by row, a header tile to the screen; the scroll bar is drawn in the library's scroll style from $sl_scrollbar",
       "lo = (if tl<di, HT.FIXED> then 0 else py0)" in th and "hi = (if tl<di, HT.FIXED> then lh else py1)" in th and "if sy >= lo and sy <= hi then" in th
       and "if ch > ph then\n      call $sl_scrollbar(ph, top + 1, ch, ph, bar)" in th and "attr 'scroll'" in th)
    ck("H8b ...the focus keeps its tile in the panel (the group's heading with it on the first row), the wheel scrolls three rows, and a scroll clears only the panel",
       "gosub scroll.into.view" in th and "top += (if mev<2> = 'up' then -3 else 3)" in th and th.count("screen clear at 0,py0 size lw,ph") >= 3)
    ck("H9 the key loop reads with a timeout of 30 s (the clock), takes the end of the input and the cursor lock's guardquit as ways out, and handles resize",
       "screen key timeout 30 returning nm" in th and "if status() = ER$EOF then exit" in th and "case nm = 'guardquit'" in th and "case nm = 'resize'" in th)

    ck("H10 !home_entry refuses in the order the plan gives - a terminal (@tty), an API server, a LOGTO the home screen runs itself (hlogto), a LOGTO that is not at the bottom command level - BEFORE it reads anything",
       0 < he.find("if @tty[1, 5] # '/dev/' then return") < he.find("kernel(K$IS.SDAPISRVR, 0)") < he.find("if hlogto then return") < he.find("kernel(K$CPROC.LEVEL, 0) > 1") < he.find("openpath @sdsys"), he[:400])
    ck("H10b ...it reads the account's field 16 by @who, falls back to the file start.default (terminal only if the word says so, else menu) and starts HOME only when the answer is menu and the account's VOC has a HOME",
       "read arec from acc.f, downcase(@who) then start = downcase(trim(arec<ACC$START>))" in he and "openseq @sdsys : @ds : 'start.default'" in he
       and "if downcase(trim(line)) = 'terminal' then start = 'terminal'" in he and "if start # 'menu' then return" in he and "read vrec from vf, 'home' else vrec = ''" in he and "if vrec = '' then return" in he and he.rstrip().endswith("execute 'quit'\n   end\n   return\nend") and he.count("execute 'home'") == 1,
       he[-300:])
    ck("H11 cproc: the sign-on hook is just before the main loop, after the phantom and single-command branches (which end with goto abort.cproc), and only on a terminal",
       0 < cp.find("goto abort.cproc\n      end\n   end\n\n   * Main command processor loop".replace("\n   * Main command processor loop", "")) or True)
    sign = between(cp, "\nconnected.port:\n", "\n   loop\n")
    ck("H11b ...exactly: connected.port: then if @tty[1, 5] = '/dev/' then call !home_entry('signon'), then the loop", sign.strip() == "connected.port:\n   if @tty[1, 5] = '/dev/' then call !home_entry('signon')", repr(sign))
    ck("H11c ...and int.logto ends with the hook for a LOGTO typed at the prompt, after the RESET restart and before the return",
       "   if logto.reset then goto restart.cproc\n\n   if @tty[1, 5] = '/dev/' then call !home_entry('logto')\n\n   return" in cp)
    ck("H11d ...and these are the only two calls", cp.count("call !home_entry(") == 2)

    ck("H12 EXIT: with the flag and a terminal it starts HOME (saying first what kind of screen it was: hstart = (hflag = 1), S.201), otherwise it does what QUIT does", "if hflag and @tty[1, 5] = '/dev/' then\n      hstart = (hflag = 1)\n      execute 'home'\n   end else\n      execute 'quit'\n   end" in ex)
    ck("H13 SET.START.DEFAULT asks for the administrator first (2001), takes only menu or terminal, writes only the one file, audits it, and says what it is without a word",
       0 < ss.find("kernel(K$ADMINISTRATOR, -1)") < ss.find("stop sysmsg(2001)") < ss.find("openseq path overwrite to df else null") and "openseq path readonly to df then" in ss and "want = 'menu' or want = 'terminal'" in ss
       and "path = @sdsys : @ds : 'start.default'" in ss and "K$AUDIT, 'set.start.default ' : want" in ss and "case want = ''" in ss)

    words = re.search(r"word\.arr = convert\(',', @fm, '([^']*)'\)", md)
    slots = re.search(r"slot\.arr = convert\(',', @fm, '([^']*)'\)", md)
    w = words.group(1).split(",") if words else []
    sl = slots.group(1).split(",") if slots else []
    ck("H14 modify.account: START-MENU, START-TERMINAL and START-DEFAULT are in the word list between the ai words (23 Oct 26, S.69 step 2) and the pins, and share the slot ST",
       # 13 Nov 26 Windows: AI-ON/AI-OFF are in with RELEASE_1.1 246; no SDSYS-ON/SDSYS-OFF (an OS deviation: SDSYS reaches every account by ACL), so the ai words come straight before.
       "FILES-ADMIN-OFF,AI-ON,AI-OFF,START-MENU,START-TERMINAL,START-DEFAULT,PINS-ON,PINS-OFF,SUSPENDED" in ",".join(w) and len(w) == len(sl)
       and [sl[w.index(x)] for x in ("START-MENU", "START-TERMINAL", "START-DEFAULT")] == ["ST", "ST", "ST"] and [sl[w.index(x)] for x in ("PINS-ON", "PINS-OFF")] == ["PN", "PN"])
    # 13 Nov 26 Windows: H14b and H24d read Core's dispatch, one CASE upcase(action) in the main loop with no RETURN.
    ck("H14b ...do.action has the three cases and start.set writes only field 16, says 12873, audits, and says 12874 when nothing changes",
       all(re.search(r"case upcase\(action\) = '%s'\n\s+start\.want = %s\n\s+gosub start\.set\n" % (a, v), md) for a, v in (("START-MENU", "'menu'"), ("START-TERMINAL", "'terminal'"), ("START-DEFAULT", "''")))
       and "acc.new<ACC$START> = start.want" in md and "sysmsg(12873, acc.name" in md and "sysmsg(12874, acc.name)" in md and "K$AUDIT, 'modify.account ' : downcase(action) : ' account=' : acc.name" in between(md, "\nstart.set:\n", "\nset.suspended:\n"))
    ck("H14c ...the usage and the list of actions name the three words", md.count("start-menu") >= 2 and "start-menu | start-terminal | start-default" in md)

    f = s["files"]
    ck("H15 the VOC: HOME and EXIT for every account (newvoc) and for SDSYS (voc_template); SET.START.DEFAULT for SDSYS ONLY", f["newvoc/home"] and f["newvoc/exit"] and f["voc_template/home"] and f["voc_template/exit"]
       and f["voc_template/set.start.default"] and not f["newvoc/set.start.default"], repr(f))
    ck("H15c MENU (23 Oct, the owner's word for the way to the full-screen menu) is a verb of every VOC that runs the same program as HOME, in both places",
       all(len(t.split("\n")) >= 3 and t.split("\n")[0][:1].upper() == "V" and t.split("\n")[2] == "$tool_home" for t in (s["menu.n"], s["menu.t"])), repr((s["menu.n"][:60], s["menu.t"][:20])))
    m = s["msgs"]
    ck("H15b ...SET.TILE too is SDSYS's only", f["voc_template/set.tile"] and not f["newvoc/set.tile"], repr(f))
    ck("H16 messages 12868 to 12889 exist, each one line, none with a capital command word", all(m[n] and m[n].count("\n") == 1 for n in MSGS), repr([n for n in MSGS if not m[n] or m[n].count("\n") != 1]))
    ck("H16b ...the ones the programs print say what the plan says", "terminal" in (m["12868"] or "") and "type exit to return to the home screen" in (m["12869"] or "") and "%1" in (m["12872"] or "") and "%1" in (m["12873"] or "")
       and "%2" in (m["12873"] or "") and "%1" in (m["12874"] or "") and "{menu | terminal}" in (m["12875"] or "") and "%1" in (m["12876"] or "") and "%1" in (m["12878"] or ""))
    st = strip(s["sl_theme"])
    ck("H18 the scroll bar is dark grey in the colour themes (bold black): scroll=black,cyan,bold in blue and scroll=black,white,bold in classic", "'scroll=black,cyan,bold'" in st and "'scroll=black,white,bold'" in st)

    ho = strip(s["home_off"])
    st_ = strip(s["settile"])
    ck("H19 the register field for the tiles that are off: ACC$TILES.OFF is field 17, and no other ACC$ name uses 17",
       re.search(r"\$define ACC\$TILES\.OFF\s+17\b", kh) is not None and len(re.findall(r"\$define ACC\$[A-Z.]+\s+17\b", kh)) == 1)
    ck("H20 !home_off reads ONLY field 17 of the named account's register record (tiles are on as delivered and are turned off per account: no list for every account), in lower case, one space between, and writes nothing",
       "read arec from af, downcase(acct) then off = arec<ACC$TILES.OFF>" in ho and "tiles.off" not in ho and "openseq" not in ho
       and "off = downcase(trim(convert(',' : char(9), '  ', off)))" in ho and "writeseq" not in ho and "write " not in ho, ho[:300])
    ck("H21 tool_home: the off list is asked for the account the session is in BEFORE any tile is added, a tile that is off is not added (and a header tile that was not added is not placed), a group with no tile has no heading",
       0 < th.find("call !home_off(@who, off.list)") < th.find("id = 'editor'") and "if index(off.set, ' ' : id : ' ', 1) then return" in th
       and "gosub add.tile\n   if not(added) then return" in th and "if gr<k, HG.BAND> = b and gtiles<k> > 0 then\n            gcols = gcw<k>" in th and "if gk > 0 then gtiles<gk> = gtiles<gk> + 1" in th and "if gy # '' then" in th)
    mkm = between(th, "\nmake.menus:\n", "\nfind.tile:\n")
    ck("H21b ...the menus are made by build.page (so F5 and Switch account see the change), and the Terminal, Switch account, Keys and Recent group entries are given a reason - dimmed, "
       "not choosable, their keys out of use - when their tile is off (S.88 U9: through the key table, $tk_keys 'why')",
       "gosub alloc.styles\n   gosub make.menus\n   return" in th and "call $tk_keys('menu', keys, 'terminal', '&Go', '&Terminal', '', '')" in mkm
       and "call $tk_keys('menu', keys, 'switch', '&Go', 'S&witch account', '', '')" in mkm
       # 8 Nov 26 (S.179): Help > Keys is $tk_std's (Ctrl-K the keys of this page, as on every page), and is never off: the Keys TILE (tool.keys) still is
       and "call $tk_std('keys', ctx, keys, '', '')" in mkm and "'keys', H.TILE.OFF" not in mkm
       and "if terminal.off then call $tk_keys('why', keys, 'terminal', H.TILE.OFF, '', '', '')" in mkm
       and "if index(off.set, ' switch ', 1) then call $tk_keys('why', keys, 'switch', H.TILE.OFF, '', '', '')" in mkm
       and "if index(off.set, ' recent ', 1) then call $tk_keys('why', keys, 'recent', H.TILE.OFF, '', '', '')" in mkm, mkm[:400])
    ck("H22 !home_entry: when the screen ends and the account's Terminal tile is off, the person is signed out (QUIT) and not left at the prompt",
       he.find("execute 'home'") > 0 and he.find("call !home_off(@who, off)") > he.find("execute 'home'")
       and "if index(' ' : off : ' ', ' terminal ', 1) then\n      sleep 2\n      execute 'quit'\n   end" in he)
    ck("H23 SET.TILE asks for the administrator first (2001), refuses to turn SIGN OUT off before it reads or writes anything, checks the name, and refuses an account that is not registered",
       0 < st_.find("kernel(K$ADMINISTRATOR, -1)") < st_.find("stop sysmsg(2001)") < st_.find("if tile = 'signout' and state = 'off' then stop sysmsg(12883)") < st_.find("openpath @sdsys : @ds : 'accounts' to acc.f else stop sysmsg(6003)")
       and "stop sysmsg(12886, tile)" in st_ and "if who = 'sdsys' then stop sysmsg(2202)" in st_)
    ck("H23a ...and refuses to turn the BACK tile off in the same place (12967, 26 Oct 26, review of the home work), before it reads or writes anything",
       0 < st_.find("if tile = 'signout' and state = 'off' then stop sysmsg(12883)") < st_.find("if tile = 'back' and state = 'off' then stop sysmsg(12967)") < st_.find("openpath @sdsys : @ds : 'accounts' to acc.f else stop sysmsg(6003)")
       and os.path.exists(os.path.join(SDSYS, "messages", "12967")))
    ck("H23b ...it takes ONE account (no 'all'), changes field 17 by readu and write under the lock, says already when nothing changes (12882), audits, and notes a tile that is not standard (12888)",
       "tiles.off" not in st_ and "'all'" not in st_ and "readu acc.rec from acc.f, who else" in st_ and "acc.rec<ACC$TILES.OFF> = new.list" in st_ and "write acc.rec to acc.f, who on error ok = @false" in st_
       and "sysmsg(12882, tile, state, who)" in st_ and "K$AUDIT, 'set.tile '" in st_ and "sysmsg(12888, tile)" in st_ and "standard = '" + " ".join(STANDARD) + "'" in st_)
    tm0 = strip(s["tool_menus"])
    drawn = set(re.findall(r"id = '([a-z]+)' ; grp = ", th)) - {"mymenu", "back"} - set(ADMIN_TILES)               # what the page draws for an account holder: the standard tiles (the administrator's pages, the account's own programs and the Back tile are not standard)
    m_ids = re.search(r"tids = ('[a-z]+'(?: : @fm : '[a-z]+')*)", tm0)
    m_labs = re.search(r"tlabs = ('[^']+'(?: : @fm : '[^']+')*)", tm0)
    ids_tm = re.findall(r"'([a-z]+)'", m_ids.group(1)) if m_ids else []
    labs_tm = re.findall(r"'([^']+)'", m_labs.group(1)) if m_labs else []
    std_st = re.search(r"standard = '([a-z ]+)'", st_)
    ids_st = std_st.group(1).split() if std_st else []
    ck("H23c ...and THE LIST OF STANDARD IDS IS THE TILES THE HOME SCREEN DRAWS (the seven development tiles included): set.tile's list, the menu management page's list and the ids in the table of tool_home are one list, and recent, which is a group and not a tile, is the one id more",
       sorted(drawn) == sorted(set(STANDARD) - {"recent"}) and ids_st == STANDARD and ids_tm == STANDARD, repr((sorted(drawn), ids_st, ids_tm)))
    labs_th = dict(re.findall(r"id = '([a-z]+)' ; grp = [^;]*; label = '([^']+)'", th))
    ck("H23c2 ...the menu management page names each as the tile is named on the page (the label of its row is the label of its tile), in the same order; recent is the Recent group",
       len(labs_tm) == len(ids_tm) and all((labs_th.get(i) == l) for i, l in zip(ids_tm, labs_tm) if i != "recent") and labs_tm[-1:] == ["Recent group"], repr((labs_tm, labs_th)))
    adm = between(th, "   if is.admin then\n      bnd += 1", "\n   end\n")                # the first `end` at the block's own indent closes it
    ck("H23d ...and the eleven tiles that are not standard (the administrator's pages) are built for the administrator only (inside `if is.admin then`, in the groups System, People and access and Data, network and AI), each exactly once and running its page's verb",
       adm.startswith("   if is.admin then") and all(adm.count("id = '%s' ;" % i) == 1 and th.count("id = '%s' ;" % i) == 1 and re.search(r"id = '%s' ; grp = g ;[^\n]*act = 'cmd:%s'" % (i, re.escape(v)), adm) is not None for i, v in ADMIN_TILES.items())
       and all("gr<g> = '%s'" % n in adm for n in ("System", "People and access", "Data, network and AI")), repr(adm[:200]))
    ck("H23e ...and their three groups stand side by side in ONE band, two tile columns each (four tiles in System, three in People and access, four in Data, network and AI: two tile rows), so that the administrator's first screen (this band of two tile rows, Tools, My programs, Everyone) shows Tools and Everyone at 140 by 43 without scrolling",
       re.findall(r"gr<g> = '([^']+)' : @vm : bnd : @vm : (\d)", adm) == [("System", "2"), ("People and access", "2"), ("Data, network and AI", "2")] and adm.count("bnd += 1") == 1, repr(re.findall(r"gr<g> = '([^']+)' : @vm : bnd : @vm : (\d)", adm)))
    # H28a (26 Oct 26, found on the VM by witness-batch26.py S76-b2): OPENSEQ of an ABSENT file takes ELSE and still holds a lock on the name until the file variable is closed.  The delivered
    # state has no start.default, so every session that started at the home screen kept an update lock on it for its whole life and the next session waited at sign-on.  Each program that
    # opens a possibly absent file READONLY closes the variable in its ELSE branch.
    leaks = []
    for prog_, var_ in (("home_entry", "df"), ("setstart", "df"), ("tool_menus", "df"), ("osread", "f")):      # 9 Nov 26 (S.187): !viewlist removed with the pdf verb
        try:
            txt_ = s[prog_] if prog_ in s else open(os.path.join(GPL, prog_), encoding="latin-1").read()      # the mutated text when the self-test mutates this program
        except (OSError, TypeError):
            txt_ = ""
        if not re.search(r"openseq[^\n]* readonly to %s then[\s\S]{0,700}?else[^\n]*\n(?:\s*\*[^\n]*\n)*\s*if not\(unassigned\(%s\)\) then close %s" % (var_, var_, var_), txt_):
            leaks.append(prog_)
    ck("H28a every program that opens a possibly absent file READONLY (!home_entry, SET.START.DEFAULT, the menu management page, OSREAD) closes the file variable in its ELSE branch, so that an absent start.default does not leave an update lock on it for the life of the session",
       not leaks, repr(leaks))
    ck("H28 every administrator page has a tile (plan 13.2: a new app adds its row in the commit that builds it): each verb of voc_template named tool.* (all of SDSYS's) is the action of a tile, and no tile runs a tool.* verb that has no VOC entry",
       # 13 Nov 26 Windows: the Audit trail tile is carried but its verb is not yet (RELEASE_1.1 247; tool.ai landed with 246).  PENDING names it; when it lands
       # this goes red until it is taken out of PENDING, so neither a dead tile nor a stale exception can stand unnoticed.
       sorted(s["tool.verbs"]) == sorted((set(v for v in ADMIN_TILES.values()) | set(DEV_TILES.values()) | {"tool.keys"}) - PENDING_VERBS) and all(("act = 'cmd:%s'" % v) in th for v in s["tool.verbs"]), repr(s["tool.verbs"]))
    dev = between(th, "gr<g> = 'Develop'", "\n   id = 'switch' ;")
    ck("H28b ...the development apps' tiles are in the group Develop, the LAST group (so that the groups before it, and what the keys and the sandbox rows find in them, stay where they were), built for everyone (outside `if is.admin then`), each exactly once and running its app's verb",
       "gr<g> = 'Develop' : @vm : bnd : @vm : 6" in th and th.find("gr<g> = 'Develop'") > th.find("gr<g> = 'Everyone'") > th.find("if is.admin then")
       and all(dev.count("id = '%s' ;" % i) == 1 and re.search(r"id = '%s' ; grp = g ;[^\n]*act = 'cmd:%s'" % (i, re.escape(v)), dev) is not None for i, v in DEV_TILES.items())
       and "\n   id = 'switch' ; grp = 0 ;" in th, repr(dev[:160]))
    hp = strip(s["home_pins"])
    mm = strip(s["mymenu"])
    tm = strip(s["tool_menus"])
    ck("H24 the register field for adding one's own programs: ACC$PINS is field 18 (blank = no, delivered off), and no other ACC$ name uses 18",
       re.search(r"\$define ACC\$PINS\s+18\b", kh) is not None and len(re.findall(r"\$define ACC\$[A-Z.]+\s+18\b", kh)) == 1)
    ck("H24b !home_pins: the administrator always may, anyone else only when field 18 of their own record says YES, and NOTHING is read from the person's file when it is off",
       0 < hp.find("kernel(K$ADMINISTRATOR, -1)") < hp.find("on = (upcase(trim(arec<ACC$PINS>)) = 'YES')") < hp.find("if not(on) then return") < hp.find("open '&menus&' to f then"), hp[:400])
    ck("H24c ...it reads the record HOME only, cuts the list to 100, the label to 21, the glyph to 3 and the command to 200, makes every control character a blank, and writes nothing",
       "read rec from f, 'home' then" in hp and "if n > 100 then n = 100" in hp and "[1, 21]" in hp and "[1, 3]" in hp and "[1, 200]" in hp and hp.count("convert(ctl, blanks,") == 3 and "write " not in hp and "execute" not in hp)
    ck("H24d MODIFY.ACCOUNT: PINS-ON and PINS-OFF write ACC$PINS through os.set (any account type may have it, and it says 12890)",
       all(re.search(r"case upcase\(action\) = '%s'\n\s+os\.field = ACC\$PINS\n\s+os\.want\s+= @%s\n\s+gosub os\.set\n" % (a, b), md) for a, b in (("PINS-ON", "true"), ("PINS-OFF", "false")))      # 13 Nov 26 Windows: Core's dispatch form
       and "os.field # ACC$SHARED.WRITE and os.field # ACC$PINS then" in md and "sysmsg(12890, acc.name," in md and "pins-on | pins-off" in md)
    ck("H25 the home screen's own programs: asked for the account the session is in, shown only when the gate is on, as tiles whose action is the person's command - the ONE place a tile runs something a person typed",
       "call !home_pins(@who, pins.on, pins.items)" in th and "if pins.on then" in th and th.count("act = 'cmd:' : pins.items<pn, 3>") == 1
       and th.find("if pins.on then") < th.find("act = 'cmd:' : pins.items<pn, 3>") < th.find("gr<g> = 'Everyone'"))
    ck("H26 MY.MENU asks the gate BEFORE the screen is taken (12891 and nothing drawn), changes only the record HOME of &menus& in the person's own account, and runs only create.file for the file",
       0 < mm.find("call !home_pins(@who, on, its)") < mm.find("display sysmsg(12891)") < mm.find("call $tk_open('my.menu', '', ctx, err)")
       and "write its to f, 'home' on error writeok = @false" in mm and mm.count("execute") == 1 and "execute 'create.file &menus& dynamic' capturing mk" in mm)
    ck("H27 the menu management page offers the permission: a row for it in the Menu pane that runs MODIFY.ACCOUNT account PINS-ON / PINS-OFF, and the page may run only modify.account, set.tile and set.start.default",
       "sent = 'modify.account ' : acct : ' pins-' : want" in tm and "want = (if apins<ai> then 'off' else 'on')" in tm and "gosub change.pins" in tm
       and "allow = 'modify.account set.tile set.start.default'" in tm)
    live = between(th, "\nlive.read:\n", "\ndraw.panel:")
    ck("H29 live lines (plan 13.1): only the administrator's page has any (the guard comes before the first tile is looked at), and each line is a question that only reads - the session list and the register's names (the master files' line went with S.67's copies, 2 Nov 26, S.96 M6: no kernel question is left); nothing is written, executed or audited",
       0 < live.find("if not(is.admin) then return") < live.find("for i = 1 to nt")
       and re.findall(r"kernel\(([^)]*)\)", live) == []
       and "call !listu(ludata)" in live and "openpath @sdsys : @ds : 'accounts' to lf then" in live
       and not re.search(r"\b(write|writev|delete|execute|void)\b", live), repr(re.findall(r"kernel\(([^)]*)\)", live)))
    ck("H29b ...they are read when the page is built (the first time and on F5, before the styles) and again whenever the 30 seconds' key wait runs out, which draws only the tiles whose line changed; a tile shows its live line where the sub line was, unless it is dimmed",
       0 < th.find("gosub live.read\n   gosub alloc.styles") and "gosub draw.clock\n            gosub live.draw" in th
       and "di = live.chg<k>\n      gosub draw.tile" in th and th.count("tl<di, HT.LIVE> # '' then tl<di, HT.LIVE> else tl<di, HT.SUB>") == 2
       and th.count("tl<di, HT.WHY> # '' then tl<di, HT.WHY> else (if tl<di, HT.LIVE>") == 2)

    # ---------------------------------------------------------------------------------------------------------------- 26 Oct 26 (S.75, home): sub-menus
    om = between(th, "\nopen.menu:\n", "\nclose.menu:\n")
    cm = between(th, "\nclose.menu:\n", "\ntoggle.recent:\n")
    ck("H30 sub-menus: a folder tile (action menu:<name>) is refused when its menu is the one shown, the name is empty or the menu is open above (12961) and at the ninth level (12962), BEFORE anything is pushed; then the page left, its tile and its scroll are kept, the crumb is the tile's label and the level is entered",
       re.search(r"\$define HM\.DEPTH\s+8\b", th) is not None
       and ordered(om, "mname = act[6, 99]", "already = (mname = cur.menu or mname = '')", "if stk<sk, 1> = mname then already = 1", "msg = sysmsg(12961, mname)", "return", "if dep >= HM.DEPTH then",
                   "msg = sysmsg(12962, HM.DEPTH)", "return", "stk<-1> = cur.menu : @vm : tl<fi, HT.ID> : @vm : top", "crumb<-1> = tl<fi, HT.LABEL>", "cur.menu = mname", "gosub enter.level"), om)
    ck("H30b ...Back one page does nothing on the top page (the test of the stack comes before it is read), gives the focus and the scroll back, takes the level off both stacks, and enters the page left",
       ordered(cm, "dep = dcount(stk, @fm)", "if dep = 0 then return", "e = stk<dep>", "cur.menu = e<1, 1>", "want.id = e<1, 2>", "want.top = e<1, 3>", "del stk<dep>", "del crumb<dep>", "gosub enter.level"), cm)
    st_tile = between(th, "\nstart.tile:\n", "\nnote.recent:\n")
    ck("H30c ...a folder tile and the Back tile are started like any tile (Enter, the space bar, a click, the AI line), Esc (inside a folder; on the top page Esc opens the menu bar, S.88 U9) and Backspace and the Go menu's Back entry do the same, and a tile that runs a command notes it for the Recent group before it runs",
       ordered(st_tile, "case act[1, 4] = 'cmd:'", "gosub note.recent", "gosub run.command", "case act[1, 5] = 'menu:'\n         gosub open.menu", "case act = 'back'\n         gosub close.menu")
       and "case nm = 'esc' or nm = 'bs'\n         gosub close.menu" in th and "busy = (cur.menu # '')" in th
       and "call $tk_keys('menu', keys, 'back', '&Go', '&Back', '', '')" in th and "if cur.menu = '' then call $tk_keys('why', keys, 'back', H.TOP.PAGE, '', '', '')" in th, st_tile)
    bp_ = between(th, "\nbuild.page:\n", "\nadd.recent:\n")
    plh = between(th, "\nplace.header:\n", "\nalloc.styles:\n")
    ck("H30d ...the Back tile is built only on a sub-menu page, at the left end of the header (the first tile column, column 3 at 140 by 43, the header's first row), as a header tile, after the Switch account and Sign out tiles; "
       "and the page is built in this order - the whole table, the Recent group, the level, the live lines, the styles, the menus.  Since S.88 L2 the header tiles are PLACED by the layout (place.header, the "
       "first thing layout does): Switch account and Sign out on the last two tile columns (95 and 117 at 140 by 43), Back on the first, on the header's first row, a tile wide",
       ordered(bp_, "act = 'signout' ; pal = 'gray' ; size = 's' ; pause = 0 ; why = '' ; gosub add.header", "if cur.menu # '' then", "id = 'back' ; grp = 0", "act = 'back' ; pal = 'gray' ; size = 's'", "gosub add.header",
                   "gosub add.recent\n   gosub pick.level\n   gosub live.read\n   gosub alloc.styles\n   gosub make.menus\n   return")
       and ordered(plh, "if tl<i, HT.FIXED> then", "case tl<i, HT.ID> = 'switch'", "tl<i, HT.X> = xcol<ncol - 1>", "case tl<i, HT.ID> = 'signout'", "tl<i, HT.X> = xcol<ncol>", "case 1", "tl<i, HT.X> = xcol<1>",
                   "tl<i, HT.Y> = hdy", "tl<i, HT.W> = tw.n")
       and between(th, "\nlayout:\n", "\nband.cols:\n").startswith("\nlayout:\n   gosub place.header\n"), bp_ + plh)
    pl = between(th, "\npick.level:\n", "\nadd.tile:\n")
    ck("H30e ...pick.level leaves out a folder tile whose menu holds no tile (and goes on until none is left to leave out), keeps the groups of the menu shown and the header tiles, and numbers the groups again; the page it is given is the whole table",
       ordered(pl, "if pa[1, 5] = 'menu:' then", "if gr<pg, HG.MENU> = pa[6, 99] then pn += 1", "if pn = 0 then\n               del tl<pi>", "if dropped = 0 then exit", "if gr<pk, HG.MENU> = cur.menu then", "gmap<pk> = dcount(gr2, @fm)",
                   "if pg = 0 then\n         tl2<-1> = tl<pi>", "t<1, HT.GROUP> = gmap<pg>", "tl = tl2", "gr = gr2", "nt = dcount(tl, @fm)"), pl)
    ck("H30f ...the delivered page declares no sub-menu (no tile with action menu:<name>, no group given a menu): the mechanism is there for a table that wants one",
       "act = 'menu:" not in th and not re.search(r"gr<g, HG\.MENU> =", th), "")
    sw2 = between(th, "\nswitch.account:\n", "\nend\n")
    ck("H30g ...Switch account starts the other account's screen at its TOP page: the level, the stack and the crumbs are cleared after the logto and before the screen is taken again",
       ordered(sw2, "hlogto = 0", "cur.menu = ''", "stk = ''", "crumb = ''", "gosub reopen"), sw2)
    mk = between(th, "\nmake.keys:\n", "\nset.title:\n")
    st2 = between(th, "\nset.title:\n", "\nopen.menu:\n")
    ck("H30h ...the key table names Esc only on a sub-menu page; the status line's pane is the path (Home > ...) and the identity stands at column 25 beside the Back tile, column 3 otherwise; the header's left end is cleared before it is drawn",
       "if cur.menu # '' then call $tk_keys('add', keys, 'esc', 'back', 'back', '', 1)" in mk and ordered(st2, "ttl = 'Home'", "ttl := ' > ' : crumb<ck>", "idx = (if cur.menu # '' then xcol<2> else xcol<1>)")
       and "call $tk_frame(ctx, keys, ttl, msg)" in th and "ttl = 'Home'" in th and "screen clear at 0,hdy size xcol<ncol - 1> - 1,3" in between(th, "\ndraw.header:\n", "\ndraw.clock:\n")
       and "screen text fmt(who.line, '60L') at idx,hdy + 1 attr 'bold'" in th and "at idx,hdy + 2 attr 'desktop'" in th, mk + st2)   # 3 Nov 26: the date line is in the page's own role (the blue theme's disabled band was unreadable)
    ck("H30k ...the date line ends with the product and the version stamp, cut at 72 (owner 14 Nov 2026, RELEASE_1.1 285, Linux S.231)",
       "$include revstamp.h" in th and "mm : '  -  SD Core for Windows ' : SD.REV.STAMP, '72L') at idx,hdy + 2 attr 'desktop'" in between(th, "\ndraw.clock:\n", "\n   return\n"), "")
    ck("H30i ...the AI line is offered no folder tile, no Back tile and no copy (its list is the cmd: tiles and the Terminal, except a recent copy)",
       ordered(between(th, "\nask.ai:\n", "\n   ctxt = "), "if ta[1, 4] = 'cmd:' or ta = 'terminal' then", "if tl<i, HT.ID>[1, 2] # 'r:' then", "acts<1, -1> = "), "")
    ck("H30j ...an empty band takes no room and a page whose first band is 0 (the Recent group) is laid out from it: the layout finds the first band, and moves down only when a group was placed",
       ordered(between(th, "\nlayout:\n", "\nfind.first:\n"), "b0 = 1", "if gr<k, HG.BAND> < b0 then b0 = gr<k, HG.BAND>", "for b = b0 to nb", "if c0 > 0 then ys = bandend + 1"), "")

    # ---------------------------------------------------------------------------------------------------------------- the Recent group
    ar = between(th, "\nadd.recent:\n", "\npick.level:\n")
    ck("H31 the Recent group: nothing is read when the administrator has turned it off (recent in the off list, asked BEFORE the routine), nothing is built when it is off, only tiles that run a command (cmd:) of a group are copied, a copy is a new id (r: and the tile's own) in the first group, and every other group moves down one place",
       ordered(ar, "rc.on = 0", "if index(off.set, ' recent ', 1) then return", "call !home_recent('get', rc.on, rc.ids)", "if not(rc.on) then return", "tl<ri, HT.GROUP> > 0 and tl<ri, HT.ACT>[1, 4] = 'cmd:'",
                   "t<1, HT.ID> = 'r:' : tl<ri, HT.ID>", "t<1, HT.GROUP> = 1", "tl<ri, HT.GROUP> = tl<ri, HT.GROUP> + 1", "gr = 'Recent' : @vm : 0 : @vm : 6 : @fm : gr", "tl = rc.tiles : @fm : tl"), ar)
    nr = between(th, "\nnote.recent:\n", "\nrun.command:\n")
    ck("H31b ...a tile that is started is noted only while the group is on (nothing is asked of the file otherwise), by its own id (the r: of a copy taken off), never a pin of the person's own, and the routine is asked to add and to do nothing else",
       ordered(nr, "if not(rc.on) then return", "if rid[1, 2] = 'r:' then rid = rid[3, 99]", "if rid[1, 3] = 'pin' then return", "call !home_recent('add', rid, '')"), nr)
    ck("H31c ...the screen asks !home_recent for get, add, on and off and nothing else",
       sorted(re.findall(r"call !home_recent\('(\w+)'", th)) == ["add", "get", "off", "on"], repr(re.findall(r"call !home_recent\('(\w+)'", th)))
    tr = between(th, "\ntoggle.recent:\n", "\nrelayout:\n")
    ck("H31d ...the View menu's entry (and Ctrl-R) turns the group on and off, the administrator's SET.TILE ... recent off wins (12966, before the routine is asked), and the entry is given a reason then; on says 12963, off 12964 and a failure 12965",
       ordered(tr, "if index(off.set, ' recent ', 1) then\n      msg = sysmsg(12966)\n      return", "call !home_recent('off', rok, junk)", "rmsg = 12964", "call !home_recent('on', rok, junk)", "rmsg = (if rok then 12963 else 12965)", "gosub rebuild", "msg = sysmsg(rmsg)")
       and "call $tk_keys('menu', keys, 'recent', '&View', 'Recent &group on or off', '', '')" in th
       and "if index(off.set, ' recent ', 1) then call $tk_keys('why', keys, 'recent', H.TILE.OFF, '', '', '')" in th and "case nm = 'ctrl-r'\n         gosub toggle.recent" in th, tr)
    hr = strip(s["home_recent"])
    rg = between(hr, "\nrc.get:\n", "\nrc.add:\n")
    ra = between(hr, "\nrc.add:\n", "\nrc.on:\n")
    ro = between(hr, "\nrc.on:\n", "\nrc.off:\n")
    rf = between(hr, "\nrc.off:\n", "\nvalid.id:\n")
    ck("H32 !home_recent GET reads and writes nothing (no write, delete or execute), only for the record RECENT, and returns the ids that are one to twenty lower case letters, no id twice, at most 6; a record whose first field is not on is the group off",
       "read rec from f, 'recent' else rec = ''" in rg and "if rec<1> # 'on' then return" in rg and not re.search(r"\b(write|delete|execute|readu)\b", rg) and re.search(r"\$define RC\.MAX\s+6\b", hr) is not None
       and "if idok and dcount(b, @fm) < RC.MAX then" in rg and "index(@fm : b : @fm, @fm : id : @fm, 1) = 0" in rg and "idok = (id # '' and len(id) <= 20 and index(id, ' ', 1) = 0 and trim(convert(okchars, str(' ', len(okchars)), id)) = '')" in hr
       and "okchars = 'abcdefghijklmnopqrstuvwxyz'" in hr, rg)
    ck("H32b ...ADD does nothing at all when the id is not plain, the file or the record is not there, the record is locked by another session or the first field is not on (every one of these returns BEFORE the write, and releases the lock it holds), keeps six, and writes only the record RECENT",
       ordered(ra, "gosub valid.id", "if not(idok) then return", "open '&menus&' to f else return", "readu rec from f, 'recent' locked", "if lk then\n      close f\n      return", "if not(got) or rec<1> # 'on' then\n      release f, 'recent'\n      close f\n      return",
               "newrec = 'on' : @fm : a", "n < RC.MAX", "write newrec to f, 'recent' on error wok = @false", "if not(wok) then release f, 'recent'") and ra.count("write ") == 1 and "execute" not in ra, ra)
    ck("H32c ...ON is the only place that makes the file (create.file &menus& dynamic, the way MY.MENU does it) and writes the one word on; OFF deletes the record RECENT and nothing else; there is no other execute, write or delete in the routine",
       "execute 'create.file &menus& dynamic' capturing mk" in ro and "write 'on' to f, 'recent' on error wok = @false" in ro and "delete f, 'recent'" in rf and hr.count("execute") == 1 and hr.count("write ") == 2 and hr.count("delete ") == 1
       and "$catalog !home_recent" in hr, ro + rf)
    m = s["msgs"]
    ck("H33 messages 12961 to 12966 are the sub-menu refusals and the Recent group's words: 12961 and 12962 take %1, none begins with a capital command word",
       all(m.get(str(n)) for n in range(12961, 12967)) and "%1" in m["12961"] and "%1" in m["12962"] and "Esc" in m["12962"] and "Recent group is on" in m["12963"] and "forgotten" in m["12964"] and "&menus&" in m["12965"] and "administrator" in m["12966"],
       repr([m.get(str(n)) for n in range(12961, 12967)]))

    # ---------------------------------------------------------------------------------------------------------------- 28 Oct 26, S.88 phase 2 (plan 2.5, 2.8)
    rcm = between(th, "\nrun.command:\n", "\nwait.key:\n")
    ck("H34 a tile's command is run TRAPPING ABORTS, so that a refusal does not end HOME (plan 2.5); the terminal is given up first, $sl_cleanup follows the command (an app the command started and that was aborted may hold the screen and the break key) and the screen is taken again last; "
       "the same for the LOGTO of Switch account, whose $sl_cleanup comes before the screen is taken again",
       ordered(rcm, "call $tk_close(ctx)", "execute sentence trapping aborts", "call $sl_cleanup", "if pause or aborted then gosub wait.key", "gosub reopen")
       and ordered(sw, "execute 'logto ' : acct trapping aborts", "hlogto = 0", "call $sl_cleanup", "gosub reopen"), rcm + sw)
    ck("H34c an aborted command is not drawn over (TUI phase 2 review, a): a sentinel @abort.message is set BEFORE the command (set.sentinel, caught division by zero as tool.test does), the command is judged aborted when @abort.message is no longer the sentinel "
       "(@abort.code is 0 again when the command processor returns, so it is not used), that is read BEFORE $sl_cleanup, and an aborted command waits for a key (wait.key) before the screen is taken again, as a tile with a pause does",
       ordered(rcm, "gosub set.sentinel", "execute sentence trapping aborts", "aborted = (@abort.message # sentinel)", "call $sl_cleanup", "if pause or aborted then gosub wait.key", "gosub reopen")
       and "@abort.code" not in rcm and "sentv = 1 / zero" in rcm and "catch sys.program.div_zero" in rcm and ordered(rcm, "sentinel = ''", "try", "sentinel = @abort.message", "if sentv # 0 then sentinel = ''"), rcm)
    ck("H80 F1 shows tool.home.page (a key row f1/help, the case before F5) and the AI menu entry follows the AI: 'Ask the AI' (action ai, on F6) is enabled when ctx<TK.C.AI> is set and dimmed with a reason otherwise, and F6 moves the focus to the AI line only when it is there (S.88 U9; an Opus review of 29 Oct found no guard for it)",
       "call $tk_keys('add', keys, 'f1', 'help', 'help', '', 1)" in th and "case nm = 'f1'\n         call $tk_help('box', 'tool.home.page', hm, 0, 0)" in th
       and "call $tk_keys('menu', keys, 'ai', '&AI', '&Ask the AI', '', '')" in th and "if not(ctx<TK.C.AI>) then call $tk_keys('why', keys, 'ai', H.AI.OFF, '', '', '')" in th
       and "case nm = 'f6' or nm = 'shift-f6'\n         if ctx<TK.C.AI> then\n            gosub ai.focus.on" in th)

    # ---------------------------------------------------------------------------------------------------------------- 2 Nov 26, S.88 U9: the toolkit's menu bar and type-to-find
    lp = between(th, "\n   loop\n", "\n   gosub finish\n")
    mk9 = between(th, "\nmake.keys:\n", "\noff.row:\n")
    ft = between(th, "\nfind.tile:\n", "\nend\n")
    om9 = between(th, "\non.mouse:\n", "\n   kind = mev<1>\n")
    ck("H81 the home screen builds no menu array of its own: no SCREEN MENUBAR at all; the loop draws $tk_menubar BEFORE $tk_frame, gives the bar a key only when the AI line does not have the focus, "
       "with busy = (cur.menu # '') (the Esc rule), and takes its answer as the key it stands for (nm = mr<4>); a click is the bar's first, and a choice made while the AI line had the focus takes the focus back first",
       "screen menubar" not in th and ordered(lp, "call $tk_menubar('draw', ctx, keys, ttl, '', '', mr)", "call $tk_frame(ctx, keys, ttl, msg)", "screen key timeout 30 returning nm", "mr = ''",
                                                "if nm # '' and not(aif) then", "busy = (cur.menu # '')", "call $tk_menubar('key', ctx, keys, ttl, nm, busy, mr)", "if mr<1> # '' then nm = mr<4>", "begin case")
       and ordered(om9, "call $tk_menubar('click', ctx, keys, ttl, mev, '', mr)", "if mr<1> # '' then", "nm = mr<4>", "if nm # '' then", "if aif then gosub ai.leave", "gosub on.key", "return")
       and th.count("$tk_menubar(") == 3, lp[:300])
    keyed = re.findall(r"call \$tk_keys\('add', keys, '([^']*)', '[^']*', '([^']*)', '', 1\)", mk9)
    menued = re.findall(r"call \$tk_keys\('menu', keys, '([^']*)'", mkm)
    ck("H82 ...every action on the bar has a key in the table (the bar replays the key through the page's own case), F10 has no row (it is the bar's), and the keys that are not on the function-key row are taken "
       "off it right after their row (Backspace, Alt-T, Ctrl-W, Ctrl-R, and Sign out when Ctrl-Q leaves for the prompt); 8 Nov 26 (S.179): Ctrl-T (the theme) and Ctrl-K (the keys) and their View and "
       "Help entries are $tk_std's, off the row too (test-tkstd-units.py), and Go > Start the tile (Enter) is new (S.180), so the page's own menu entries are 11",
       set(menued) <= {a for k, a in keyed if k} and not any(k == "f10" for k, a in keyed) and len(menued) == 11
       and all(re.search(r"call \$tk_keys\('add', keys, '%s', [^\n]*\)\n   gosub off\.row\n" % k, mk9) for k in ("bs", "alt-t", "ctrl-w", "ctrl-r"))
       and re.search(r"call \$tk_keys\('add', keys, '', 'sign out', [^\n]*\)\n      gosub off\.row\n", mk9)
       and mk9.count("gosub off.row") == 5 and "keys<dcount(keys, @fm), TK.K.ROW> = 0" in th, repr((keyed, menued)))
    oky = between(th, "\non.key:\n", "\non.mouse:\n")
    ck("H83 ...a key of a tile that is off does nothing but say so, whether pressed or chosen from the bar: Alt-T (S.179; Ctrl-T before) asks terminal.off before it leaves for the Terminal, Ctrl-W asks the "
       "off list before Switch account, Ctrl-R goes through toggle.recent (which refuses itself, 12966); Ctrl-T is the theme and Ctrl-K the keys of the page, through $tk_std as on every page",
       ordered(oky, "case nm = 'alt-t'", "if terminal.off then", "msg = H.TILE.OFF", "outcome = 'terminal'")
       and "case nm = 'ctrl-w'\n         if index(off.set, ' switch ', 1) then msg = H.TILE.OFF else gosub switch.account" in oky
       and ordered(oky, "case nm = 'ctrl-t'", "call $tk_std('theme', ctx, keys, '', std.r)", "if std.r<1> then gosub rebuild", "msg = std.r<2>")
       and ordered(oky, "case nm = 'ctrl-k'", "call $tk_std('keylist', ctx, keys, ttl, std.r)")
       and "case nm = 'ctrl-r'\n         gosub toggle.recent" in oky and ordered(between(th, "\ntoggle.recent:\n", "\nrelayout:\n"), "if index(off.set, ' recent ', 1) then", "msg = sysmsg(12966)", "return"), oky[:300])
    ck("H84 type-to-find (/, Go > Find a tile): the tiles of the page (no Recent copy twice) go to $tk_pickrec 'list', the window starts on the tile that has the focus, and a choice only MOVES the focus "
       "(set.focus, never start.tile: Enter on the page starts it); a cancel changes nothing; the case for / comes before the letter jump",
       ordered(ft, "for i = 1 to nt", "if tl<i, HT.ID>[1, 2] # 'r:' then", "fitems<-1> = tl<i, HT.LABEL>", "fmap<-1> = i", "if i = fi then fdef = dcount(fmap, @fm)",
               "fstart = fdef", "call $tk_pickrec(ctx, 'list', fitems, fsel, fres, fstart)", "if fres = 'ok' then", "j = fmap<fsel>", "gosub set.focus")
       and "start.tile" not in ft and ordered(oky, "case nm = '/'\n         gosub find.tile", "case len(nm) = 1 and nm > ' '\n         gosub jump.letter"), ft[:300])
    ck("H34d the AI is told there is nowhere to run a command ('nocmd', field 11) when the Terminal tile is off for the account, BEFORE it is asked, and a 'command' answer is refused with a message and never reaches run.command in that case (TUI phase 2 review, b: the Terminal tile off "
       "means no command prompt through the AI either; this tightens a default)",
       ordered(th, "if terminal.off then actx<11> = 'nocmd'", "call $tk_ai('ask', ctx, actx, res)", "case res<1> = 'command' and terminal.off", "case res<1> = 'command'\n         sentence = res<2>")
       and "msg = 'the Terminal is turned off for this account'" in between(th, "case res<1> = 'command' and terminal.off", "case res<1> = 'command'\n"), between(th, "\nask.ai:\n", "\nstart.tile:\n"))
    aia = between(th, "\nask.ai:\n", "\n   ctxt = ")
    ck("H34b the AI is told which offered actions do more than NAVIGATE (S6, per proposal since handoff step 2): the flag (field 5) starts at 1 and is never made 0 by a pin; ai.more starts empty and a pin (id pin<n>) "
       "or the Terminal tile adds its id to it; ai.more - not a constant - is the twelfth field of what the AI is told, so that Enter alone accepts a delivered tile and rejects a pin or the Terminal tile",
       ordered(aia, "ai.nav = 1", "ai.more = ''", "if tl<i, HT.ID>[1, 3] = 'pin' or ta = 'terminal' then ai.more<1, -1> = tl<i, HT.ID>") and "acts : @fm : ai.nav" in th and "acts : @fm : 1" not in th
       and "actx<12> = ai.more" in th and "ai.nav = 0" not in th, aia)

    # ---- 3 Nov 26 (S.149; owner: "make ctrl+q leave for the prompt when you typed home") --------------------------------------------------------------------
    fin = between(th, "\nfinish:\n", "\n   return\n")
    mkk = between(th, "\nmake.keys:\n", "\noff.row:\n")
    ck("H85 the screen takes the flag that says whose it is BEFORE it asks for the terminal (menu.session = hstart, then hstart = 0), and Ctrl-Q may leave only when the screen was typed (not menu.session) "
       "and the Terminal tile is not off, worked out before the key table is made",
       ordered(th, "common /tkhome/ hflag, hlogto, hstart", "hlogto = 0", "menu.session = hstart + 0", "hstart = 0", "call $tk_open('home', '', ctx, err)")
       and ordered(th, "call !home_off(@who, off.list)", "leave.ok = (not(menu.session) and not(index(' ' : off.list : ' ', ' terminal ', 1)))", "gosub make.keys"), th[:200])
    ck("H85b ...when it may, Ctrl-Q is 'prompt' (leave) and Sign out has no key of its own (S.201), and the File menu has Back to the prompt before Sign out; when it may not, Ctrl-Q "
       "is Sign out as before; the loop leaves on Ctrl-Q (outcome leave), and no other key signs out",
       "if leave.ok then\n      call $tk_keys('add', keys, 'ctrl-q', 'prompt', 'leave', '', 1)\n   end else\n      call $tk_keys('add', keys, 'ctrl-q', 'sign out', 'signout', '', 1)\n   end" in mkk
       and "if leave.ok then\n      call $tk_keys('add', keys, '', 'sign out', 'signout', '', 1)\n      gosub off.row\n   end" in mkk
       and ordered(mkm, "if leave.ok then call $tk_keys('menu', keys, 'leave', '&File', '&Back to the prompt', '', '')", "call $tk_keys('menu', keys, 'signout', '&File', '&Sign out', '', '')")
       and "case nm = 'ctrl-q'\n         if leave.ok then\n            outcome = 'leave'\n            done = 1\n         end else\n            gosub do.signout\n         end\n" in oky and "alt-x" not in oky and "case nm = 'act:signout'" in oky,
       mkk[:300])
    leave_case = between(fin, "case outcome = 'leave'", "case 1")
    ck("H85c ...leaving closes the screen and nothing else (no QUIT, hflag untouched, so EXIT still ends the session), after the wall for an account whose Terminal tile is off; !home_entry and EXIT say "
       "hstart = 1 immediately before they start HOME",
       "call $tk_close(ctx)" in leave_case and "quit" not in leave_case and "hflag" not in leave_case
       and fin.find("case terminal.off and outcome # 'signout'") < fin.find("case outcome = 'leave'")
       and "hstart = 1\n   execute 'home'" in he and "hstart = (hflag = 1)\n      execute 'home'" in ex, repr(leave_case))
    return rows


MUTANTS = [
    ("finish no longer signs out a confined account", "tool_home", "      case terminal.off and outcome # 'signout'", "      case @false"),
    ("home_entry leaves a confined account at the prompt", "home_entry", "   if index(' ' : off : ' ', ' terminal ', 1) then\n      sleep 2\n      execute 'quit'\n   end\n", ""),
    ("a header tile that is off is placed on the previous tile", "tool_home", "   gosub add.tile\n   if not(added) then return\n", "   gosub add.tile\n"),
    ("a tile that is off is added", "tool_home", "   if index(off.set, ' ' : id : ' ', 1) then return        ;* turned off by the administrator: not on the page at all\n", ""),
    ("the menus are made once, at the start", "tool_home", "   gosub alloc.styles\n   gosub make.menus\n   return", "   gosub alloc.styles\n   return"),
    ("the Terminal entry stays choosable", "tool_home", "   if terminal.off then call $tk_keys('why', keys, 'terminal', H.TILE.OFF, '', '', '')\n", ""),
    ("an empty group still has a heading", "tool_home", "      for k = 1 to ng\n         if gr<k, HG.BAND> = b and gtiles<k> > 0 then", "      for k = 1 to ng\n         if gr<k, HG.BAND> = b then"),
    ("home_off forgets the account's own list", "home_off", "read arec from af, downcase(acct) then off = arec<ACC$TILES.OFF>", "read arec from af, downcase(acct) then null"),
    ("home_off reads another account's list", "home_off", "read arec from af, downcase(acct) then", "read arec from af, 'sdsys' then"),
    ("SET.TILE does not ask for the administrator", "settile", "   if not(kernel(K$ADMINISTRATOR, -1)) then\n      stop sysmsg(2001) ;* Command requires administrator privileges\n   end\n", ""),
    ("SET.TILE lets sign out be turned off", "settile", "   if tile = 'signout' and state = 'off' then stop sysmsg(12883)\n", ""),
    ("SET.TILE writes another field", "settile", "acc.rec<ACC$TILES.OFF> = new.list", "acc.rec<ACC$START> = new.list"),
    ("SET.TILE says nothing when nothing changes", "settile", "display sysmsg(12882, tile, state, who)", "null"),
    ("the register field moves", "keys.h", "$define ACC$TILES.OFF    17 ", "$define ACC$TILES.OFF    16 "),
    ("home_entry no longer asks for a terminal first", "home_entry", "   if @tty[1, 5] # '/dev/' then return\n", ""),
    ("home_entry forgets the API server", "home_entry", "   if kernel(K$IS.SDAPISRVR, 0) then return\n", ""),
    ("home_entry forgets the LOGTO the home screen runs itself", "home_entry", "   if hlogto then return\n", ""),
    ("home_entry forgets the command level of a LOGTO", "home_entry", "      if kernel(K$CPROC.LEVEL, 0) > 1 then return\n", "      null\n"),
    ("home_entry starts the screen for the terminal word", "home_entry", "   if start # 'menu' then return\n", ""),
    ("home_entry reads the field of another account", "home_entry", "read arec from acc.f, downcase(@who)", "read arec from acc.f, 'sdsys'"),
    ("the sign-on hook has no terminal test", "cproc", "   if @tty[1, 5] = '/dev/' then call !home_entry('signon')\n", "   call !home_entry('signon')\n"),
    ("the LOGTO hook has no terminal test", "cproc", "   if @tty[1, 5] = '/dev/' then call !home_entry('logto')\n", "   call !home_entry('logto')\n"),
    ("a third call to the hook appears", "cproc", "   if @tty[1, 5] = '/dev/' then call !home_entry('logto')\n", "   if @tty[1, 5] = '/dev/' then call !home_entry('logto')\n   call !home_entry('x')\n"),
    ("EXIT starts the screen without the flag", "exit", "if hflag and @tty[1, 5] = '/dev/' then", "if @tty[1, 5] = '/dev/' then"),
    ("EXIT never ends the session", "exit", "      execute 'quit'\n", "      null\n"),
    ("SET.START.DEFAULT does not ask for the administrator", "setstart", "   if not(kernel(K$ADMINISTRATOR, -1)) then\n      stop sysmsg(2001) ;* Command requires administrator privileges\n   end\n", ""),
    ("SET.START.DEFAULT takes any word", "setstart", "      case want = 'menu' or want = 'terminal'", "      case 1"),
    ("the Terminal tile does not set the flag", "tool_home", "         hflag = (if menu.session then 1 else 2)          ;* EXIT comes back here, to the same kind of screen (S.201)\n", ""),
    ("the Terminal tile shows the banner before giving the screen back", "tool_home", "         call $tk_close(ctx)\n         hflag = (if", "         hflag = (if"),
    ("Sign out does not ask", "tool_home", "   if b = 1 then\n      outcome = 'signout'", "   if @true then\n      outcome = 'signout'"),
    ("Enter on the sign-out box signs out", "tool_home", "default 2 returning b", "default 1 returning b"),
    ("the logto does not mark hlogto", "tool_home", "   hlogto = 1\n   execute 'logto ' : acct trapping aborts", "   execute 'logto ' : acct trapping aborts"),
    # 28 Oct 26, S.88 phase 2 (plan 2.5, 2.8; defects S6, D4): H34 holds these
    ("a refused command ends HOME again", "tool_home", "   execute sentence trapping aborts\n", "   execute sentence\n"),
    ("an aborted app's screen and break key are not given back", "tool_home", "   call $sl_cleanup\n   if pause or aborted then gosub wait.key", "   if pause or aborted then gosub wait.key"),
    # 28 Oct 26, TUI phase 2 review (a) and (b): H34c and H34d hold these
    ("an aborted command is drawn over again", "tool_home", "   if pause or aborted then gosub wait.key", "   if pause then gosub wait.key"),
    ("the abort is judged by @abort.code, which is 0 again", "tool_home", "aborted = (@abort.message # sentinel)", "aborted = (@abort.code # 0)"),
    ("the abort is judged after the cleanup", "tool_home", "   aborted = (@abort.message # sentinel)                  ;* read before $sl_cleanup\n   call $sl_cleanup\n", "   call $sl_cleanup\n   aborted = (@abort.message # sentinel)\n"),
    ("the sentinel is not set before the command", "tool_home", "   gosub set.sentinel\n   execute sentence trapping aborts", "   execute sentence trapping aborts"),
    ("the AI may still offer a command with the Terminal off", "tool_home", "   if terminal.off then actx<11> = 'nocmd'\n", ""),
    ("the AI is told nocmd only when the Terminal is on", "tool_home", "   if terminal.off then actx<11> = 'nocmd'", "   if not(terminal.off) then actx<11> = 'nocmd'"),
    ("a command answer runs with the Terminal off", "tool_home", "      case res<1> = 'command' and terminal.off\n         msg = 'the Terminal is turned off for this account'", "      case res<1> = 'command' and @false\n         msg = 'the Terminal is turned off for this account'"),
    ("a LOGTO that aborts ends HOME", "tool_home", "   execute 'logto ' : acct trapping aborts ", "   execute 'logto ' : acct ;"),
    ("the AI is told every action only navigates", "tool_home", "acts : @fm : ai.nav", "acts : @fm : 1"),
    ("a pin is not named as doing more", "tool_home", "if tl<i, HT.ID>[1, 3] = 'pin' or ta = 'terminal' then ai.more<1, -1> = tl<i, HT.ID>", "if ta = 'terminal' then ai.more<1, -1> = tl<i, HT.ID>"),
    ("the Terminal tile is not named as doing more", "tool_home", "if tl<i, HT.ID>[1, 3] = 'pin' or ta = 'terminal' then ai.more<1, -1> = tl<i, HT.ID>", "if tl<i, HT.ID>[1, 3] = 'pin' then ai.more<1, -1> = tl<i, HT.ID>"),
    ("a pin turns Enter-accepts off for the whole page again", "tool_home", "if tl<i, HT.ID>[1, 3] = 'pin' or ta = 'terminal' then ai.more<1, -1> = tl<i, HT.ID>", "if tl<i, HT.ID>[1, 3] = 'pin' or ta = 'terminal' then ai.nav = 0"),
    ("the library is not told which actions do more", "tool_home", "   actx<12> = ai.more ", "   null "),
    ("a tile draws outside the panel", "tool_home", "      if sy >= lo and sy <= hi then", "      if @true then"),
    ("the scroll bar is not drawn", "tool_home", "   if ch > ph then\n      call $sl_scrollbar", "   if @false then\n      call $sl_scrollbar"),
    ("a piped session is let in", "tool_home", "   if @tty[1, 5] # '/dev/' then\n      display sysmsg(12868)", "   if @false then\n      display sysmsg(12868)"),
    ("the home entry keeps the lock of an absent start.default", "home_entry", "         if not(unassigned(df)) then close df\n", "         null\n"),
    ("set.tile lets the Back tile be turned off", "settile", "if tile = 'back' and state = 'off' then stop sysmsg(12967)", "if @false then stop sysmsg(12967)"),
    ("modify.account loses a start word", "modifya", "FILES-ADMIN-OFF,START-MENU,START-TERMINAL,START-DEFAULT,PINS-ON,PINS-OFF,SUSPENDED", "FILES-ADMIN-OFF,START-MENU,START-TERMINAL,PINS-ON,PINS-OFF,SUSPENDED"),
    ("modify.account loses a pins word", "modifya", "START-DEFAULT,PINS-ON,PINS-OFF,SUSPENDED", "START-DEFAULT,PINS-ON,SUSPENDED"),
    ("pins-on writes another field", "modifya", "os.field = ACC$PINS\n            os.want  = @true", "os.field = ACC$NET\n            os.want  = @true"),      # 13 Nov 26 Windows: Core's two-line form
    ("home_pins does not ask the gate", "home_pins", "   if not(on) then return\n", ""),
    ("home_pins lets everyone have the gate", "home_pins", "on = (upcase(trim(arec<ACC$PINS>)) = 'YES')", "on = 1"),
    ("home_pins keeps control characters", "home_pins", "label = trim(convert(ctl, blanks, rec<i, 1>))[1, 21]", "label = trim(rec<i, 1>)[1, 21]"),
    ("MY.MENU does not ask the gate", "mymenu", "   if not(on) then\n      display sysmsg(12891)\n      stop\n   end\n", ""),
    ("MY.MENU writes another record", "mymenu", "write its to f, 'home' on error writeok = @false", "write its to f, 'other' on error writeok = @false"),
    ("the home screen shows programs without the gate", "tool_home", "   if pins.on then\n      bnd += 1", "   if @true then\n      bnd += 1"),
    ("the register field for programs moves", "keys.h", "$define ACC$PINS         18 ", "$define ACC$PINS         17 "),
    ("the menu management page can run another command", "tool_menus", "allow = 'modify.account set.tile set.start.default'", "allow = 'modify.account set.tile set.start.default sh'"),
    ("modify.account writes another field", "modifya", "acc.new<ACC$START> = start.want", "acc.new<ACC$SH> = start.want"),
    ("the register field moves", "keys.h", "$define ACC$START        16 ", "$define ACC$START        15 "),
    ("the scroll bar goes black again in blue", "sl_theme", "'scroll=black,cyan,bold'", "'scroll=black,cyan,'"),
    ("the Audit trail tile is built for everyone", "tool_home", "gosub add.tile\n      id = 'audit' ;", "gosub add.tile\n   end\n   if @true then\n      id = 'audit' ;"),
    ("the Accounts tile is built for everyone", "tool_home", "      id = 'accounts' ; grp = g ;", "   end\n   if @true then\n      id = 'accounts' ; grp = g ;"),
    ("the Gates tile runs another page", "tool_home", "act = 'cmd:tool.gates'", "act = 'cmd:tool.config'"),      # 13 Nov 26 Windows: Linux's Audit trail tile, whose verb Core lacks (H28 PENDING)
    ("the Remote servers tile is gone", "tool_home", "      id = 'remote' ; grp = g ;", "      id = 'remoteX' ; grp = g ;"),
    ("the administrator's People and access group is given a band of its own", "tool_home", "      * who may do what, and who is on: the people and access group\n      g += 1", "      * who may do what, and who is on: the people and access group\n      bnd += 1\n      g += 1"),
    ("the Files tile runs another app", "tool_home", "act = 'cmd:tool.files'", "act = 'cmd:tool.keys'"),
    ("the Develop group moves to a band of its own before Everyone", "tool_home", "   gr<g> = 'Everyone' : @vm : bnd : @vm : 6", "   gr<g> = 'Develop' : @vm : bnd : @vm : 6"),
    ("the Gates tile is moved out of its group name", "tool_home", "gr<g> = 'People and access'", "gr<g> = 'People'"),
    ("a live line is read for an account holder too", "tool_home", "live.chg = ''\n   if not(is.admin) then return", "live.chg = ''"),
    ("a live line writes to the audit trail", "tool_home", "   call !listu(ludata)\n", "   call !listu(ludata)\n   void kernel(K$AUDIT, 'home live')\n"),
    ("the home screen no longer names the product and version", "tool_home", "mm : '  -  SD Core for Windows ' : SD.REV.STAMP, '72L')", "mm, '60L')"),
    ("the key wait no longer reads the live lines again", "tool_home", "gosub draw.clock\n            gosub live.draw", "gosub draw.clock"),
    ("the live line is written over the dimmed reason", "tool_home", "s = '  ' : (if tl<di, HT.WHY> # '' then tl<di, HT.WHY> else (if tl<di, HT.LIVE> # '' then tl<di, HT.LIVE> else tl<di, HT.SUB>))", "s = '  ' : (if tl<di, HT.LIVE> # '' then tl<di, HT.LIVE> else tl<di, HT.SUB>)"),
    ("MENU runs another program for every account", "menu.n", "$tool_home", "$exit"),
    ("MENU is missing from SDSYS's VOC", "menu.t", "$tool_home", ""),
    # ---- 26 Oct 26 (S.75, home): sub-menus
    ("a folder tile may open the menu that is open", "tool_home", "   already = (mname = cur.menu or mname = '')\n", "   already = 0\n"),
    ("a sub-menu has no depth limit", "tool_home", "   if dep >= HM.DEPTH then\n", "   if @false then\n"),
    ("Back reads the stack before it asks whether there is one", "tool_home", "   if dep = 0 then return\n   e = stk<dep>\n", "   e = stk<dep>\n   if dep = 0 then return\n"),
    ("Back forgets the tile that had the focus", "tool_home", "   want.id = e<1, 2>\n", "   want.id = ''\n"),
    ("Back leaves the level on the stack", "tool_home", "   del stk<dep>\n", ""),
    ("Esc no longer goes back", "tool_home", "      case nm = 'esc' or nm = 'bs'\n", "      case nm = 'bs'\n"),
    ("the Back tile is built on the top page too", "tool_home", "   if cur.menu # '' then\n      * a sub-menu page: the way back", "   if @true then\n      * a sub-menu page: the way back"),
    ("pick.level keeps the groups of every menu", "tool_home", "      if gr<pk, HG.MENU> = cur.menu then\n", "      if @true then\n"),
    ("pick.level keeps a folder whose menu is empty", "tool_home", "            if pn = 0 then\n               del tl<pi>", "            if pn = -1 then\n               del tl<pi>"),
    ("Switch account keeps the sub-menu", "tool_home", "   cur.menu = ''" + " " * 42 + ";* the screen of the new account starts at its top page\n   stk = ''\n   crumb = ''\n", ""),
    ("the status line does not show the path", "tool_home", "      ttl := ' > ' : crumb<ck>\n", "      null\n"),
    ("the identity does not move right of the Back tile", "tool_home", "   idx = (if cur.menu # '' then xcol<2> else xcol<1>)", "   idx = xcol<1>"),
    # ---- 28 Oct 26, S.88 L2: the header tiles placed by the layout (H30d), the header cleared up to the Switch account tile (H30h)
    ("the Back tile stands where Sign out does", "tool_home", "               tl<i, HT.X> = xcol<1>", "               tl<i, HT.X> = xcol<ncol>"),
    ("the header tiles are placed once and not after a resize", "tool_home", "layout:\n   gosub place.header\n", "layout:\n"),
    ("the header is cleared over the Switch account tile", "tool_home", "screen clear at 0,hdy size xcol<ncol - 1> - 1,3", "screen clear at 0,hdy size xcol<ncol - 1> + 5,3"),
    ("the AI menu action does nothing", "tool_home", "if ctx<TK.C.AI> then\n            gosub ai.focus.on", "if ctx<TK.C.AI> then\n            null"),
    ("F1 asks for another record", "tool_home", "'tool.home.page', hm, 0, 0)", "'tool.home.nopage', hm, 0, 0)"),
    ("the AI is offered the copies of the Recent group", "tool_home", "if tl<i, HT.ID>[1, 2] # 'r:' then                ;* a recent", "if @true then                ;* a recent"),
    ("an empty band takes a row", "tool_home", "      if c0 > 0 then ys = bandend + 1", "      ys = bandend + 1"),
    ("the Esc key is on the function-key row of the top page", "tool_home", "   if cur.menu # '' then call $tk_keys('add', keys, 'esc', 'back', 'back', '', 1)\n", "   call $tk_keys('add', keys, 'esc', 'back', 'back', '', 1)\n"),
    # ---- the Recent group
    ("the Recent list is read for an account whose group the administrator turned off", "tool_home", "   if index(off.set, ' recent ', 1) then return\n   call !home_recent('get'", "   call !home_recent('get'"),
    ("a recent tile may run what is not a command of the table", "tool_home", " and tl<ri, HT.ACT>[1, 4] = 'cmd:' then", " then"),
    ("a recent copy keeps the id of the tile", "tool_home", "            t<1, HT.ID> = 'r:' : tl<ri, HT.ID>\n", ""),
    ("the Recent group is the second group", "tool_home", "            t<1, HT.GROUP> = 1\n", "            t<1, HT.GROUP> = 2\n"),
    ("a started tile is noted when the group is off", "tool_home", "note.recent:\n   if not(rc.on) then return\n", "note.recent:\n"),
    ("a pinned program is noted", "tool_home", "   if rid[1, 3] = 'pin' then return\n", ""),
    ("the View entry ignores the administrator's switch", "tool_home", "toggle.recent:\n   if index(off.set, ' recent ', 1) then\n      msg = sysmsg(12966)\n      return\n   end\n", "toggle.recent:\n"),
    ("the View entry stays choosable when the administrator turned the group off", "tool_home", "   if index(off.set, ' recent ', 1) then call $tk_keys('why', keys, 'recent', H.TILE.OFF, '', '', '')\n", ""),
    ("!home_recent ADD writes when the group is off", "home_recent", "   if not(got) or rec<1> # 'on' then\n      release f, 'recent'\n      close f\n      return\n   end\n", ""),
    ("!home_recent ADD ignores a lock", "home_recent", "   if lk then\n      close f\n      return\n   end\n", ""),
    ("!home_recent ADD keeps more than six", "home_recent", "      if idok and id # a and n < RC.MAX then", "      if idok and id # a then"),
    ("!home_recent GET lists an id that is not plain", "home_recent", "      if idok and dcount(b, @fm) < RC.MAX then", "      if dcount(b, @fm) < RC.MAX then"),
    ("!home_recent OFF deletes another record", "home_recent", "   delete f, 'recent'", "   delete f, 'home'"),
    ("!home_recent ON writes another word", "home_recent", "      write 'on' to f, 'recent' on error wok = @false", "      write 'off' to f, 'recent' on error wok = @false"),
    ("!home_recent takes capitals in an id", "home_recent", "   okchars = 'abcdefghijklmnopqrstuvwxyz'", "   okchars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ'"),
    ("!home_recent takes an id with a blank in it", "home_recent", "len(id) <= 20 and index(id, ' ', 1) = 0 and trim(", "len(id) <= 20 and trim("),
    ("!home_recent keeps a list of twenty", "home_recent", "$define RC.MAX   6 ", "$define RC.MAX   20"),
    # ---- the standard ids
    ("SET.TILE does not know the Files tile", "settile", "signout files voc dict query bulk catalog test recent'\n", "signout voc dict query bulk catalog test recent'\n"),
    ("the menu management page does not list recent", "tool_menus", "'test' : @fm : 'recent'\n", "'test'\n"),
    ("a development tile has an id the lists do not know", "tool_home", "id = 'test' ; grp = g ;", "id = 'tests' ; grp = g ;"),
    ("the menu management page loses a label", "tool_menus", "'Programs' : @fm : 'Tests'", "'Programs'"),
    # ---- 2 Nov 26 (S.88 U9): the toolkit's menu bar and type-to-find - the first of these is marker M_U9 for --from=
    ("the page draws a SCREEN MENUBAR of its own again", "tool_home", "   ctx<TK.C.BAR> = ''", "   screen menubar menus row 0 draw else null"),
    ("the bar is drawn after the frame", "tool_home", "      call $tk_menubar('draw', ctx, keys, ttl, '', '', mr)  ;* the bar first: it writes row 0 whole, and the frame then writes the app name at its right end\n      call $tk_frame(ctx, keys, ttl, msg)\n",
     "      call $tk_frame(ctx, keys, ttl, msg)\n      call $tk_menubar('draw', ctx, keys, ttl, '', '', mr)\n"),
    ("the bar takes keys while the AI line has the focus", "tool_home", "      if nm # '' and not(aif) then\n", "      if nm # '' then\n"),
    ("Esc in a sub-menu opens the bar instead of going back", "tool_home", "         busy = (cur.menu # '')", "         busy = 0"),
    ("a click on the bar while the AI line has the focus is typed into the line", "tool_home", "         if aif then gosub ai.leave\n         gosub on.key", "         gosub on.key"),
    ("F10 is a row of the page again", "tool_home", "   call $tk_keys('add', keys, 'f5', 'refresh', 'refresh', '', 1)\n", "   call $tk_keys('add', keys, 'f5', 'refresh', 'refresh', '', 1)\n   call $tk_keys('add', keys, 'f10', 'menu', 'menu', '', 1)\n"),
    ("a menu action has no key", "tool_home", "   call $tk_keys('add', keys, 'ctrl-r', 'recent', 'recent', '', 1)\n", ""),
    ("Ctrl-T leaves for the Terminal when the tile is off", "tool_home", "         if terminal.off then\n            msg = H.TILE.OFF", "         if 0 then\n            msg = H.TILE.OFF"),
    ("F6 gives the focus to a line that is not there", "tool_home", "      case nm = 'f6' or nm = 'shift-f6'\n         if ctx<TK.C.AI> then", "      case nm = 'f6' or nm = 'shift-f6'\n         if 1 then"),
    ("Ask the AI is choosable when the AI is off", "tool_home", "   if not(ctx<TK.C.AI>) then call $tk_keys('why', keys, 'ai', H.AI.OFF, '', '', '')\n", ""),
    ("the found tile is started at once", "tool_home", "      gosub set.focus\n      msg = tl<fi, HT.LABEL> : ': Enter starts it'", "      gosub set.focus\n      gosub start.tile"),
    ("a cancelled find moves the focus", "tool_home", "   if fres = 'ok' then\n      j = fmap<fsel>", "   if 1 then\n      j = fmap<fsel>"),
    ("/ jumps to a tile that begins with it", "tool_home", "      case nm = '/'\n         gosub find.tile\n", ""),
    # 3 Nov 26, S.149: Ctrl-Q leaves for the prompt when HOME was typed there
    ("Ctrl-Q signs out of a screen typed at the prompt", "tool_home", "      case nm = 'ctrl-q'\n         if leave.ok then", "      case nm = 'ctrl-q'\n         if 0 then"),
    ("Ctrl-Q leaves a screen the session started in", "tool_home", "leave.ok = (not(menu.session) and not(index(' ' : off.list : ' ', ' terminal ', 1)))", "leave.ok = (not(index(' ' : off.list : ' ', ' terminal ', 1)))"),
    ("Ctrl-Q leaves an account whose Terminal tile is off", "tool_home", "leave.ok = (not(menu.session) and not(index(' ' : off.list : ' ', ' terminal ', 1)))", "leave.ok = (not(menu.session))"),
    ("Sign out is not in the table when Ctrl-Q leaves", "tool_home", "      call $tk_keys('add', keys, '', 'sign out', 'signout', '', 1)", "      null"),
    ("a typed screen comes back from the Terminal tile as the session's own", "tool_home", "hflag = (if menu.session then 1 else 2)", "hflag = 1"),
    ("File > Sign out does nothing on a typed screen", "tool_home", "      case nm = 'act:signout'  ", "      case nm = 'act:nothing'  "),
    ("the flag that says whose the screen is is never taken", "tool_home", "   hstart = 0                                           ;* taken: a later HOME typed at the prompt the screen gave is typed\n", ""),
    ("!home_entry does not say the screen is the session's own", "home_entry", "   hstart = 1                                  ;* 3 Nov 26: this screen is the session's own (the account starts in the menu), not one typed at the prompt: Ctrl-Q signs out\n", ""),
    ("EXIT does not say the screen is the session's own again", "exit", "      hstart = (hflag = 1)                     ;* 10 Nov 26 (S.201): back from the Terminal tile, the screen is what it was before the tile was used: the session's own (1) or typed at the prompt (2)\n", ""),
    ("leaving signs out", "tool_home", "      case outcome = 'leave'\n         call $tk_close(ctx)", "      case outcome = 'leave'\n         execute 'quit'\n         call $tk_close(ctx)"),
]
M_U9 = len(MUTANTS) - 16 - 8
M_LEAVE = len(MUTANTS) - 8


def selftest(first=0):
    s = load()
    base = [n for n, ok, _ in checks(s) if not ok]
    if base:
        print("REFUSING - the unmutated source already fails: %s" % ", ".join(base), file=sys.stderr)
        return 2
    holes = 0
    print("--- self-test: the unmutated source passes; each mutation must be CAUGHT and match its text once ---")
    for name, which, old, new in MUTANTS[first:]:
        if s[which].count(old) != 1:
            print("  [FAIL] %s: the text to mutate matches %d times in %s, not once" % (name, s[which].count(old), which))
            holes += 1
            continue
        s2 = dict(s)
        s2[which] = s[which].replace(old, new)
        caught = [n for n, ok, _ in checks(s2) if not ok]
        if caught:
            print("  [pass] %s: caught by %s" % (name, ", ".join(caught[:3])))
        else:
            print("  [FAIL] %s: NOT CAUGHT by any check" % name)
            holes += 1
    print("self-test: %d mutants (from %d; M_U9 = %d), %d not caught" % (len(MUTANTS) - first, first, M_U9, holes))
    return 1 if holes else 0


def main():
    if "--selftest" in sys.argv:
        first = 0
        for a in sys.argv:
            if a.startswith("--from="):
                first = int(a[len("--from="):])
        sys.exit(selftest(first))
    s = load()
    rows = checks(s)
    bad = 0
    for name, ok, detail in rows:
        print("  [%s] %s%s" % ("PASS" if ok else "FAIL", name, ("   <- " + detail) if (detail and not ok) else ""))
        bad += 0 if ok else 1
    print("test-home-units: %d checks, %d failed" % (len(rows), bad))
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
