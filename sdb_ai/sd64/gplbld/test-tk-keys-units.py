#!/usr/bin/env python3
"""test-tk-keys-units.py - the toolkit's action registry ($tk_keys, tk.h's key table) held as TEXT (S.88 phase 3.9, steps S0 to S2).

    python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/test-tk-keys-units.py [--s0] [--selftest [--from=N]]

WHAT THIS IS, AND WHAT IT IS NOT.  It reads the BASIC of the 24 programs that build a key table (`call $tk_keys('add', ...)`), parses all of their
rows, and holds the rules a hand edit breaks unnoticed: seven arguments at every call, no key bound to two actions in one pane, one label and one key
per action, quit on Ctrl-Q and help on F1, a handler in the page's source for every key it registers, the keys the plan reserves (F2, F6, F10, F11)
and the mnemonics of the IDE's menus.  Part B (below the marker lines in this file) holds the registry's own operations in `tk_keys` and `tk_fkeys`,
and the owner's answer 25 of 29 Oct 26: ***an action reachable through the registry (a menu entry, the palette, the key list) runs through the SAME
handler as its key*** - the registry holds no code path that runs an action; it returns the action's code and the page's own handler does the rest.

***IT RUNS NOTHING.***  It cannot say that a handler's own gate (K$PATH.OK, K$EDIT.OK, the administrator test) refuses anybody, that a menu bar is
drawn, or that a key press reaches the handler: those are the sandbox suites (`sandbox-tk-base.py` rows on tool_tktest).  A text check can only
say that there is exactly one place where an action's code is turned into work, and that the registry has no other.

--s0      run part A only (step S0 of the plan: the check alone, on a tree whose tk_keys has not changed).
--selftest breaks each rule in the way an edit plausibly would and requires a check to notice; a mutant nothing catches is a failure.
          --from=N runs the mutants from number N on (the first of part B is printed as M_P39B).

THE EXCEPTIONS LEDGER.  Each entry is a defect that is true of the tree today and is the Phase 5 work list.  An entry that stops being true makes
the check FAIL ("the ledger names X, which no longer fires: remove it"), so the ledger can only shrink by someone reading it.
"""

import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SDSYS = os.path.normpath(os.path.join(HERE, "..", "sdsys"))
GPL = os.path.join(SDSYS, "gpl.bp")
MSG = os.path.join(SDSYS, "messages")

# A program that builds a key table only to NAME the keys of its foot (the form of a dictionary item, 1 Nov 26): its keys are the library form's (Enter is the default button, Esc the cancel
# button, Tab the focus), it has no help and no quit of a page, so the page rules (handler, F1, Ctrl-Q) do not apply to it; it is still parsed and counted.
# $tk_aipage (S.97 stage 1, 1 Nov 26) is in the same list for another reason: it is not a page but adds ONE row, F6 for the action ai, to the table of the page that calls it (and the AI menu
# entry); the page's own source has the case, which test-aipage-units.py holds.
# $debug (S.98 H1, 1 Nov 26) is in the list as well: it builds a nine-row table (F1 F2 F3 F4 F5 F7 F8 ^F7 ^F8) only to NAME the keys of its foot; its own command loop acts on them (K$F1 ... ),
# and test-dbgdisplay-units.py holds that the table and the loop name the same keys.  It has no quit of a page and F2 is ABORT there, which the page rules (Ctrl-Q, F2 reserved) would refuse.
# $spview (S.99, 2 Nov 26) is in the list for the debugger's reason: its nine rows (PgDn PgUp Home End Left Right S X Q) only NAME the keys of its foot; its own command loop
# (map.keys and the case c = lines) acts on them, and test-spview-units.py V12 holds that the row and the loop name the same keys.  It is no page: Q quits after asking, as it always has.
FOOT_ONLY = ("dict_form", "tk_aipage", "debug", "spview")
EXPECT_PROGRAMS = 29          # - tool_viewers (S.187, 9 Nov 26: removed with the pdf verb); + ced_edit (S.181, 9 Nov 26: !CED()'s keys list); - tool_masters (S.96 M6, 2 Nov 26: the master-file copies are retired); + spview (S.99, 2 Nov 26); + tool_entries (S.96 M1a, 3 Nov 26); tool_jobs (S.102 stage 1, 2 Nov 26)
EXPECT_ADD_ROWS = 350         # 9 Nov 26 (S.184 stage 5): the IDE's Alt-R and Alt-P + 2.  9 Nov 26 (S.187): tool_viewers' 7 rows went with the page (the pdf verb is removed) - 7.  9 Nov 26 (S.186): '/' find on tool.accounts, tool.sessions, tool.jobs, tool.gates, my.menu and the filter's '/' on tool.audit + 6.  9 Nov 26 (S.184 stage 3): the IDE's Alt-= character code + 1.  9 Nov 26 (S.181): ced_edit's 14 rows (its keys list; F2 only when the AI is usable, so 13 in a session without it).  8 Nov 26 (S.179, the same keys on every page): debug's F9 run and F10 menu + 2; the IDE's Shift-F9 build, Ctrl-T theme and Ctrl-K keys + 3 (F5 is refresh, F9 run, Alt-G go to, the fields' type Alt-T); mymenu's F5 + 1; tool_keys' Ctrl-K + 1; tool_home's Ctrl-K row gone - 1 ($tk_std adds Ctrl-T and Ctrl-K on every page that calls it, and is not counted).  8 Nov 26 (S.176, F6 the box key of every page): $tk_aipage's F6 'box' row beside its menu-only Ask the AI row, and tool_dict's F6 row for Items and Indices, + 2; the pages' Tab rows became F6 rows, no count.  8 Nov 26 (S.171): tool_ai's M and K rows became the one S row (the setup dialog), - 1.  7 Nov 26 (S.160): tool_ai's T row (the standing text), + 1.  3 Nov 26 (S.149): tool_home's 'leave' on Ctrl-Q and its Ctrl-X sign out, + 2; earlier, 3 Nov 26, merge of tracks B, C and D: tool_entries' G and U rows and dict_form's F6 row + 3, tool_test's Tab row + 1, tool_query's Saved-view rows Enter and X - 2 ("Extend the picker"): 322 + 3 + 1 - 2.  2 Nov 26, S.106: tool_remote lost R and L (the recovery codes and the console code), 324 - 2.  Before that: 318 +tool_home's six (S.88 U9, 2 Nov 26: Backspace, Ctrl-T, Ctrl-W, /, Ctrl-R, F6 and Ctrl-K added, the F10 row gone, so that every menu entry has a key); 317 + mymenu's F1 row (S.88 U4, 2 Nov 26); 324 - tool_masters' 7 rows (S.96 M6, 2 Nov 26); 318 + tool_jobs' J, A, N, C, D and R rows (S.102 stage 4, 2 Nov 26); 309 + the nine foot rows of spview (S.99, 2 Nov 26); 308 +tool_remote's L row (S.101 stage D, 2 Nov 26, local branch s101-ab); 307 + tool_entries' B row (S.96 M5, 2 Nov 26); 306 + tool_entries' C row (S.96 M4, 2 Nov 26); 305 + tool_entries' D row (S.96 M3, 2 Nov 26); 303 + tool_entries' E and N rows (S.96 M2, 3 Nov 26); 302 + tool_entries' K row (S.96 M1b, 3 Nov 26); 294 + tool_entries' eight rows (S.96 M1a, 3 Nov 26); 287 + tool_jobs' seven rows (S.102 stage 1, 2 Nov 26); 286 + the IDE's Shift-F7 row (S.98 H2, 2 Nov 26); 277 + the nine foot rows of debug (S.98 H1, 1 Nov 26); 266 + the 4 foot rows of dict_form, 1 Nov 26, + tk_aipage's F6 row; + tool_remote's 6, O, R, F rows (S.95 stage 1b, 1 Nov 26); + tool_gates' A and N (all on, all off, 1 Nov 26)
# 10 Nov 26 Windows port (RELEASE_1.1 197): the pages Linux has that this tree does not carry yet, with their 'add' rows at Linux 7bc274b9 (90 in all, so
# 22 programs and 260 rows here, counted 10 Nov 26) - tool.accounts, tool.audit, tool.config and tool.jobs need a Windows design, tool.ai waits for the
# AI (RELEASE_1.1 173), tool.entries for run.in (RELEASE_1.1 201), tool.remote for remote administration (RELEASE_1.1 202).  A page named here counts
# again, and its ledger entries are asked for again, as soon as its program is in gpl.bp; the counts themselves stay exact.
NOT_CARRIED = {"tool_accounts": 10, "tool_ai": 13, "tool_audit": 11, "tool_config": 10, "tool_entries": 16, "tool_jobs": 14, "tool_remote": 16}
# earlier counts: (266 with the IDE's eight rows of the pane "fields", 31 Oct 26; 256 with tool_sessions' Ctrl-O row, 257 with tool_home's F1 row, 258 with tool_test's Ctrl-O row, 29 Oct 26) after the 30 Oct 26 page fan-out: the 232 rows of the tree before 29 Oct 26, tool_tktest's pilot, and the Esc, menu and bar rows the pages on $tk_menubar added
KNOWN_OPS_S0 = {"add", "name", "action"}

