#!/usr/bin/env python3
"""test-idekeys-units.py - the IDE's key map and the memo's editing keys (S.88 Phase 4, the owner's settled keys of 20 Oct 2026, plan decisions D28, D31, D32, D33), as invariants read off the source.

  python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/test-idekeys-units.py
  python3 .../test-idekeys-units.py --selftest

No sudo, no install, no sd.  Exit 0 every check passed, 1 a check failed, 2 it could not run.

WHAT IT HOLDS.  `do.key` of `gpl.bp/ide` is the key map: F2, F3 and F11 have no case, Ctrl-S is the only save, F5 runs, F7 debugs, F8 compiles, F9 builds (compile and catalogue), F6 and Shift-F6 are the
next and previous pane (the tree is reached by the ring of panes, the Go menu entry "Files and records", which has no key, and the mouse), the tabs are Ctrl-PageDown / Ctrl-PageUp and, for a terminal that keeps
those for its own tabs (GNOME Terminal), Alt-PageDown / Alt-PageUp, Ctrl-W closes, Ctrl-N is New and Ctrl-O is Open.  Every key a menu (messages 12230-12233) shows is bound in `do.key` to the SAME command word,
every command word of the menus (bound to a key or not) has a case in `run.cmd`, and the help (12219-12221) names the keys the map binds and no key it does not (F3 is never named as the tree).  The editor
passes exactly Ctrl-E to the IDE.  The memo (`gpl.bp/sl_memo`) has F3 for find next, Shift-F3 for find previous, Ctrl-A for select all, Ctrl-D duplicating the line and Ctrl-K cutting it, and neither Ctrl-O nor
Ctrl-N.  SED (`gpl.bp/sed`, `key.rec`) binds Alt-PageDown / Alt-PageUp to the next / previous buffer beside the Ctrl forms.  The tree leaves the dollar entries out and the name form refuses a typed one.

***IT RUNS NOTHING, SO IT CANNOT SAY THAT A KEY WORKS ON A SCREEN***: that is `sandbox-ide.py`, `sandbox-ide-small.py`, `sandbox-ide-fresh.py` and `sandbox-screen.py` (a pseudo-terminal, the disk and the
emulated screen as the evidence).  What a text check is for: the properties an edit can move while everything still compiles - a key bound to the wrong word, a menu that shows a key the map does not
have, a help that still names the old key.

--selftest breaks each invariant in the way an edit plausibly would and requires a check to notice; a mutant that nothing catches is a failure of the self-test.

28 Oct 26 (the editor merge, stage B): the Go menu has "Open the include" (command word `include`, no key: a terminal sends Ctrl-Enter as Return, and the
owner's keys of 20 Oct are not rebound) between Previous pane and Edit in SED; IK24 holds that run.cmd runs do.include for it and no key leads to it.

28 Oct 26 (approved by the owner): Tab indents in the IDE's editor.  IK25-IK27 hold the memo's opt-in tabindent (Tab / Shift-Tab are the area's keys only
with it, never in a viewer), indent.in / indent.out (one undo step, blanks only, to the stop; no step for nothing), and that the IDE alone sets it to 3 and its
help says so; 12 mutants from M_TAB.  That a Tab typed on a screen indents is sandbox-ide.py section TAB.

3 Nov 26 (S.75 DV10, Opus decision 12c): the Tools menu (message 15004) opens the seven development pages.  IK28 holds that it is put before AI and Help, that
its entries are exactly the seven verbs with no key, that run.cmd sends a tool. word to do.tool only, and that do.tool runs ONLY those seven, through the
terminal hand-over as Run does (the text kept, leave.screen, an execute with TRAPPING ABORTS and no CAPTURING, retake.screen) and never through do.xeq; mutants
from M_DV10.  That a page opens and the IDE comes back is sandbox-ide-tools.py.
"""

import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SDSYS = os.path.normpath(os.path.join(HERE, "..", "sdsys"))
GPL = os.path.join(SDSYS, "gpl.bp")
MSG = os.path.join(SDSYS, "messages")
FILES = {
    "ide": os.path.join(GPL, "ide"),
    "ide_name": os.path.join(GPL, "ide_name"),
    "memo": os.path.join(GPL, "sl_memo"),
}
for _n in (12209, 12212, 12219, 12220, 12221, 12230, 12231, 12232, 12233, 12688, 15004):
    FILES["m%d" % _n] = os.path.join(MSG, str(_n))