# an action that has two keys on purpose (the second is for a terminal that keeps the first for itself)
# 2 Nov 26 (S.88 U9): the home screen goes back one sub-menu page on Esc (a row only on a sub-menu page: on the top page Esc is the bar's) and on Backspace (off the key row)
TWO_KEYS = {("tool_home", "back"): {"esc", "bs"}}
RESERVED = ("f2", "f6", "f10", "f11", "shift-f10")
# the action a reserved key may stand for (plan 5.2 / K8: F2 find an action, F6 the next pane, F10 the menu is NOT a page key, F11 gone)
# 1 Nov 26 (the owner accepted Opus's review): F6 is the AI line on every page - "ai"; the IDE keeps F6 as its next pane until its panes are decided (S.99)
# 3 Nov 26 (S.88 K7/K8 built): F2 and Shift-F10 are answered by the bar itself ($tk_menubar: the finder and the context menu), so no page binds them (an F2 row of a page would win)
# 8 Nov 26 (S.176, the owner: "F6 for boxes is fine"): F6 is the box key of every page, the AI line one stop of its ring; a page's F6 row keeps the action id its Tab row had (pane,
#   switch, next: the AI is offered them by id), the library's and the IDE's is nextpane.  "ai" stays for the home screen until it takes the change.
RESERVED_OK = {"f6": {"nextpane", "pane", "switch", "next", "ai"}}
MYMENU_MOVED = ("f2", "f3", "f4", "f6")

LEDGER = {
    "reserved": {
        "tool_tktest:f11": "the throw-away test app's pick-a-file key; it goes with the app",
        "tool_tktest:f6": "the throw-away test app's table refresh; it goes with the app",
        "tool_tktest:f10": "the throw-away test app's multi-pick key; it goes with the app",
    },
    "mnemonic": {
    },
    "handler": {
        # 30 Oct 26: "ide:esc/menu" (the IDE's Esc is handled where the form is read, not in do.key) is gone from this ledger because the IDE's fields view (fields.run) now has the literal 'esc' in its
        #   source; the Esc that opens the menu bar is still the main loop's `case 1`, so the check passes by the fields view's word until somebody takes it out, when this entry comes back
        "tool_remote:2/": "tool_remote's digit keys 2 to 5 choose a pane by number (a computed test, not a literal case; 1 and 6 are its ends)",
        "tool_remote:3/": "(as 2)",
        "tool_remote:4/": "(as 2)",
        "tool_remote:5/": "(as 2; 1 Nov 26, S.95 stage 1b, the sixth view made 5 an inner key)",
    },
    "conflict": {
        "tool_home:ctrl-q": "3 Nov 26 (S.149): Ctrl-Q is 'prompt' (leave) in the branch for a screen typed at the prompt and 'sign out' in the other: make.keys registers ONE of the two, never both",
    },
    "quitkey": {
        "tool_home:ctrl-q is signout": "the home screen leaves by signing out; Ctrl-Q is its quit",
        "tool_home:ctrl-q is leave": "3 Nov 26 (S.149): a screen typed at the prompt is a visit; Ctrl-Q is its quit and goes back to the prompt",
        "tool_home:has no quit": "(as above)",
    },
    "helpkey": {
        "tool_keys:has no help": "tool.keys is exempt (owner answer 18: it is the page that shows keys)",
    },
    "twokeys": {
        "tool_query:option": "an option list chooses with Enter or the space bar (the table of two-key actions)",
        "tool_audit:filter": "9 Nov 26 (S.186): F, and '/', the find key of every page (the filter form's last field is text anywhere); '/' is not on the key row",
    },
}

IDE_MENU_MESSAGES = (12230, 12231, 12232, 12233, 12234, 12235, 12659, 15004, 15019)      # 15004: the Tools menu (S.75 DV10, 3 Nov 26); 15019 the Edit menu (S.180, 8 Nov 26)


# ---------------------------------------------------------------------------------------------------------------------- reading

def strip_bas(src):
    out = []
    for line in src.split("\n"):
        s = line.lstrip()
        if s.startswith("*") or s.startswith("!"):
            out.append("")
            continue
        cut = cut_comment(line)
        out.append(line if cut < 0 else line[:cut])
    return "\n".join(out)


# What the BUSY expression of each page with an Esc case of its own must hold (the Opus review of 29 Oct 26, finding 2: a regex on "not the literal 0" passed the pre-fix tool_dict and
# tool_query, whose busy was a variable that was 0 in the pane with its own Esc).  A page with an Esc case that is not listed here fails until its panes have been read.
ESC_LEDGER = {
    "tool_dict": "pi = 3",                 # the Indices pane goes back to the items; the Files and Items panes have a name filter
    "tool_query": "cur.pane = 'File'",     # the file filter belongs to the File pane alone
    "tool_test": "filt #", "tool_config": "view # 1", "tool_files": "filt #", "tool_audit": "flt #", "tool_catalog": "filt #",
    "tool_remote": "view # 1", "tool_gates": "flt #", "tool_voc": "filt #", "tool_entries": "filt #",
    "tool_sessions": "outopen", "tool_jobs": "outopen",     # the output pane, passed as BUSY itself (9 Nov 26, S.187: tool_viewers left the ledger with the pdf verb)
}


def esc_bar_ok(prog, body):
    """the bar takes Esc itself ($tk_menubar 'key': the Esc rule) and the page can say when its own state wants Esc first.  A page whose source has an Esc case of its own must pass the
    bar a BUSY that is not the literal 0 AND hold what ESC_LEDGER says its busy must hold"""
    if "$tk_menubar('key'" not in body:
        return False
    if not re.search(r"\bcase\b[^\n]*'esc'", body):
        return True
    if re.search(r"\$tk_menubar\('key',[^\n]*,\s*nm,\s*(?!0\s*,)[\w.]+\s*,\s*\w+\)", body) is None:
        return False
    need = ESC_LEDGER.get(prog)
    if need is None:
        return False
    if need == "outopen":
        return re.search(r"\$tk_menubar\('key',[^\n]*,\s*nm,\s*outopen\s*,", body) is not None
    return any(l.strip().startswith("busy = ") and need in l for l in body.split("\n"))


def cut_comment(line):
    """the index of a ';*' that is outside quotes, or -1"""
    q = ""
    for i, ch in enumerate(line):
        if q:
            if ch == q:
                q = ""
        elif ch in "'\"":
            q = ch
        elif ch == ";" and line[i + 1:i + 2] == "*":
            return i
    return -1


def load():
    raw = {}
    for f in sorted(os.listdir(GPL)):
        p = os.path.join(GPL, f)
        if os.path.isfile(p):
            with open(p, "r", encoding="latin-1") as fh:
                raw[f] = fh.read()
    for n in IDE_MENU_MESSAGES:
        with open(os.path.join(MSG, str(n)), "r", encoding="latin-1") as fh:
            raw["msg:%d" % n] = fh.read()
    for n in range(12191, 12195):
        p = os.path.join(MSG, str(n))
        if os.path.exists(p):
            with open(p, "r", encoding="latin-1") as fh:
                raw["msg:%d" % n] = fh.read()
    return raw


def split_top(s, sep):
    """split on sep outside quotes and brackets"""
    parts, depth, q, cur = [], 0, "", ""
    for ch in s:
        if q:
            cur += ch
            if ch == q:
                q = ""
        elif ch in "'\"":
            q = ch
            cur += ch
        elif ch in "([" or (sep == "," and ch == "<"):
            depth += 1
            cur += ch
        elif ch in ")]" or (sep == "," and ch == ">"):
            depth -= 1
            cur += ch
        elif ch == sep and depth == 0:
            parts.append(cur)
            cur = ""
        else:
            cur += ch
    parts.append(cur)
    return [p.strip() for p in parts]


CALL = re.compile(r"call \$tk_keys\((.*)\)\s*$")