# the key map, as the owner settled it: key name -> command word
KEYMAP = {
    # 8 Nov 26 (S.179, the owner: the same keys on every page; F5 refresh everywhere, run on F9): F5 and Ctrl-L refresh, F9 run, Shift-F9 catalog, Alt-G goto, Ctrl-T theme, Ctrl-K keys
    "f1": "help", "ctrl-s": "save", "f4": "nexterr", "f5": "refresh", "ctrl-l": "refresh", "f9": "run", "shift-f9": "catalog", "f6": "nextpane", "shift-f6": "prevpane", "f7": "debug",
    "shift-f7": "bptoggle", "f8": "compile",
    "ctrl-pgdn": "nexttab", "ctrl-pgup": "prevtab", "alt-pgdn": "nexttab", "alt-pgup": "prevtab", "f10": "menu", "ctrl-q": "quit", "ctrl-w": "close", "ctrl-n": "new", "ctrl-o": "open",
    "ctrl-e": "zoom","alt-g": "goto", "alt-r": "macrec", "alt-p": "macrun", "ctrl-r": "replace", "f12": "fields", "ctrl-t": "theme", "ctrl-k": "keys",
}
# the help: the line that names a key, a word its description holds, the key name it stands for
# a key name of None is a key the editor (the memo) owns and the IDE does not bind: only the help's wording is held (the memo's own keys are IK18)
HELP = (
    ("m12219", "Ctrl-S", "Save", "ctrl-s"), ("m12219", "Ctrl-N", "New record", "ctrl-n"), ("m12219", "Ctrl-O", "Open a record", "ctrl-o"),
    ("m12219", "Ctrl-W", "Close the record", "ctrl-w"), ("m12219", "Ctrl-PgDn, PgUp", "record tab", "ctrl-pgdn"),
    ("m12219", "Alt-PgDn, PgUp", "own tabs", "alt-pgdn"), ("m12219", "F6, Shift-F6", "previous pane", "shift-f6"),
    ("m12220", "F4", "Next error", "f4"), ("m12220", "F9", "Run", "f9"), ("m12220", "F7", "Debug", "f7"), ("m12220", "F8", "Compile", "f8"),
    ("m12220", "F5, Ctrl-L", "Draw the screen again", "f5"), ("m12220", "Ctrl-T", "theme", "ctrl-t"), ("m12220", "Ctrl-K", "keys", "ctrl-k"),
    ("m12220", "Shift-F9", "compile and catalog", "shift-f9"), ("m12220", "Alt-G", "Go to a line", "alt-g"), ("m12220", "Ctrl-E", "fills the screen", "ctrl-e"),
    ("m12220", "F12", "as fields", "f12"),
    ("m12221", "F3, Shift-F3", "previous", None), ("m12221", "Esc, F10", "menus", "f10"), ("m12221", "Ctrl-Q", "Quit", "ctrl-q"), ("m12221", "F1", "This screen", "f1"),
    ("m12221", "Ctrl-R", "Replace", "ctrl-r"),
)
FILE_MENU = ["new", "open", "save", "saveas", "writeas", "spool", "close", "quit"]
GO_MENU = ["goto", "nexterr", "nexttab", "prevtab", "tree", "nextpane", "prevpane", "include", "zoom", "fields", "dform", "nextsel", "filter"]     # 31 Oct 26 (S.90 stage 2): the dictionary item form, last, no key; 9 Nov 26 (S.184 stage 1): Zoom the editor (Ctrl-E) before Edit in SED, which has no key; 9 Nov 26 (S.184 stage 3): Next record from the list, last, no key
UNKEYED = ["bpclear", "debug1", "dform", "downcase", "expandtabs", "export", "filter", "find", "findopts", "format", "import", "include", "nextsel", "qreplace", "runargs", "saveas", "spool", "stamp", "tree", "upcase", "view", "writeas", "xeq", "xeqterm"]       # 29 Oct 26 (stage D): the editing commands have no key; 9 Nov 26 (S.184 stage 3): Stamp, Expand tabs, Run with arguments, Next record from the list, Run a command at the terminal
SEARCH_MENU = ["find", "replace", "view", "qreplace", "findopts", "upcase", "downcase", "import", "export", "stamp", "expandtabs"]
BUILD_MENU = ["compile", "catalog", "run", "debug", "xeq", "format", "debug1", "bptoggle", "bpclear", "runargs", "xeqterm"]     # 2 Nov 26 (S.98 H2): the breakpoint entries; 9 Nov 26 (S.184 stage 3): Run with arguments, then Run a command at the terminal, last


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


def block(text, label):
    """The text of an internal subroutine: from its label to the next label at the start of a line (or to the end)."""
    m = re.search(r"^" + re.escape(label) + r":\s*$", text, re.M)
    if not m:
        return ""
    n = re.search(r"^[a-z][a-z.0-9]*:\s*$|^end\s*$", text[m.end():], re.M)
    return text[m.start(): m.end() + (n.start() if n else len(text))]


def case_block(text, head):
    """The lines of one `case` of a begin-case, from its head to the next `case` at the same indent."""
    m = re.search(r"^(\s*)" + re.escape(head) + r"\s*(?:;.*)?$", text, re.M)
    if not m:
        return ""
    ind = m.group(1)
    n = re.search(r"^" + ind + r"(?:case\b|end case)", text[m.end():], re.M)
    return text[m.start(): m.end() + (n.start() if n else len(text))]


def keymap_of(text):
    """do.key's `case edata = 'k'` (or `case edata = 'k' or edata = 'k2'`) / `cmd = 'w'` pairs, as a list (a key bound twice shows twice)."""
    out = []
    for heads, cmd in re.findall(r"case ((?:edata = '[a-z0-9-]+'(?: or )?)+)\s*\n\s*cmd = '([a-z.]+)'", block(text, "do.key")):
        for k in re.findall(r"edata = '([a-z0-9-]+)'", heads):
            out.append((k, cmd))
    return out


def menu_entries(msg):
    """(label, key text, command word) of each entry of a menu message, after its title."""
    parts = msg.strip("\n").split("|")
    out = []
    for e in parts[1:]:
        f = e.split("~")
        out.append((f[0], f[1] if len(f) > 1 else "", f[2] if len(f) > 2 else ""))
    return out


def keyname(shown):
    """'^PgDn' -> 'ctrl-pgdn', 'F4' -> 'f4', '' -> ''."""
    if shown.startswith("^"):
        return "ctrl-" + shown[1:].lower()
    return shown.lower()


def help_text(msg):
    return msg.replace("\\n", "\n")