def calls_in(code):
    """[(line number, op, [args], text)] for every `call $tk_keys(` of a stripped program"""
    out = []
    for no, line in enumerate(code.split("\n"), 1):
        m = CALL.search(line)
        if m and "call $tk_keys(" in line:
            args = split_top(m.group(1), ",")
            out.append((no, args[0].strip("'") if args else "", args, line))
    return out


def literal(arg):
    """('lit', text) for a quoted string or a ':' chain of quoted strings and @sm / @fm / @vm; ('var', name) for a name; ('expr', text) otherwise"""
    arg = arg.strip()
    parts = split_top(arg, ":")
    text = ""
    for p in parts:
        if len(p) >= 2 and p[0] == p[-1] and p[0] in "'\"":
            text += p[1:-1]
        elif p in ("@sm", "@fm", "@vm"):
            text += "|"
        else:
            if re.fullmatch(r"[A-Za-z][A-Za-z0-9.]*", arg):
                return ("var", arg)
            return ("expr", arg)
    return ("lit", text)


def rows_of(raw):
    """every 'add' row: dict(prog, line, key, label, act, panes (frozenset, empty = every pane), on ('on', 'off', 'cond'), problems)"""
    rows = []
    for prog in sorted(raw):
        if prog.startswith("msg:") or prog == "tk_std":      # 8 Nov 26 (S.179): the shared rows (ctrl-t theme, ctrl-k keys) are added by every page's own call; test-tkstd-units.py holds them
            continue
        code = strip_bas(raw[prog])
        for no, op, args, line in calls_in(code):
            if op != "add":
                continue
            r = {"prog": prog, "line": no, "bad": [], "nargs": len(args), "args": args}
            if len(args) == 7:
                kind = {}
                for name, i in (("key", 2), ("label", 3), ("act", 4)):
                    k, v = literal(args[i])
                    if k != "lit":
                        r["bad"].append("%s is %s, not a quoted text" % (name, k))
                    r[name] = v
                k, v = literal(args[5])
                if k == "var":
                    m = None
                    for mm in re.finditer(r"^\s*%s\s*=\s*(.*)$" % re.escape(v), code, re.M):
                        m = mm
                    if m is None:
                        r["bad"].append("panes variable %s is not assigned in the program" % v)
                        v = ""
                    else:
                        k2, v2 = literal(m.group(1))
                        if k2 != "lit":
                            r["bad"].append("panes variable %s is not a text" % v)
                            v2 = ""
                        v = v2
                elif k == "expr":
                    r["bad"].append("panes is an expression")
                    v = ""
                r["panes"] = frozenset(x for x in re.split(r"[|]", v) if x)
                on = args[6].strip()
                r["on"] = "off" if on == "0" else ("on" if on in ("1", "''") else "cond")
                if on.startswith("(if ") and on.endswith(")"):
                    r["on"] = "cond"
                elif r["on"] == "on" and on not in ("1", "''"):
                    r["bad"].append("on is %s" % on)
            rows.append(r)
    return rows


# ---------------------------------------------------------------------------------------------------------------------- part A

def run_a(raw, rows):
    """{check name: [problem strings]}"""
    res = {}
    progs = sorted({r["prog"] for r in rows})
    ops_ok = KNOWN_OPS_S0
    tk = strip_bas(raw.get("tk_keys", ""))
    implemented = set(re.findall(r"case op = '([a-z]+)'", tk))
    if not implemented:
        implemented = ops_ok
    res["parse"] = []
    absent = [p for p in NOT_CARRIED if p not in raw]          # 10 Nov 26 Windows port: Linux's counts less the pages not carried
    want_progs = EXPECT_PROGRAMS - len(absent)
    want_rows = EXPECT_ADD_ROWS - sum(NOT_CARRIED[p] for p in absent)
    if len(progs) != want_progs:
        res["parse"].append("%d programs build a key table, expected %d (%s)" % (len(progs), want_progs, " ".join(progs)))
    if len(rows) != want_rows:
        res["parse"].append("%d 'add' rows found, expected %d" % (len(rows), want_rows))
    for r in rows:
        if r["nargs"] != 7:
            res["parse"].append("%s:%d add has %d arguments" % (r["prog"], r["line"], r["nargs"]))
        for b in r["bad"]:
            res["parse"].append("%s:%d %s" % (r["prog"], r["line"], b))
    res["args"] = []
    for prog in sorted(raw):
        if prog.startswith("msg:"):
            continue
        for no, op, args, line in calls_in(strip_bas(raw[prog])):
            if len(args) != 7:
                res["args"].append("%s:%d $tk_keys has %d arguments, not 7" % (prog, no, len(args)))
            if prog == "tkkeys" and op == "op":
                continue                                    # S.130: the public wrapper !tkkeys passes its caller's op through to $tk_keys
            if op not in implemented:
                res["args"].append("%s:%d $tk_keys op '%s' is not one tk_keys implements" % (prog, no, op))
    good = [r for r in rows if r["nargs"] == 7 and not r["bad"]]
    # (key, pane) bound to two actions
    res["conflict"] = []
    byprog = {}
    for r in good:
        byprog.setdefault(r["prog"], []).append(r)
    for prog, rs in byprog.items():
        for i, a in enumerate(rs):
            for b in rs[i + 1:]:
                if a["key"] and a["key"] == b["key"] and a["act"] != b["act"] and "off" not in (a["on"], b["on"]):
                    if not a["panes"] or not b["panes"] or (a["panes"] & b["panes"]):
                        res["conflict"].append("%s:%s" % (prog, a["key"]))
    # one act, one label; one act, one key
    res["label"] = []
    res["twokeys"] = []
    for prog, rs in byprog.items():
        labels, keys = {}, {}
        for r in rs:
            labels.setdefault(r["act"], set()).add(r["label"])
            if r["key"]:
                keys.setdefault(r["act"], set()).add(r["key"])
        for act, ls in labels.items():
            if len(ls) > 1:
                res["label"].append("%s:%s has the labels %s" % (prog, act, sorted(ls)))
        for act, ks in keys.items():
            if len(ks) > 1 and ks != TWO_KEYS.get((prog, act)):
                res["twokeys"].append("%s:%s has the keys %s" % (prog, act, sorted(ks)))
    # quit is ctrl-q, help is f1
    res["quitkey"], res["helpkey"] = [], []
    for prog, rs in byprog.items():
        if prog in FOOT_ONLY:
            continue
        for r in rs:
            if r["act"] == "quit" and r["key"] != "ctrl-q":
                res["quitkey"].append("%s:quit is on %s" % (prog, r["key"]))
            if r["act"] == "help" and r["key"] != "f1":
                res["helpkey"].append("%s:help is on %s" % (prog, r["key"]))
            if r["key"] == "ctrl-q" and r["act"] != "quit":
                res["quitkey"].append("%s:ctrl-q is %s" % (prog, r["act"]))
            if r["key"] == "f1" and r["act"] != "help":
                res["helpkey"].append("%s:f1 is %s" % (prog, r["act"]))
        if not any(r["act"] == "quit" for r in rs):
            res["quitkey"].append("%s:has no quit" % prog)
        if not any(r["act"] == "help" for r in rs):
            res["helpkey"].append("%s:has no help" % prog)
    # a handler in the page's source for every registered key
    res["handler"] = []
    for prog, rs in byprog.items():
        if prog in FOOT_ONLY:
            continue
        body ="\n".join(l for l in strip_bas(raw[prog]).split("\n") if "$tk_keys('add'" not in l)
        for r in rs:
            if not r["key"] or r["on"] == "off":          # a menu-only action has no key; a row switched off needs no handler
                continue
            if r["key"] == "esc" and r["act"] == "menu" and "$tk_menubar('key'" in body:
                hit = esc_bar_ok(prog, body)           # the bar takes Esc itself ($tk_menubar 'key': the Esc rule); the page's own Esc case must NOT count as a handler of this row (it hid the faults of the fan-out)
            else:
                hit =(re.search(r"\bact\s*=\s*'%s'" % re.escape(r["act"]), body) is not None
                       or re.search(r"=\s*'%s'" % re.escape(r["key"]), body) is not None
                       or re.search(r"\bcase\b[^\n]*'%s'" % re.escape(r["key"]), body) is not None)
                if not hit and prog == "ced_edit":
                    # 9 Nov 26 (S.181): !CED()'s host takes the shared keys itself and hands every other key to the engine, whose key handler acts on it
                    hit = re.search(r"\bc\.key\s*=\s*'%s'" % re.escape(r["key"]), strip_bas(raw["ced_core"])) is not None
                if not hit and prog == "ide" and r["panes"] == frozenset(["fields"]):
                    # 31 Oct 26 (S.86 stage 4): a key of the IDE's pane "fields" is handed to the engine, whose key handler is the one that acts on it
                    hit = re.search(r"\bc\.key\s*=\s*'%s'" % re.escape(r["key"]), strip_bas(raw["ced_core"])) is not None
            if not hit:
                res["handler"].append("%s:%s/%s" % (prog, r["key"], r["act"]))
    # reserved keys
    res["reserved"] = []
    for prog, rs in byprog.items():
        for r in rs:
            if r["key"] in RESERVED and r["act"] not in RESERVED_OK.get(r["key"], set()) and prog != "debug" and not (prog == "ced_edit" and r["key"] == "f2"):     # the debugger's F2 is ABORT, its own key since 2004 (S.98 H1: the foot names it); !CED()'s F2 is its AI menu (24 Oct 26), and it has no bar whose finder F2 would be
                res["reserved"].append("%s:%s" % (prog, r["key"]))
            if prog == "mymenu" and r["key"] in MYMENU_MOVED:      # owner answer 20: mymenu's own keys give way to Ctrl-N, Del and u / d in Phase 5
                res["reserved"].append("%s:%s" % (prog, r["key"]))
    res["reserved"] = sorted(set(res["reserved"]))
    # the IDE's menus: one & in every entry, the mnemonics of a menu and of the titles all different
    res["mnemonic"] = []
    titles = {}
    for n in IDE_MENU_MESSAGES:
        text = raw.get("msg:%d" % n, "").rstrip("\n")
        items = text.split("|")
        title = items[0]
        if title.count("&") != 1:
            res["mnemonic"].append("%d:%s:title has %d marks" % (n, title, title.count("&")))
            continue
        t = re.search(r"&(.)", title).group(1).lower()
        if t in titles:
            res["mnemonic"].append("%d:%s:%s title letter %s is also %s's" % (n, title.replace("&", "").lower(), t, t, titles[t]))
        titles[t] = title.replace("&", "")
        seen = {}
        for it in items[1:]:
            label = it.split("~")[0]
            if label.count("&") != 1:
                res["mnemonic"].append("%d:%s:entry '%s' has %d marks" % (n, title.replace("&", "").lower(), label, label.count("&")))
                continue
            c = re.search(r"&(.)", label).group(1).lower()
            if c in seen:
                res["mnemonic"].append("%d:%s:%s" % (n, title.replace("&", "").lower(), c))
            seen[c] = label
    return res


def judge(res, ledger_on=True):
    """[(name, passed, detail)] - a problem in the ledger is allowed, a ledger entry that no longer fires is a failure"""
    out = []
    for name in sorted(res):
        probs = res[name]
        led = LEDGER.get(name, {}) if ledger_on else {}
        new = [p for p in probs if not any(p.startswith(k) for k in led)]
        # 10 Nov 26 Windows port: an entry of a page in NOT_CARRIED whose program is not in gpl.bp cannot fire, and is not stale until the page comes
        stale = [k for k in led if not any(p.startswith(k) for p in probs)
                 and not (k.split(":")[0] in NOT_CARRIED and not os.path.exists(os.path.join(GPL, k.split(":")[0])))]
        detail = []
        if new:
            detail.append("NEW: " + "; ".join(new[:6]) + (" ..." if len(new) > 6 else ""))
        if stale:
            detail.append("the ledger names %s, which no longer fires: remove it" % ", ".join(stale))
        out.append((name, not detail, " | ".join(detail)))
    return out


A_TEXT = {
    "parse": "all 232 'add' rows of the 24 programs parse (key, label and action quoted, panes a text or a variable assigned in the program, on a number or an (if) expression)",
    "args": "every $tk_keys call has seven arguments and an op tk_keys implements",
    "conflict": "no key is bound to two actions in one pane (a null pane list overlaps every pane; a row switched off is out)",
    "label": "one action has one label in a page",
    "twokeys": "one action has one key in a page, except the table of two-key actions",
    "quitkey": "quit is Ctrl-Q and nothing else is, in every page",
    "helpkey": "help is F1 and nothing else is, in every page",
    "handler": "every key a page registers is acted on in that page's source (an act = 'x' case or the key's literal in a case)",
    "reserved": "the keys the plan reserves (F2 and Shift-F10, the bar's finder and context menu; F6 next pane or the AI line; F10; F11) are bound by no page except as allowed - the rest is the ledger",
    "mnemonic": "the IDE's menus: one & in every entry, no letter twice in a menu or among the titles - the rest is the ledger",
}


# ---------------------------------------------------------------------------------------------------------------------- part B
# ---- PART B BEGINS (the registry's operations, fkeys, the messages, and the owner's answer 25) ----
def norm(text):
    return re.sub(r"\s+", " ", text)


REGISTRY_OPS = {"add", "name", "action", "menu", "why", "menus", "keyof", "keylist", "ai", "aiacts"}      # 'ai' and 'aiacts': S.97 stage 1, an action offered to the AI and what is offered (both only list)
# what a program that only lists and names actions must never contain: it would be a second way to run one
NO_RUN_WORDS = ("execute", "perform", "chain", "screen", "display", "print", "crt", "open", "openseq", "write", "writeseq", "writev", "delete", "kernel(", "@sentence",
                "stop", "abort", "call $", "call(", "input", "read")