def checks(raw):
    rows = []

    def ck(i, what, ok, detail=""):
        rows.append((i, what, bool(ok), detail))

    ide = strip_bas(raw["ide"])
    inm = strip_bas(raw["ide_name"])
    memo = strip_bas(raw["memo"])
    dk = block(ide, "do.key")
    rc = block(ide, "run.cmd")
    pairs = keymap_of(ide)
    bound = dict(pairs)
    menus = {n: menu_entries(raw["m%d" % n]) for n in (12230, 12231, 12232, 12233)}
    ck("IK0", "NULL CASE: the IDE, its name form, the memo, SED, the key map (22 pairs or more), run.cmd and the four menu messages were found and are not empty (a check on nothing would pass)",
       len(ide) > 30000 and len(inm) > 3000 and len(memo) > 15000 and len(pairs) >= 22 and len(rc) > 2000 and all(len(v) >= 2 for v in menus.values())
       and all(raw[k].strip() for k in raw), "%d %d %d %d %d" % (len(ide), len(inm), len(memo), len(pairs), len(rc)))
    ck("IK1", "F2 and F11 have no case in do.key (F2 is the debugger's abort; find in the records is a menu entry with no key)",
       "f2" not in bound and "f11" not in bound and "case edata = 'f2'" not in dk and "case edata = 'f11'" not in dk, repr(sorted(bound)))
    wrong = {k: bound.get(k) for k, w in KEYMAP.items() if bound.get(k) != w}
    extra = sorted(set(bound) - set(KEYMAP) - {"guardquit", "mouse"})
    ck("IK2", "do.key binds exactly the settled keys, each once, to its command: Ctrl-S save, F5 run, F7 debug, F8 compile, F9 catalog (compile and catalogue), F6 nextpane, Shift-F6 prevpane, "
       "Ctrl-PgDn and Alt-PgDn nexttab, Ctrl-PgUp and Alt-PgUp prevtab, Ctrl-W close, Ctrl-N new, Ctrl-O open, and the unchanged F4 nexterr, Ctrl-L goto, Ctrl-E sed, Ctrl-R replace, F12 fields, "
       "F10 menu, Ctrl-Q quit, F1 help; F3 is not among them (IK21)",
       not wrong and not extra and len(bound) == len(pairs) - 0 and len([k for k, _ in pairs]) == len(set(k for k, _ in pairs)), "wrong %r extra %r" % (wrong, extra))
    run_cases = set(w for heads in re.findall(r"case ((?:cmd = '[a-z.0-9]+'(?: or )?)+)", rc) for w in re.findall(r"cmd = '([a-z.0-9]+)'", heads))   # `case cmd = 'nextpane' or cmd = 'prevpane'` holds both
    menu_cmds = {c for es in menus.values() for _, _, c in es}
    ck("IK3", "every command word do.key sets and every command word a menu carries has a case in run.cmd",
       set(bound.values()) <= run_cases and menu_cmds <= run_cases, repr(sorted((set(bound.values()) | menu_cmds) - run_cases)))
    bad = []
    for n, es in menus.items():
        for lab, shown, cmd in es:
            if shown and bound.get(keyname(shown)) != cmd:
                bad.append((n, lab, shown, cmd, bound.get(keyname(shown))))
    ck("IK4", "every key a menu shows (messages 12230-12233) is bound in do.key to the SAME command word the entry carries",
       not bad and sum(1 for es in menus.values() for e in es if e[1]) >= 14, repr(bad[:4]))
    unkeyed = sorted(c for es in menus.values() for _, s, c in es if not s)
    ck("IK4b", "the entries with no key are exactly Save as, Write a copy, Find in the records, Files and records (the tree: F3 is the editor's find next) and Open the include, "
       "and no key in do.key leads to them",
       unkeyed == UNKEYED and not (set(UNKEYED) & set(bound.values())), repr(unkeyed))
    ck("IK5", "the menus list their entries in the settled order: File (New, Open, Save, Save as, Write a copy, Close, Quit), Go (Go to line, Next error, Next tab, Previous tab, Files and records, "
       "Next pane, Previous pane, Open the include, Edit in SED, Edit as fields), Search (Find in the records, Replace in the record, then the stage D commands at the end), Build (Compile, Compile and catalogue, Run, Debug, Run a command)",
       [c for _, _, c in menus[12230]] == FILE_MENU and [c for _, _, c in menus[12231]] == GO_MENU and [c for _, _, c in menus[12232]] == SEARCH_MENU
       and [c for _, _, c in menus[12233]] == BUILD_MENU, repr([[c for _, _, c in menus[n]] for n in menus]))
    miss = []
    for key, shown, word, kn in HELP:
        t = help_text(raw[key])
        if not re.search(re.escape(shown) + r"\s+[^\n]*" + re.escape(word), t, re.I) or (kn is not None and bound.get(kn) is None):
            miss.append((key, shown, word))
    allhelp = "\n".join(help_text(raw["m%d" % n]) for n in (12219, 12220, 12221))
    old = [w for w in ("F2", "F11") if re.search(r"\b" + w + r"\b", allhelp)]
    ck("IK6", "the help (12219-12221) names each settled key beside what it does: F6, Shift-F6 as the next / previous pane, Ctrl-PgDn, PgUp and Alt-PgDn, PgUp (a terminal may keep the Ctrl keys), "
       "F3, Shift-F3 as the next / previous find, Esc, F10 as the menus; and names neither F2 nor F11",
       not miss and not old and re.search(r"F6, Shift-F6\s+Next / previous pane", help_text(raw["m12219"])) is not None
       and re.search(r"F7\s+Debug", help_text(raw["m12220"])) is not None
       and re.search(r"Alt-PgDn, PgUp too: a terminal may keep the Ctrl keys", help_text(raw["m12219"])) is not None, repr((miss[:3], old)))
    ck("IK7", "the help names every key do.key binds: F1, F3 (the editor's), F4, F5, F6, F7, F8, F9, F10, F12, Shift-F6, Shift-F3, Alt-PgDn and each Ctrl key of the map are all in it",
       all(re.search(r"\b" + k.upper() + r"\b", allhelp) for k in ("f1", "f3", "f4", "f5", "f6", "f7", "f8", "f9", "f10", "f12"))
       and all(w in allhelp for w in ("Shift-F6", "Shift-F3", "Alt-PgDn"))
       and all(("Ctrl-" + c) in allhelp for c in ("S", "N", "O", "W", "L", "E", "R", "Q", "PgDn")), "")
    ck("IK8", "the menu is the help's key table made of the same words: the entry for each of F5, F7, F8, F9 shows that key (the menu was where F7 compile and F8 compile-and-catalogue stood)",
       [(c, s) for _, s, c in menus[12233]] == [("compile", "F8"), ("catalog", "Shift-F9"), ("run", "F9"), ("debug", "F7"), ("xeq", ""), ("format", ""), ("debug1", ""), ("bptoggle", "Shift-F7"), ("bpclear", ""), ("runargs", ""), ("xeqterm", "")], repr(menus[12233]))      # (xeq, format, 29 Oct 26: no key; the last three, 2 Nov 26, S.98 H2)
    cat = case_block(rc, "case cmd = 'catalog'")
    ck("IK9", "F9 builds: 'catalog' compiles first (no debugging option), runs CATALOG only when the compile was good, and only then asks catalog.verified; 'compile' catalogues nothing",
       re.search(r"c\.opt = ''\s*\n\s*gosub do\.compile\s*\n\s*if c\.ok then\s*\n.*\n\s*execute 'catalog ' : qp\.f : ' ' : qp\.i capturing co\s*\n\s*gosub catalog\.verified", cat) is not None
       and "execute" not in case_block(rc, "case cmd = 'compile'") and "catalog" not in case_block(rc, "case cmd = 'compile'").replace("case cmd = 'compile'", ""), cat[:200])
    cv = block(ide, "catalog.verified")
    ck("IK10", "'Catalogued file id' (12212) is the status only when CATALOG's own success line (messages 3029 to 3031) was read in its answer; otherwise the answer is shown in a box (12979)",
       raw["m12212"].startswith("Cataloged ") and re.search(r"for cv\.m = 3029 to 3031\s*\n\s*if index\(upcase\(co\), upcase\(sysmsg\(cv\.m, c\.id\)\), 1\) then cv\.ok = @true", cv) is not None
       and re.search(r"if cv\.ok then\s*\n\s*msg = sysmsg\(12212, c\.file, c\.id\)\s*\n\s*return\s*\n\s*end", cv) is not None and "sysmsg(12979," in cv and "gosub refuse.box" in cv, cv[:200])
    cc = block(ide, "close.current")
    ck("IK11", "Ctrl-W closes the record: a changed one asks Save / Discard / Cancel (12209), Cancel and a refused save leave it open, and the last tab closed makes an Untitled buffer (the editor is never empty)",
       "screen msgbox sysmsg(12209, bf.name, bf.id) buttons 'Save,Discard,Cancel' default 1 returning b else b = 3" in cc
       and re.search(r"case 1\s*\n\s*return\s*\n\s*end case", cc) is not None and re.search(r"gosub save\.one\s*\n\s*if not\(sv\.ok\) then return", cc) is not None
       and "if nbuf = 0 then" in cc and "gosub add.untitled" in cc and "write" not in cc, cc[:200])
    nmcase = case_block(rc, "case cmd = 'new'")
    ck("IK12", "Ctrl-N, Ctrl-O: 'new' and 'open' go to do.new and do.open, which ask the name form (ide_name), 'open' in the mode 'open' that needs an existing record",
       "gosub do.new" in nmcase and "gosub do.open" in case_block(rc, "case cmd = 'open'") and "case mode = 'open'" in inm and "read x from fv, ii" in inm, "")
    nm_d = block(inm, "try.accept")
    i_dollar = nm_d.find("case ff[1, 1] = '$'")
    i_open = nm_d.find("case mode = 'open'", i_dollar)      # 30 Oct 26 (E2): the path: branch above has a "case mode = 'open'" of its own; the one that opens a record comes after the dollar test
    ck("IK13", "the name form refuses a file whose name starts with a dollar sign (12688) BEFORE it opens anything, and names the file in the message",
       0 < i_dollar < i_open and re.search(r"case ff\[1, 1\] = '\$'\s*\n\s*msg = sysmsg\(12688, ff\)", nm_d) is not None and "%1" in raw["m12688"] and "dollar sign" in raw["m12688"], "")
    bf = block(ide, "build.files")
    ck("IK14", "the tree lists only files of records and leaves out the names that start with a dollar sign ($acc, $hold, $map, $release): the VOC walk tests the first character",
       re.search(r"if \(t1 = 'F' or t1\[1, 5\] = 'FILE '\) and ids<i>\[1, 1\] # '\$' then fl<-1> = ids<i>", bf) is not None, bf[:120])
    pk = re.search(r"mw\{'passkeys'\} = (\(if alone then '' else 'ctrl-e' : @vm\) : '[^']*'(?: : @vm : '[^']*')*)", ide)
    ck("IK15", "the editor passes exactly Ctrl-E (SED), Ctrl-T (the theme) and Ctrl-K (the keys) to the IDE (S.179, 8 Nov 26) and keeps all the memo's other keys, F3 and Shift-F3 among them; "
       "the first buffer of a bare IDE is an untitled one",
       pk is not None and pk.group(1) == "(if alone then '' else 'ctrl-e' : @vm) : 'ctrl-t' : @vm : 'ctrl-k'" and "gosub add.untitled" in ide[: ide.find("do.key:")], pk.group(1) if pk else "no passkeys line")
    # ---- the memo -------------------------------------------------------------------------------------------------------------------------------------------------
    ck("IK16", "the memo: Ctrl-A selects ALL (the mark at the start, the cursor at the end of the last line), it is not the start of the row (Home is)",
       re.search(r"case key = 'ctrl-a'\s*\n\s*my = 1 ; mx = 1\s*\n\s*cy = n\s*\n\s*cx = len\(lines<n>\) \+ 1", case_block(memo, "case key = 'ctrl-a'")) is not None
       and "case key = 'home'" in memo and "case key = 'ctrl-a' or" not in memo and "or key = 'ctrl-a'" not in memo, "")
    ck("IK17", "the memo: Ctrl-C copies and Ctrl-O is no copy alias; Ctrl-O and Ctrl-N are no key of the memo at all (they are Open and New in the programs that have them)",
       "case key = 'ctrl-c'" in memo and "'ctrl-o'" not in memo and "'ctrl-n'" not in memo, "")
    ck("IK18", "the memo: F3 is find next (it calls find.next), Shift-F3 is find previous (it calls find.prev), Ctrl-F / Ctrl-B ask the question",
       re.search(r"case key = 'f3'\s*\n\s*gosub find\.next", memo) is not None and re.search(r"case key = 'shift-f3'\s*\n\s*gosub find\.prev", memo) is not None
       and "case key = 'ctrl-t' or key = 'ctrl-f'" in memo and "case key = 'ctrl-b'" in memo, "")
    cd = case_block(memo, "case key = 'ctrl-d'")
    ck("IK19", "the memo: Ctrl-D DUPLICATES the line (kind 'dup': an undo step, the copy inserted under the line, the cursor on it) and deletes or joins nothing - Del joins",
       "kind = 'dup'" in cd and "gosub snap.push" in cd and "ins lines<cy> before lines<cy + 1>" in cd and "cy += 1" in cd and "del " not in cd
       and "lines<cy> = ln : lines<cy + 1>" in case_block(memo, "case key = 'del'"), cd[:150])
    ck_ = case_block(memo, "case key = 'ctrl-k' or key = 'alt-k'")      # 8 Nov 26 (S.179): Alt-K as well, for the IDE, which keeps Ctrl-K (the keys)
    ck("IK20", "the memo: Ctrl-K CUTS THE WHOLE LINE into the clipboard (kind 'cutline': an undo step, the line and its end mark in clip.text, the line removed, the cursor at the start of the row below), "
       "an only line is emptied and not deleted",
       "kind = 'cutline'" in ck_ and "gosub snap.push" in ck_ and "clip.text = lines<cy> : @fm" in ck_ and "clip.has = 1" in ck_ and "del lines<cy>" in ck_ and "lines<cy> = ''" in ck_ and "cx = 1" in ck_,
       ck_[:150])
    # ---- F3 is the editor's, the tree has panes / the Go menu / the mouse, the Alt forms of the tab keys, SED's buffer keys -------------------------------------------------
    ck("IK21", "F3 and Shift-F3 have no case in do.key (the owner's D31: they are the text area's find next / previous); the tree is a command word run.cmd still has, reached from the Go menu entry "
       "'Files and records' (no key), the panes' ring and the mouse",
       "f3" not in bound and "shift-f3" not in bound and "case edata = 'f3'" not in dk and "case edata = 'shift-f3'" not in dk and "case cmd = 'tree'" in rc
       and ("Files and records", "", "tree") in [(re.sub(r"&", "", a), b, c) for a, b, c in menus[12231]], repr(sorted(bound)))
    bad_f3 = [ln for ln in allhelp.split("\n") if re.search(r"\bF3\b", ln) and re.search(r"tree|Files and records", ln, re.I)]
    ck("IK22", "no line of the help (12219-12221) names F3 beside the tree or Files and records",
       not bad_f3 and "F3, Shift-F3" in allhelp, repr(bad_f3[:2]))
    # ---- 28 Oct 26, stage B: Open the include --------------------------------------------------------------------------------------------------------------------
    inc = [(re.sub(r"&", "", a), b, c) for a, b, c in menus[12231] if c == "include"]
    di = block(ide, "do.include")
    ck("IK24", "Go / Open the include: one entry with no key, command word 'include', run.cmd runs do.include for it, do.include reads the editor's line at the cursor, takes "
       "'$include' as its first word and opens the record through open.record; the help names it",
       inc == [("Open the include", "", "include")] and re.search(r"case cmd = 'include'\s*\n\s*gosub do\.include", rc) is not None
       and "mw{'cy'}" in di and "'$include'" in di and "gosub open.record" in di and "include" not in bound.values() and "Open the include" in allhelp, repr(inc))
    # ---- 28 Oct 26 (approved by the owner): Tab indents in the IDE's editor, an option of the memo that only the IDE sets ------------------------------------------
    hk = memo[memo.find("handle.key:"):]
    i_ro = hk.find("      case ro\n")
    i_tab = hk.find("      case key = 'tab' and ti > 0\n")
    i_btab = hk.find("      case key = 'btab' and ti > 0\n")
    ck("IK25", "the memo's Tab and Shift-Tab are its own keys ONLY with tabindent: ti is w{'tabindent'} + 0, the two cases test ti > 0 and come AFTER the readonly case (a viewer moves "
       "the focus as before), Tab runs indent.in and Shift-Tab indent.out, and no other case names tab or btab (without the option Tab is 'unhandled', a form's control key)",
       "ti = w{'tabindent'} + 0" in memo and 0 < i_ro < i_tab < i_btab
       and re.search(r"case key = 'tab' and ti > 0\s*\n\s*gosub indent\.in\b", hk) is not None and re.search(r"case key = 'btab' and ti > 0\s*\n\s*gosub indent\.out\b", hk) is not None
       and len(re.findall(r"case key = '(?:tab|btab)'\s*(?:\n|or\b)", hk)) == 0 and len(re.findall(r"'b?tab'", memo)) == 2, "%d %d %d" % (i_ro, i_tab, i_btab))
    ii = block(memo, "indent.in")
    io = block(memo, "indent.out")
    oc = block(memo, "outdent.count")
    ck("IK26", "indent.in is ONE undo step taken before the change (kind 'indent', snap.push), puts blanks in with space() and never a tab character, to the next stop (ti - mod(cx - 1, ti)) "
       "or the width before each selected line that holds something; indent.out takes out only blanks, back to the stop before, and makes no step when there is nothing to take out; "
       "neither kind joins a run of typing in snap.push",
       ordered(ii, "kind = 'indent'", "gosub snap.push", "if has.sel then", "gosub indent.lines", "space(ti) : lines<in.i>", "end else", "in.n = ti - mod(cx - 1, ti)", "space(in.n)")
       and "char(9)" not in ii + io + oc and "if lines<in.i> # '' then" in ii
       and ordered(io, "in.any = @false", "gosub outdent.count", "if not(in.any) then return", "kind = 'outdent'", "gosub snap.push", "lines<in.i> = in.ln[in.r + 1, len(in.ln)]")
       and ordered(oc, "in.ln[in.l + 1, 1] = ' '", "in.r = mod(in.l, ti)", "if in.r = 0 then in.r = ti", "if in.r > in.l then in.r = in.l")
       and "if ex = 1 and ey > sy then in.b = ey - 1" in block(memo, "indent.lines")
       and "if kind = k0 and (kind = 'type' or kind = 'bs' or kind = 'del') then return" in block(memo, "snap.push"), ii[:120])
    ti_sets = re.findall(r"\{'tabindent'\}\s*=\s*(\S+)", ide)
    ck("IK27", "the IDE sets the editor's tabindent to 3 (the codebase's width), once, where it sets the other options of the editor; the help says Tab, Shift-Tab indent and outdent "
       "in the editor and F6, Shift-F6 move between the panes",
       ti_sets == ["ed.tab", "ed.tab"] and ide.count("ed.tab = 3") == 1 and ordered(block(ide, "new.form"), "mw{'stay'} = 1", "mw{'tabindent'} = ed.tab", "mw{'softcur'} = 1")
       and re.search(r"Tab, Shift-Tab\s+In the editor: indent, outdent", help_text(raw["m12219"])) is not None
       and not re.search(r"Tab, Shift-Tab\s+Next / previous pane", help_text(raw["m12219"])), repr(ti_sets))
    # 3 Nov 26 (S.75 DV10): Tools > a development page, through the terminal hand-over as Run does
    tools = menu_entries(raw["m15004"])
    dt = block(ide, "do.tool")
    seven = ["tool.files", "tool.dict", "tool.voc", "tool.query", "tool.bulk", "tool.catalog", "tool.test"]
    ck("IK28", "the Tools menu (15004) is put before AI and Help and offers exactly the seven development pages, none with a key; run.cmd sends a tool. word to do.tool and nothing else does; do.tool runs only "
       "those seven, keeping the editor's text, through leave.screen, an execute with trapping aborts and NO capturing, and retake.screen (Run's hand-over), never do.xeq",
       [c for _, _, c in tools] == seven and all(not s for _, s, _ in tools) and raw["m15004"].startswith("&Tools|")
       and ordered(ide, "for j = 12230 to 12235", "if j = 12235 and not(alone) then", "m = change(sysmsg(15004), '|', @vm)", "if j = 12235 and ai.on then")
       and "case cmd[1, 5] = 'tool.'\n         gosub do.tool" in rc and ide.count("gosub do.tool") == 1
       and ordered(dt, "tl.verb = cmd", "if index(' " + " ".join(seven) + " ', ' ' : tl.verb : ' ', 1) = 0 then return", "gosub stash.current", "gosub leave.screen",
                   "execute tl.verb trapping aborts", "gosub retake.screen")
       and "capturing" not in dt and "do.xeq" not in dt and dt.count("execute") == 1, repr(([c for _, _, c in tools], dt[:160])))
    return rows