def run_b(raw):
    res = {}
    tkh = norm(strip_bas(raw.get("tk.h", "")))
    tk = norm(strip_bas(raw.get("tk_keys", "")))
    fk = norm(strip_bas(raw.get("tk_fkeys", "")))
    app = strip_bas(raw.get("tool_tktest", ""))
    appn = norm(app)
    # the table's values: the first five did not move
    want = [("KEY", 1), ("LABEL", 2), ("ACT", 3), ("PANES", 4), ("ON", 5), ("MENU", 6), ("ENTRY", 7), ("WHY", 8), ("ROW", 9), ("AI", 10)]
    res["tablevalues"] = ["TK.K.%s is not %d" % (n, v) for n, v in want if re.search(r"\$define TK\.K\.%s +%d\b" % (n, v), tkh) is None]
    res["tablevalues"] += ["TK.K.%s is defined more than once" % n for n, v in want if len(re.findall(r"\$define TK\.K\.%s\b" % n, tkh)) != 1]
    # the subroutine: seven arguments, the ops, the 'add' line as the pages have always had it
    res["ops"] = []
    if "subroutine tk_keys(op, keys, a, b, c, d, e)" not in tk:
        res["ops"].append("tk_keys does not take seven arguments (op, keys, a, b, c, d, e)")
    got = set(re.findall(r"case op = '([a-z]+)'", tk))
    if got != REGISTRY_OPS:
        res["ops"].append("tk_keys implements %s, the registry has %s" % (sorted(got), sorted(REGISTRY_OPS)))
    if "case op = 'add' keys<-1> = a : @vm : b : @vm : c : @vm : d : @vm : e" not in tk:
        res["ops"].append("'add' no longer writes the five values of the page tables")
    # action: an empty key matches nothing, a switched off action or one with a reason is not returned
    res["action"] = []
    m = re.search(r"case op = 'action' (.*?) case op = 'menu'", tk)
    ab = m.group(1) if m else ""
    for what, text in (("the empty-key guard (a # '')", "if a # '' and keys<i, TK.K.KEY> = a"), ("the ON test", "keys<i, TK.K.ON> # '0'"),
                       ("the WHY skip", "keys<i, TK.K.WHY> = '' then"), ("the pane test", "index(@sm : panes : @sm, @sm : pane : @sm, 1)")):
        if text not in ab:
            res["action"].append("'action' lacks " + what)
    # why: takes the action out of use AND states the reason; gives back only an action that had one
    res["why"] = []
    m = re.search(r"case op = 'why' (.*?) case op = 'menus'", tk)
    wb = m.group(1) if m else ""
    if not re.search(r"if b # '' then keys<i, TK\.K\.ON> = 0 keys<i, TK\.K\.WHY> = b end else if keys<i, TK\.K\.WHY> # '' then keys<i, TK\.K\.WHY> = '' keys<i, TK\.K\.ON> = ''", wb):
        res["why"].append("'why' does not set ON 0 with the reason, or gives back an action that had none")
    # menus: the flag D, the shown key derived, the entries from the table
    res["menus"] = []
    m = re.search(r"case op = 'menus' (.*?) case op = 'keyof'", tk)
    mb = m.group(1) if m else ""
    m = re.search(r" act\.state: (.*?) return key\.name:", tk)
    st = m.group(1) if m else ""
    for what, text in (("the flag D from the action's state", "fl = (if ia then '' else 'D')"), ("the shown key derived (ik)", "ent = keys<i, TK.K.ENTRY> : @sm : ik : @sm : fa : @sm : fl"), ("the reason goes with the entry (S.133; the F2 finder shows subvalue 5)", "if iw # '' then ent := @sm : iw"),
                       ("one entry an action", "if index(seen, @fm : fa : @fm, 1) = 0 then"),
                       ("Quit held back and put last in its menu", "if fa = 'quit' then qent = ent else m<1, -1> = ent"), ("Quit put last", "if qent # '' then m<1, -1> = qent")):
        if text not in mb:
            res["menus"].append("'menus' lacks " + what)
    for what, text in (("enabled means ON # '0' and no reason", "if keys<j, TK.K.ON> # '0' and keys<j, TK.K.WHY> = '' then ia = 1"),
                       ("the pane scope", "if panes = '' or index(@sm : panes : @sm, @sm : pane : @sm, 1) then isc = 1")):
        if text not in st:
            res["menus"].append("act.state lacks " + what)
    # keyof returns the first ENABLED binding's key for the pane
    res["keyof"] = []
    m = re.search(r"case op = 'keyof' (.*?) case op = 'keylist'", tk)
    kb = m.group(1) if m else ""
    if "gosub act.state c = ikf" not in kb or "if ikf = '' then ikf = kj" not in st:
        res["keyof"].append("'keyof' does not return the first enabled binding's key")
    # the names
    res["name"] = []
    for what, text in (("PgUp", "kt = 'PgUp'"), ("PgDn", "kt = 'PgDn'"), ("Shift-", "pre = 'Shift-'"), ("Alt-", "pre = 'Alt-'"), ("^", "pre = '^'")):
        if text not in tk:
            res["name"].append("'name' lacks " + what)
    # the function-key row leaves out a row with no key and a row whose ROW is 0
    res["fkeys"] = []
    if "keys<i, TK.K.ROW> # '0'" not in fk:
        res["fkeys"].append("tk_fkeys does not skip ROW = 0")
    if "keys<i, TK.K.KEY> # ''" not in fk:
        res["fkeys"].append("tk_fkeys does not skip an empty key")
    # the messages 12191 to 12194
    res["messages"] = []
    for n in (12191, 12192, 12193, 12194):
        t = raw.get("msg:%d" % n)
        if t is None:
            res["messages"].append("message %d is missing" % n)
        elif not t.endswith("\n") or t.count("\n") != 1 or not t.strip():
            res["messages"].append("message %d is not one line" % n)
    if (raw.get("msg:12193") or "").count("%1") != 1:
        res["messages"].append("12193 must hold %1 once (the reason)")
    cited = {}
    for prog in raw:
        if not prog.startswith("msg:"):
            for x in re.findall(r"sysmsg\((1219[1-4])", strip_bas(raw[prog])):     # 10 Nov 26 Windows port: Linux 11186-11189 + 1005
                cited.setdefault(prog, set()).add(int(x))
    if cited.get("tk_keys") != {12193} or cited.get("tool_tktest") != {12194}:
        res["messages"].append("only tk_keys cites 12193 and only tool_tktest cites 12194 (got %s)" % {k: sorted(v) for k, v in cited.items()})
    # ***OWNER ANSWER 25: the registry runs nothing.***  It lists and names actions and returns an action id; the page's own handler is the only place an id becomes work.
    res["norun"] = []
    for name, src in (("tk_keys", strip_bas(raw.get("tk_keys", ""))), ("tk_fkeys", strip_bas(raw.get("tk_fkeys", "")))):
        for w in NO_RUN_WORDS:
            pat = re.escape(w) if not w[0].isalpha() or not w[-1].isalpha() else r"\b%s\b" % re.escape(w)
            # tk_fkeys calls $tk_keys 'name' and nothing else
            for mm in re.finditer(pat, src):
                line = src[src.rfind("\n", 0, mm.start()) + 1:src.find("\n", mm.end())]
                if name == "tk_fkeys" and w == "call $" and "call $tk_keys('name'" in line:
                    continue
                res["norun"].append("%s contains '%s': %s" % (name, w, line.strip()[:60]))
    targets = set(re.findall(r"gosub ([a-z.]+)", tk))
    if not targets <= {"act.state", "key.name"}:
        res["norun"].append("tk_keys gosubs %s, not only act.state and key.name" % sorted(targets - {"act.state", "key.name"}))
    # a page that puts actions in a menu runs a menu answer through the page's one case on the action id
    res["samehandler"] = []
    menus_users = []
    facade_users = []
    for prog in sorted(raw):
        if prog.startswith("msg:") or prog in ("tk_aipage", "tk_std"):      # tk_aipage puts ONE entry in the menu of the page that calls it; the page's own case on that key is test-aipage-units.py's.  tk_std (S.179) the same for theme and keys: every page that calls it has its own case on ctrl-t and ctrl-k (test-tkstd-units.py)
            continue
        code = strip_bas(raw[prog])
        acts = [args[2].strip().strip("'") for no, op, args, line in calls_in(code) if op == "menu" and len(args) == 7]
        if not acts:
            continue
        menus_users.append(prog)
        if "$tk_menubar(" in code:
            # 30 Oct 26 (S.88 F0a): a page on the toolkit's bar.  The bar returns the KEY of the chosen action (field 4 of its answer is the name to dispatch on) and the page's own case on that
            # key does what it does for the key itself: ONE handler per action, the key's, with the registry running nothing.  So: every menu action has a key, the page asks the bar for a key
            # once and for a click once, takes each answer as `nm = mr<4>` once, and draws the bar before the frame.
            facade_users.append(prog)
            keyed = {args[4].strip().strip("'") for no, op, args, line in calls_in(code) if op == "add" and len(args) == 7 and args[2].strip().strip("'") != ""}
            for act in sorted(set(acts)):
                if act not in keyed:
                    res["samehandler"].append("%s: the menu action '%s' has no key, so the bar has nothing to replay through the page's case; a keyless action needs its row read" % (prog, act))
            # 11 Nov 26: tool_ai draws the bar a second time, in box.resized (S.209: a resize while its own box is open draws the page, the bar and the foot behind
            #   the box, because the main loop that draws them is waiting for the box).  A draw answers nothing, so the one-handler rule is the key and click hooks';
            #   a second draw is listed here by name, and any other is still refused.  Reported by the Windows agent (mail 2026-11-11T0140): the check was red on 7bc274b9.
            #   (Linux 074397f6, carried 11 Nov 26; tool_ai is not in the Windows tree yet.)
            draws = {"tool_ai": 2}
            for hook, want in (("'draw'", draws.get(prog, 1)), ("'key'", 1), ("'click'", 1)):
                n = len(re.findall(r"call \$tk_menubar\(%s," % hook, code))
                if n != want:
                    res["samehandler"].append("%s: %d calls of $tk_menubar %s, expected %d" % (prog, n, hook, want))
            n = len(re.findall(r"\bnm = \w+<4>", code))
            if n != 2:
                res["samehandler"].append("%s: the bar's answer reaches nm %d times, expected 2 (the key hook and the click hook)" % (prog, n))
            if re.search(r"\bmr<[123]>", code) and not re.search(r"\bmr<1>\s*#\s*''", code):
                res["samehandler"].append("%s: the bar's answer is read for something other than the name to dispatch on" % prog)
            if code.find("call $tk_menubar('draw'") > code.find("call $tk_frame("):
                res["samehandler"].append("%s: the bar is not drawn before the frame" % prog)
            continue
        for act in sorted(set(acts)):
            lines = [l for l in code.split("\n") if re.match(r"\s*case\b", l) and re.search(r"\bact\s*=\s*'%s'" % re.escape(act), l)]
            if len(lines) != 1:
                res["samehandler"].append("%s: the action '%s' has %d 'case act' handlers, not one" % (prog, act, len(lines)))
        mcs = re.findall(r"screen menubar [^\n]*returning (\w+)", code)
        if len(mcs) != 1:
            res["samehandler"].append("%s: %d menu bars that return an answer, not one" % (prog, len(mcs)))
            continue
        mc = mcs[0]
        uses = re.findall(r"\b%s\b" % re.escape(mc), code)
        if len(uses) != 2 or not re.search(r"^\s*act = %s\s*$" % re.escape(mc), code, re.M):
            res["samehandler"].append("%s: the menu answer %s is used %d times; it must be used once, as `act = %s`" % (prog, mc, len(uses), mc))
        first_case = re.search(r"^\s*begin case\s*\n\s*case act = ", code, re.M)
        ans = code.find("act = " + mc)
        if not first_case or ans < 0 or ans > first_case.start():
            res["samehandler"].append("%s: the menu answer does not reach `act` before the program's case on act" % prog)
        if "call $tk_keys('action', keys, k, pane, act, '', '')" not in code or code.find("act = " + mc) < code.find("call $tk_keys('action'"):
            res["samehandler"].append("%s: ACT is not set from the key table before the menu answer replaces it" % prog)
    if [p for p in menus_users if p not in facade_users] != ["tool_tktest"]:
        res["samehandler"].append("the programs that call $tk_keys 'menu' are %s; the registry's own pilot is tool_tktest, the pages on $tk_menubar are held by the rules above, and any other needs its row read" % menus_users)
    # mnemonics of the registry's own menus: one & in every entry, unique in a menu and among the titles
    res["regmenu"] = []
    for prog in sorted(raw):
        if prog.startswith("msg:"):
            continue
        menus = {}
        for no, op, args, line in calls_in(strip_bas(raw[prog])):
            if op == "menu" and len(args) == 7:
                k, title = literal(args[3])
                k2, entry = literal(args[4])
                if k != "lit" or k2 != "lit":
                    res["regmenu"].append("%s:%d title or entry is not a quoted text" % (prog, no))
                    continue
                menus.setdefault(title, []).append(entry)
        letters = {}
        for title, entries in menus.items():
            if title.count("&") != 1:
                res["regmenu"].append("%s: title '%s' has %d marks" % (prog, title, title.count("&")))
                continue
            t = re.search(r"&(.)", title).group(1).lower()
            if t in letters:
                res["regmenu"].append("%s: title letter %s is used twice" % (prog, t))
            letters[t] = 1
            seen = set()
            for en in entries:
                if en.count("&") != 1:
                    res["regmenu"].append("%s: entry '%s' has %d marks" % (prog, en, en.count("&")))
                    continue
                c = re.search(r"&(.)", en).group(1).lower()
                if c in seen:
                    res["regmenu"].append("%s: menu %s uses the letter %s twice" % (prog, title, c))
                seen.add(c)
    # the pilot in tool_tktest
    res["pilot"] = []
    for what, text in (("only with the word menubar", "pilot = (if index(' ' : @sentence : ' ', ' menubar ', 1) then 1 else 0)"),
                       ("Esc is on no function-key row", "keys<nk, TK.K.ROW> = 0"),
                       ("Save as has no key", "call $tk_keys('add', keys, '', 'save as', 'saveas', 'A' : @sm : 'B', 1)"),
                       ("Save as has a reason from message 12194", "call $tk_keys('why', keys, 'saveas', sysmsg(12194), '', '', '')"),
                       ("the bar is made by 'menus' for the focused pane", "call $tk_keys('menus', keys, '', menus, pane, '', '')"),
                       ("the bar is drawn on row 0", "screen menubar menus row 0 draw else null")):
        if text not in appn:
            res["pilot"].append("tool_tktest lacks: " + what)
    # 3 Nov 26 (S.88 K7/K8): the finder (F2) and the context menu (Shift-F10, a right press) are the bar's, made from the same menus, and answer as the bar does: the action's KEY, which the
    # page replays through its own case.  A disabled entry is never answered, the context menu lists only what the pane uses, and the page's own binding of the key wins.
    res["finder"] = []
    mb = norm(strip_bas(raw.get("tk_menubar", "")))
    for what, text in (("F2 is the finder", "case nm = 'f2' start = -1"), ("Shift-F10 is the context menu", "case nm = 'shift-f10' start = -2"),
                       ("the page's own binding of the key wins", "if start # 0 then call $tk_keys('action', keys, nm, pane, pa, '', '') if pa # '' and pa # 'menu' then start = 0 end"),
                       ("a right press opens the context menu at the pointer", "case op = 'click' and a<1> = 'press' and a<2> = 3 cx = a<3> + 0 ; cy = a<4> + 0 gosub box.at"),
                       # 3 Nov 26 (owner: "Move focus first"): on a focus box that has not the focus, the page's own left press first, the menu on the next draw
                       ("a right press on another focus box is the page's left press, and the menu waits for the draw",
                        "if bx.name # '' and bx.name # pane then rc.state = 'ctx' ; rc.x = cx ; rc.y = cy ; rc.epoch = ctx<TK.C.EPOCH> a<2> = 1 end else gosub run.context end"),
                       ("the draw opens the waiting menu once, for this open of the page, and leaves the choice for the next SCREEN KEY",
                        "if rc.state = 'ctx' and rc.epoch = ctx<TK.C.EPOCH> then rc.state = '' cx = rc.x ; cy = rc.y gosub run.context if c<1> = 'act' and c<4> # '' then kp.name = 'kp:' : c<4> c = '' end"),
                       ("the box under the pointer is a shown focus box's", "if rr<1, 1, 5> and cx >= rr<1, 1, 1> and cx < rr<1, 1, 1> + rr<1, 1, 3> and cy >= rr<1, 1, 2> and cy < rr<1, 1, 2> + rr<1, 1, 4> then bx.name = fo<1, fi, 2>"),
                       ("the finder lists the bar's own menus", "call $sl_palette(menus, sysmsg(15000), pr, ps, pw)"),
                       ("a disabled entry is answered with its reason and nothing chosen", "case ps = 2 screen msgbox pw returning bn else bn = 0 gosub no.answer"),
                       ("an answer is the action's key, as the bar's", "answer.act: call $tk_keys('keyof', keys, pr, pane, kn, '', '') c = 'act' : @fm : pr : @fm : kn : @fm : (if kn = '' then 'act:' : pr else kn)"),
                       ("the context menu leaves out File and Help", "if tt = 'File' or tt = 'Help' or tt[1, 1] = '>' then continue"),
                       ("the context menu lists only what the pane uses, with the bar's flags", "gosub pane.uses if uses then citems<1, -1> = menus<k, v, 1> : @sm : menus<k, v, 2> : @sm : fa : @sm : menus<k, v, 4>"),
                       ("the pane test is the key table's", "if pl = '' or index(@sm : pl : @sm, @sm : pane : @sm, 1) then"),
                       ("the context menu ends with the finder, under a code that is not a submenu's (>)", "citems<1, -1> = sysmsg(15001) : @sm : 'F2' : @sm : 'tk:palette'")):
        if text not in mb:
            res["finder"].append("tk_menubar lacks: " + what)
    mbq = re.sub(r"'[^']*'", "''", mb)          # the op names ('open', 'draw' ...) are quoted texts, not statements
    for w in ("execute", "perform", "chain", "write", "delete", "open", "@sentence", "kernel("):
        if re.search(r"\b%s\b" % re.escape(w) if w[0].isalpha() and w[-1].isalpha() else re.escape(w), mbq):
            res["finder"].append("tk_menubar contains '%s': the bar, the finder and the context menu run nothing" % w)
    if mb.count("gosub answer.act") != 2:
        res["finder"].append("the finder and the context menu answer through answer.act (twice), found %d" % mb.count("gosub answer.act"))
    sk = norm(strip_bas(raw.get("screen_key", "")))
    if "if kp.name[1, 3] = 'kp:' then ret = kp.name[4, 999] kp.name = '' status = 0 return end" not in sk or "kp.name = 'kp:'" in sk:
        res["finder"].append("!screen_key does not give the menu bar's left key once (marked kp:, then cleared), or sets one itself")
    return res


B_TEXT = {
    "tablevalues": "tk.h: the key table's nine values, the first five where they were (MENU 6, ENTRY 7, WHY 8, ROW 9 are new)",
    "ops": "tk_keys keeps seven arguments and the five-value 'add'; it implements add, name, action, menu, why, menus, keyof, keylist, ai, aiacts and no other op",
    "action": "'action': an empty key matches nothing, a switched-off action or one with a reason is not returned, the pane is tested",
    "why": "'why' takes the action out of use together with the reason, and gives back only an action that had one",
    "menus": "'menus': the flag D comes from the action's state (switched off, a reason, or a pane that does not use it); the shown key is derived; one entry an action",
    "keyof": "'keyof' returns the key of the first enabled binding for the pane",
    "name": "'name' knows PgUp, PgDn, ^, Shift- and Alt-",
    "fkeys": "tk_fkeys leaves a key-less row and a ROW = 0 row off the function-key row",
    "messages": "messages 12191 to 12194 exist, are one line each, 12193 holds %1; only tk_keys cites 12193 and only tool_tktest 12194",
    "norun": "OWNER ANSWER 25: tk_keys and tk_fkeys contain no word that runs, opens, writes, calls or stops anything (and gosub only act.state and key.name): the registry cannot run an action",
    "samehandler": "OWNER ANSWER 25: in a page that puts actions in a menu, every such action has exactly one `case act` handler and the menu answer is used only as `act = answer`, before that case",
    "regmenu": "the registry's own menus: one & in every title and entry, no letter twice in a menu or among the titles",
    "pilot": "tool_tktest's pilot: only with the word menubar, Esc off the key row, Save as with no key and a reason, the bar made by 'menus' and drawn on row 0",
    "finder": "S.88 K7/K8: F2 (the finder) and Shift-F10 or a right press (the context menu of the pane) are the bar's, made from its menus, answered as the bar answers (the action's key), never a disabled entry, a page's own binding winning; the bar runs nothing",
}
# ---- PART B ENDS ----