def ordered(text, *parts):
    pos = -1
    for p in parts:
        i = text.find(p, pos + 1)
        if i < 0:
            return False
        pos = i
    return True


def sub(key, old, new):
    def f(raw):
        r = dict(raw)
        if old not in r[key]:
            raise KeyError("%s: %r is not in the file, so the mutant cannot be made" % (key, old[:70]))
        r[key] = r[key].replace(old, new, 1)
        return r
    return f


MUTANTS = [
    ("F2 saves again", "IK1", sub("ide", "      case edata = 'ctrl-s'\n         cmd = 'save'", "      case edata = 'f2'\n         cmd = 'save'\n      case edata = 'ctrl-s'\n         cmd = 'save'")),
    ("F11 finds in the records again", "IK1", sub("ide", "      case edata = 'f12'\n", "      case edata = 'f11'\n         cmd = 'find'\n      case edata = 'f12'\n")),
    ("F7 compiles (the old key)", "IK2", sub("ide", "case edata = 'f7'\n         cmd = 'debug'", "case edata = 'f7'\n         cmd = 'compile'")),
    ("F6 goes to the next tab (the old key)", "IK2", sub("ide", "case edata = 'f6'\n         cmd = 'nextpane'", "case edata = 'f6'\n         cmd = 'nexttab'")),
    ("Ctrl-W writes a copy (the old key)", "IK2", sub("ide", "case edata = 'ctrl-w'\n         cmd = 'close'", "case edata = 'ctrl-w'\n         cmd = 'writeas'")),
    ("Ctrl-PageDown is not the tab key", "IK2", sub("ide", "case edata = 'ctrl-pgdn'", "case edata = 'ctrl-pgdnx'")),
    ("a menu shows F8 for the catalogue entry", "IK4", sub("m12233", "Compile and cat&alog~Shift-F9~catalog", "Compile and cat&alog~F8~catalog")),
    ("a menu carries a word run.cmd does not know", "IK3", sub("m12230", "&New record~^N~new", "&New record~^N~newer")),
    ("run.cmd has no close", "IK3", sub("ide", "      case cmd = 'close'\n         gosub close.current\n", "      case cmd = 'closed'\n         gosub close.current\n")),
    ("Close record moves in the File menu", "IK5", sub("m12230", "|&Close record~^W~close|&Quit~^Q~quit", "|&Quit~^Q~quit|&Close record~^W~close")),
    ("a menu entry has a key the map lacks", "IK4", sub("m12232", "&Find in the records~~find", "&Find in the records~F11~find")),
    ("the help names F2", "IK6", sub("m12219", "Ctrl-S           Save", "F2, Ctrl-S       Save")),
    ("the help says F7 compiles", "IK6", sub("m12220", "F7              Debug", "F7              Compile")),
    ("the help says F6 is the tab key", "IK6", sub("m12219", "F6, Shift-F6     Next / previous pane", "F6, Shift-F6     Next / previous tab")),
    ("F9 stops compiling first", "IK9", sub("ide", "         c.opt = ''\n         gosub do.compile\n         if c.ok then\n            qp.file = c.file ; qp.id = c.id ; gosub quote.pair\n            execute 'catalog '",
                                            "         c.opt = ''\n         c.ok = @true\n         if c.ok then\n            qp.file = c.file ; qp.id = c.id ; gosub quote.pair\n            execute 'catalog '")),
    ("Catalogued is said whatever CATALOG answered", "IK10", sub("ide", "   if cv.ok then\n      msg = sysmsg(12212, c.file, c.id)", "   if 1 then\n      msg = sysmsg(12212, c.file, c.id)")),
    ("Close discards without asking", "IK11", sub("ide", "      screen msgbox sysmsg(12209, bf.name, bf.id) buttons 'Save,Discard,Cancel' default 1 returning b else b = 3\n      begin case\n         case b = 1\n            sv.i = cb",
                                                   "      b = 2\n      begin case\n         case b = 1\n            sv.i = cb")),
    ("the name form lets a dollar file through", "IK13", sub("ide_name", "case ff[1, 1] = '$'", "case ff[1, 1] = '%'")),
    ("the tree lists the dollar entries", "IK14", sub("ide", " and ids<i>[1, 1] # '$' then fl<-1>", " then fl<-1>")),
    ("the editor passes F3 to the IDE again", "IK15", sub("ide", "mw{'passkeys'} = (if alone then '' else 'ctrl-e' : @vm) : 'ctrl-t' : @vm : 'ctrl-k'", "mw{'passkeys'} = (if alone then '' else 'ctrl-e' : @vm) : 'ctrl-t' : @vm : 'ctrl-k' : @vm : 'f3'")),
    ("the editor passes nothing to the IDE", "IK15", sub("ide", "mw{'passkeys'} = (if alone then '' else 'ctrl-e' : @vm) : 'ctrl-t' : @vm : 'ctrl-k'", "mw{'passkeys'} = ''")),
    ("the editor keeps Ctrl-T for itself (S.179)", "IK15", sub("ide", "mw{'passkeys'} = (if alone then '' else 'ctrl-e' : @vm) : 'ctrl-t' : @vm : 'ctrl-k'", "mw{'passkeys'} = 'ctrl-e' : @vm : 'ctrl-k'")),
    ("Ctrl-A is the start of the row", "IK16", sub("memo", "         my = 1 ; mx = 1\n         cy = n\n         cx = len(lines<n>) + 1\n         want = cx", "         my = 0 ; mx = 0\n         cx = 1\n         want = cx")),
    ("Ctrl-O copies again", "IK17", sub("memo", "case key = 'ctrl-c'", "case key = 'ctrl-c' or key = 'ctrl-o'")),
    ("Ctrl-N finds the next again", "IK17", sub("memo", "case key = 'f3'", "case key = 'f3' or key = 'ctrl-n'")),
    ("F3 does not find next", "IK18", sub("memo", "case key = 'f3'                           ;* 28 Oct 26 (D31): find next is F3 (and Return in the find question); Ctrl-N is New in the programs that have one\n         gosub find.next",
                                         "case key = 'f3'\n         null")),
    ("Ctrl-D joins lines again", "IK19", sub("memo", "         ins lines<cy> before lines<cy + 1>\n         cy += 1", "         del lines<cy + 1>\n         cy += 1")),
    ("Ctrl-K cuts to the end of the row again", "IK20", sub("memo", "clip.text = lines<cy> : @fm", "clip.text = lines<cy>[cx, 99999]")),
]
# the sitting of 28 Oct 26 (F3 to the editor, F6 / Shift-F6 round the panes, the Alt forms of the tab keys): its mutants, first
M_F3 = len(MUTANTS)
MUTANTS += [
    ("F3 goes to the tree again", "IK21", sub("ide", "      case edata = 'f4'\n         cmd = 'nexterr'", "      case edata = 'f3'\n         cmd = 'tree'\n      case edata = 'f4'\n         cmd = 'nexterr'")),
    ("Shift-F3 goes to the IDE", "IK21", sub("ide", "      case edata = 'f4'\n         cmd = 'nexterr'", "      case edata = 'shift-f3'\n         cmd = 'nexterr'\n      case edata = 'f4'\n         cmd = 'nexterr'")),
    ("run.cmd has no tree", "IK21", sub("ide", "case cmd = 'tree'", "case cmd = 'treex'")),
    ("Shift-F6 is not bound", "IK2", sub("ide", "case edata = 'shift-f6'", "case edata = 'shift-f6x'")),
    ("Shift-F6 goes to the next pane", "IK2", sub("ide", "case edata = 'shift-f6'\n         cmd = 'prevpane'", "case edata = 'shift-f6'\n         cmd = 'nextpane'")),
    ("F6 goes to the previous pane", "IK2", sub("ide", "case edata = 'f6'\n         cmd = 'nextpane'", "case edata = 'f6'\n         cmd = 'prevpane'")),
    ("Alt-PageDown is not the tab key", "IK2", sub("ide", " or edata = 'alt-pgdn'", "")),
    ("Alt-PageUp goes to the next tab", "IK2", sub("ide", "case edata = 'ctrl-pgup' or edata = 'alt-pgup'\n         cmd = 'prevtab'", "case edata = 'ctrl-pgup' or edata = 'alt-pgup'\n         cmd = 'nexttab'")),
    ("the Go menu has no Previous pane", "IK5", sub("m12231", "|Previous p&ane~Shift-F6~prevpane", "")),
    ("the Go menu shows F6 for Previous pane", "IK4", sub("m12231", "Previous p&ane~Shift-F6~prevpane", "Previous p&ane~F6~prevpane")),
    ("the Go menu gives Files and records F3", "IK4", sub("m12231", "&Files and records~~tree", "&Files and records~F3~tree")),
    ("the Go menu drops Files and records", "IK5", sub("m12231", "|&Files and records~~tree", "")),
    ("the help names F3 as the tree", "IK22", sub("m12221", "Ctrl-Q           Quit", "Ctrl-Q           Quit   F3  The tree")),
    ("the help drops Shift-F6", "IK6", sub("m12219", "F6, Shift-F6     Next / previous pane", "F6               Next pane")),
    ("the help drops the Alt keys", "IK6", sub("m12219", " (Alt-PgDn, PgUp too: a terminal may keep the Ctrl keys for its own tabs)", "")),
    ("the help drops Shift-F3", "IK6", sub("m12221", "F3, Shift-F3  The next, the previous", "F3  The next")),
    ("the help calls Esc, F10 something else", "IK6", sub("m12221", "Esc, F10        The menus", "Esc, F10        The tree")),
    ("the memo has no Shift-F3", "IK18", sub("memo", "case key = 'shift-f3'", "case key = 'shift-f3x'")),
    ("Shift-F3 finds the next one", "IK18", sub("memo", "and Shift-F3 the one before\n         gosub find.prev", "and Shift-F3 the one before\n         gosub find.next")),
]
# 28 Oct 26, stage B: Open the include
M_INC = len(MUTANTS)
MUTANTS += [
    ("the Go menu has no Open the include", "IK5", sub("m12231", "|&Open the include~~include", "")),
    ("Open the include runs nothing", "IK24", sub("ide", "      case cmd = 'include'\n         gosub do.include", "      case cmd = 'include'\n         null")),
    ("Open the include is given F3", "IK4", sub("m12231", "&Open the include~~include", "&Open the include~F3~include")),
    ("do.include opens the record without open.record", "IK24", sub("ide", "   cur.code = 'R:' : or.file : ':' : or.id\n   gosub open.record\n   if nbuf > 0 then\n      ft.id = 'ed'\n      gosub focus.to\n      gosub redraw.tabs",
                                                                    "   cur.code = 'R:' : or.file : ':' : or.id\n   null\n   if nbuf > 0 then\n      ft.id = 'ed'\n      gosub focus.to\n      gosub redraw.tabs")),
    ("the help does not name Open the include", "IK24", sub("m12220", "Go, Open the include:", "Go, the include:")),
]
# 28 Oct 26: Tab indents in the IDE's editor (the memo's tabindent)
M_TAB = len(MUTANTS)
MUTANTS += [
    ("the memo indents without the option (every form loses Tab)", "IK25", sub("memo", "      case key = 'tab' and ti > 0\n", "      case key = 'tab'\n")),
    ("a read-only area indents", "IK25", sub("memo", "      case ro\n         ret = 'unhandled' : @fm : key\n      case key = 'tab' and ti > 0\n         gosub indent.in                ;* 28 Oct 26: an area with tabindent (the IDE); without it Tab is 'unhandled' below, as ever\n",
                                             "      case key = 'tab' and ti > 0\n         gosub indent.in                ;* 28 Oct 26: an area with tabindent (the IDE); without it Tab is 'unhandled' below, as ever\n      case ro\n         ret = 'unhandled' : @fm : key\n")),
    ("Shift-Tab indents", "IK25", sub("memo", "      case key = 'btab' and ti > 0\n         gosub indent.out", "      case key = 'btab' and ti > 0\n         gosub indent.in")),
    ("Tab puts a tab character in", "IK26", sub("memo", "      lines<cy> = ln[1, cx - 1] : space(in.n) : ln[cx, len(ln)]", "      lines<cy> = ln[1, cx - 1] : char(9) : ln[cx, len(ln)]")),
    ("Tab is no undo step", "IK26", sub("memo", "   kind = 'indent'\n   gosub snap.push\n", "   kind = 'indent'\n")),
    ("Tab goes the whole width whatever the column", "IK26", sub("memo", "      in.n = ti - mod(cx - 1, ti)", "      in.n = ti")),
    ("an empty selected line gets blanks", "IK26", sub("memo", "         if lines<in.i> # '' then\n            lines<in.i> = space(ti) : lines<in.i>", "         if 1 then\n            lines<in.i> = space(ti) : lines<in.i>")),
    ("Shift-Tab makes a step that changes nothing", "IK26", sub("memo", "   if not(in.any) then return\n", "")),
    ("Shift-Tab takes out the whole width, not back to the stop", "IK26", sub("memo", "   in.r = mod(in.l, ti)\n", "   in.r = ti\n")),
    ("a run of indents is one undo step", "IK26", sub("memo", "(kind = 'type' or kind = 'bs' or kind = 'del')", "(kind = 'type' or kind = 'bs' or kind = 'del' or kind = 'indent')")),
    ("the IDE does not set the option (Tab moves the focus again)", "IK27", sub("ide", "   mw{'tabindent'} = ed.tab", "   mw{'tabindent'} = 0")),
    ("the IDE's tab width starts at another number", "IK27", sub("ide", "   ed.tab = 3\n", "   ed.tab = 4\n")),
    ("the help still says Tab is the next pane", "IK27", sub("m12219", "Tab, Shift-Tab   In the editor: indent, outdent", "Tab, Shift-Tab   Next / previous pane; in the editor: indent, outdent")),
]
M_DV10 = len(MUTANTS)
MUTANTS += [
    ("a Tools entry runs another verb", "IK28", sub("m15004", "&Tests~~tool.test", "&Tests~~tool.test.all")),
    ("do.tool runs any tool. word", "IK28", sub("ide", "   if index(' tool.files tool.dict tool.voc tool.query tool.bulk tool.catalog tool.test ', ' ' : tl.verb : ' ', 1) = 0 then return\n", "")),
    ("do.tool captures the page's output (do.xeq's way)", "IK28", sub("ide", "   execute tl.verb trapping aborts\n", "   execute tl.verb trapping aborts capturing tl.out\n")),
    ("do.tool keeps the screen while the page runs", "IK28", sub("ide", "   gosub stash.current\n   gosub leave.screen\n   execute tl.verb", "   gosub stash.current\n   execute tl.verb")),
    ("do.tool loses the editor's text", "IK28", sub("ide", "   gosub stash.current\n   gosub leave.screen\n   execute tl.verb", "   gosub leave.screen\n   execute tl.verb")),
    ("the Tools menu is not on the bar", "IK28", sub("ide", "         m = change(sysmsg(15004), '|', @vm)", "         m = ''")),
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
    print("test-idekeys-units: tree %s" % os.path.dirname(GPL))
    if not raw["ide"] or not raw["memo"]:
        print("test-idekeys-units: CANNOT RUN - %s or %s is not there" % (FILES["ide"], FILES["memo"]))
        return 2
    rows = checks(raw)
    bad = report(rows)
    print("\ntest-idekeys-units: %d passed, %d failed" % (len(rows) - bad, bad))
    rc = 1 if bad else 0
    if "--selftest" in argv:
        rc = (selftest(raw) or rc)
    return rc


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