# ---------------------------------------------------------------------------------------------------------------------- the run

def run(raw, s0=False):
    rows = rows_of(raw)
    res = run_a(raw, rows)
    texts = dict(A_TEXT)
    if not s0:
        res.update(run_b(raw))
        texts.update(B_TEXT)
    return judge(res), texts, rows


M = []         # (file, text to change, replacement, what it breaks, the check that must go red)
M_A = len(M)


def mut(fname, old, new, what, expect):
    M.append((fname, old, new, what, expect))


mut("tool_keys", "call $tk_keys('add', keys, 'ctrl-q', 'quit', 'quit', '', 1)", "call $tk_keys('add', keys, 'ctrl-x', 'quit', 'quit', '', 1)", "quit moved off Ctrl-Q", "quitkey")
mut("tool_keys", "call $tk_keys('add', keys, 'ctrl-l', 'clear', 'clear', '', 1)", "call $tk_keys('add', keys, 'ctrl-r', 'clear', 'clear', '', 1)", "two actions on Ctrl-R", "conflict")
mut("tool_keys", "call $tk_keys('add', keys, 'ctrl-t', 'theme', 'theme', '', 1)", "call $tk_keys('add', keys, 'ctrl-t', 'theme', 'raw', '', 1)", "one action with two labels and two keys", "label")
mut("tool_keys", "call $tk_keys('add', keys, 'ctrl-q', 'quit', 'quit', '', 1)", "call $tk_keys('add', keys, 'ctrl-q', 'quit', 'quit', 1)", "a call with six arguments", "args")
mut("tool_keys", "call $tk_keys('add', keys, 'ctrl-t', 'theme', 'theme', '', 1)", "call $tk_keys('add', keys, 'ctrl-9', 'theme', 'zzact', '', 1)", "a key whose action has no handler in the page", "handler")
mut("tool_keys", "call $tk_keys('add', keys, 'ctrl-l', 'clear', 'clear', '', 1)", "call $tk_keys('add', keys, 'f11', 'clear', 'clear', '', 1)", "a new F11 binding outside the ledger", "reserved")
mut("tool_keys", "call $tk_keys('add', keys, 'ctrl-q', 'quit', 'quit', '', 1)", "call $tk_keys('add', keys, 'ctrl-q', 'quit', 'quit', '', 1)\n   call $tk_keys('add', keys, 'ctrl-q', 'quit', 'quit', '', 1)", "a row more than the table has", "parse")
mut("msg:12659", "&Ask about this record", "&Explain about this record", "a duplicate mnemonic in the AI menu", "mnemonic")
mut("msg:12659", "&Ask about this record", "Ask about this record", "an entry with no mnemonic", "mnemonic")
mut("tool_home", "call $tk_keys('add', keys, 'f6', 'ai', 'ai', '', 1)", "call $tk_keys('add', keys, 'f6', 'ai', 'askai', '', 1)", "tool_home's F6 bound to another action than the AI line", "reserved")

# ---- PART B MUTANTS BEGIN ----
M_P39B = len(M)
mut("tk_keys", "if a # '' and keys<i, TK.K.KEY> = a", "if keys<i, TK.K.KEY> = a", "an empty key matches the first empty-key row", "action")
mut("tk_keys", "and keys<i, TK.K.ON> # '0' and keys<i, TK.K.WHY> = '' then", "and keys<i, TK.K.ON> # '0' then", "'action' returns an action that has a reason", "action")
mut("tk_keys", "keys<i, TK.K.ON> = 0\n", "keys<i, TK.K.ON> = 1\n", "'why' leaves the action in use", "why")
mut("tk_keys", "fl = (if ia then '' else 'D')", "fl = ''", "no entry is ever disabled", "menus")
mut("tk_keys", "if keys<j, TK.K.ON> # '0' and keys<j, TK.K.WHY> = '' then", "if keys<j, TK.K.ON> # '0' then", "a reason does not disable the entry", "menus")
mut("tk_keys", "if ikf = '' then ikf = kj", "ikf = kj", "keyof returns the last binding, not the first enabled one", "keyof")
mut("tk_keys", "kt = 'PgDn'", "kt = 'Pgdn'", "PgDn is written Pgdn", "name")
mut("tk_keys", "keys<-1> = a : @vm : b : @vm : c : @vm : d : @vm : e", "keys<-1> = a : @vm : b : @vm : c : @vm : d", "'add' drops the ON value", "ops")
mut("tk_keys", "      case op = 'keyof'\n", "      case op = 'keyof'\n         execute c\n", "the registry executes a sentence", "norun")
mut("tk_keys", "      case op = 'keyof'\n", "      case op = 'keyof'\n         call $tk_run('x', 's', o, st, er)\n", "the registry runs a command through $tk_run", "norun")
mut("tk_keys", "      case op = 'keyof'\n", "      case op = 'keyof'\n         screen text 'x' at 0,0\n", "the registry writes to the screen", "norun")
mut("tk_keys", "         c = ikf\n", "         c = ikf\n         gosub run.it\n", "the registry gosubs a routine of its own that is not one of the two", "norun")
mut("tk_fkeys", "keys<i, TK.K.ROW> # '0' and ", "", "ROW = 0 stays on the key row", "fkeys")
mut("tk_fkeys", " and keys<i, TK.K.KEY> # ''", "", "a key-less row is on the key row", "fkeys")
mut("tool_tktest", "            act = mc\n", "            msg = mc\n", "a menu answer is handled by code of its own, not the case on act", "samehandler")
mut("tool_tktest", "            msg = 'sorted'", "            msg = 'sorted'\n         case act = 'sort'\n            msg = 'again'", "a second handler for the action the menu offers", "samehandler")
mut("tool_tktest", "      call $tk_keys('why', keys, 'saveas', sysmsg(12194), '', '', '')\n", "", "Save as has no reason: the pilot's null case is gone", "pilot")
mut("tool_tktest", "'refresh', '&Actions', '&Refresh'", "'refresh', '&Actions', '&Seek'", "two entries with the letter S (Seek, Sort)", "regmenu")
mut("tool_tktest", "'refresh', '&Actions', '&Refresh'", "'refresh', '&Actions', '&Sample'", "two entries with the letter S", "regmenu")
mut("msg:12193", "%1", "reason", "message 12193 loses its substitution", "messages")
mut("tk.h", "$define TK.K.ROW       9", "$define TK.K.ROW       8", "ROW takes WHY's place", "tablevalues")
# 30 Oct 26 (S.88 F0a pilot): tool_mygates on $tk_menubar - the first of these is marker M_F0A for --from=
M_F0A = len(M)
mut("tool_mygates", "   call $tk_keys('menu', keys, 'refresh', '&View', '&Refresh', '', '')\n", "   call $tk_keys('menu', keys, 'refresh', '&View', '&Refresh', '', '')\n   call $tk_keys('menu', keys, 'saveas', '&File', 'Save &as', '', '')\n", "a menu action with no key on a bar page", "samehandler")
mut("tool_mygates", "      if mr<1> # '' then nm = mr<4>\n", "", "the bar's answer is not taken in the loop", "samehandler")
mut("tool_mygates", "      nm = mr<4>\n      if nm # '' then gosub on.key", "      nm = mr<2>\n      if nm # '' then gosub on.key", "a click on the bar is dispatched on the action id, not the name", "samehandler")
mut("tool_mygates", "      call $tk_menubar('draw', ctx, keys, 'My gates', '', '', mr)", "      call $tk_frame(ctx, keys, 'My gates', msg)\n      call $tk_menubar('draw', ctx, keys, 'My gates', '', '', mr)", "the bar is drawn after the frame", "samehandler")
mut("tool_mygates", "      if nm # '' and ao<1> = '' then call $tk_menubar('key', ctx, keys, 'My gates', nm, 0, mr)", "      if nm # '' and ao<1> = '' then mr = ''", "the Esc row has no bar to take it", "handler")
# 29 Oct 26 (the Opus reviews of the page fan-out, findings 1, 2, 5 and 13) - the first of these is marker M_FANOUT for --from=
M_FANOUT = len(M)
mut("tool_query", "call $tk_menubar('key', ctx, keys, cur.pane, nm, busy, mr)", "call $tk_menubar('key', ctx, keys, cur.pane, nm, 0, mr)", "a page with an Esc case of its own gives the bar no busy", "handler")
mut("tool_query", "busy = (if cur.pane = 'File' and filt # '' then 1 else 0)", "busy = (if filt # '' then 1 else 0)", "tool_query's busy holds for every pane (the pre-fix code)", "handler")
mut("tool_dict", "or pi = 3 then 1 else 0)", "then 1 else 0)", "tool_dict's busy leaves the Indices pane out (the pre-fix code)", "handler")
mut("tk_keys", "            if qent # '' then m<1, -1> = qent", "            if 0 then m<1, -1> = qent", "Quit is dropped from its menu", "menus")
mut("tk_keys", "if fa = 'quit' then qent = ent else m<1, -1> = ent", "m<1, -1> = ent", "Quit stays where the table put it", "menus")
# 31 Oct 26 (S.86 stage 4): the IDE's pane "fields" - the first of these is marker M_S86 for --from=
M_S86 = len(M)
mut("ide", "call $tk_keys('add', ide.keys, 'ctrl-v', 'paste', 'paste', 'fields', 1)", "call $tk_keys('add', ide.keys, 'ctrl-9', 'paste', 'paste', 'fields', 1)", "a key of the pane that the engine has no case for", "handler")
mut("ide", "call $tk_keys('add', ide.keys, 'ctrl-c', 'copy', 'copy', 'fields', 1)", "call $tk_keys('add', ide.keys, 'ctrl-t', 'copy', 'copy', 'fields', 1)", "Ctrl-T bound to two actions in the pane", "conflict")
# 2 Nov 26 (S.88 U9): the home screen on $tk_menubar - the first of these is marker M_U9 for --from=
M_U9 = len(M)
# 11 Nov 26: four mutants here were dead since S.176 / S.179 (the Windows agent, mail 2026-11-11T0140): the home screen's Ctrl-K row and tool_test's Tab row are gone
#   (their texts no longer occur), and Switch account moved to Ctrl-T met no parsed row, since the theme key is $tk_std's.  They are remade on rows that exist.
#   (Linux 074397f6, carried 11 Nov 26 in place of the Windows port's four commented-out ones.)
mut("tool_home", "   call $tk_keys('add', keys, 'ctrl-r', 'recent', 'recent', '', 1)\n", "", "the home screen's View > Recent group entry has no key", "samehandler")
mut("tool_home", "      if mr<1> # '' then nm = mr<4>\n", "", "the home screen's loop drops the bar's answer", "samehandler")
mut("tool_home", "      case nm = '/'\n", "      case nm = '?'\n", "the home screen binds / and acts on another key", "handler")
mut("tool_home", "   call $tk_keys('add', keys, 'ctrl-w', 'switch', 'switch', '', 1)\n", "   call $tk_keys('add', keys, 'alt-t', 'switch', 'switch', '', 1)\n", "Alt-T is Terminal and Switch account on the home screen", "conflict")
# 3 Nov 26 (S.88 K7/K8 and "Tab panes"): the first of these is marker M_K78 for --from=
M_K78 = len(M)
mut("tk_menubar", "            case nm = 'f2'\n               start = -1", "            case nm = 'f3'\n               start = -1", "the finder is on another key", "finder")
mut("tk_menubar", "            if pa # '' and pa # 'menu' then start = 0\n", "", "the bar takes F2 from a page that binds it", "finder")
mut("tk_menubar", "      case ps = 2\n         screen msgbox pw returning bn else bn = 0\n         gosub no.answer", "      case ps = 2\n         gosub answer.act", "a disabled entry of the finder is answered", "finder")
mut("tk_menubar", "         if uses then citems<1, -1>", "         citems<1, -1>", "the context menu lists every action, not the pane's", "finder")
mut("tk_menubar", "      if tt = 'File' or tt = 'Help' or tt[1, 1] = '>' then continue", "      if tt[1, 1] = '>' then continue", "the context menu holds File and Help", "finder")
mut("tk_menubar", "      case 1\n         gosub answer.act\n   end case", "      case 1\n         execute pr\n   end case", "the context menu runs its answer", "finder")
mut("tk_menubar", "      case op = 'click' and a<1> = 'press' and a<2> = 3\n", "      case op = 'click' and a<1> = 'press' and a<2> = 1\n", "a left press opens the context menu", "finder")
mut("tool_test", "   call $tk_keys('add', keys, 'f6', 'box', 'pane', '', 1)", "   call $tk_keys('add', keys, 'f2', 'box', 'pane', '', 1)", "a page binds F2 (the finder's key)", "reserved")
mut("tool_test", "   call $tk_keys('add', keys, 'f6', 'box', 'pane', '', 1)", "   call $tk_keys('add', keys, 'shift-f10', 'box', 'pane', '', 1)", "a page binds Shift-F10 (the context menu's key)", "reserved")
mut("msg:15004", "&Programs~~tool.catalog", "&Queries again~~tool.catalog", "a duplicate mnemonic in the IDE's Tools menu", "mnemonic")
mut("msg:15004", "&Tools|", "&File tools|", "the Tools menu's title takes File's letter", "mnemonic")
# 3 Nov 26 (owner: "Move focus first")
mut("tk_menubar", "            a<2> = 1\n", "", "the right press on another box does not become the page's left press", "finder")
mut("tk_menubar", "            rc.state = ''\n            cx = rc.x", "            cx = rc.x", "the waiting menu opens on every draw", "finder")
mut("screen_key", "      kp.name = ''\n", "", "SCREEN KEY gives the left key for ever", "finder")
# ---- PART B MUTANTS END ----


def selftest(frm, s0):
    try:
        raw = load()
    except (OSError, IOError) as e:
        print("CANNOT RUN: %s" % e)
        return 2
    base, _, _ = run(raw, s0)
    if any(not ok for _, ok, _ in base):
        print("selftest: the real files already fail a check")
        return 1
    killed, missed = 0, []
    for i, (fname, old, new, what, expect) in enumerate(M):
        if i < frm:
            continue
        if s0 and i >= M_P39B:
            continue
        if fname not in raw:
            print("  [CANNOT] %s: no such file %s" % (what, fname))
            return 2
        if raw[fname].count(old) != 1:
            print("  [CANNOT] %s: the text to change is found %d times in %s, not once" % (what, raw[fname].count(old), fname))
            return 2
        m = dict(raw)
        m[fname] = raw[fname].replace(old, new)
        res, _, _ = run(m, s0)
        red = [n for n, ok, _ in res if not ok]
        if expect in red:
            killed += 1
            print("  [killed] #%d %s  <- %s" % (i, what, ", ".join(red)))
        else:
            missed.append(what)
            print("  [MISSED] #%d %s (wanted %s red, got %s)" % (i, what, expect, red or "none"))
    print("selftest: %d mutants run, %d killed, %d missed (M_P39B = %d)" % (killed + len(missed), killed, len(missed), M_P39B))
    return 0 if not missed and killed else 1


def main():
    s0 = "--s0" in sys.argv
    if "--selftest" in sys.argv:
        frm = 0
        for a in sys.argv:
            if a.startswith("--from="):
                frm = int(a[7:])
        return selftest(frm, s0)
    try:
        raw = load()
    except (OSError, IOError) as e:
        print("CANNOT RUN: %s" % e)
        return 2
    res, texts, rows = run(raw, s0)
    bad = 0
    print("test-tk-keys-units: read %d 'add' rows of %d programs%s" % (len(rows), len({r['prog'] for r in rows}), " (part A only: --s0)" if s0 else ""))
    for name, ok, detail in res:
        print("  [%s] %s: %s%s" % ("ok" if ok else "FAIL", name, texts.get(name, ""), ("\n        " + detail) if detail else ""))
        bad += 0 if ok else 1
    print("test-tk-keys-units: %d passed, %d failed" % (len(res) - bad, bad))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
