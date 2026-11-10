#!/usr/bin/env python3
"""test-tkguards-units.py - the three shared guards of the toolkit that S.88 phase 2 added (`gpl.bp/tk_ownfile`, `tk_word`, `tk_brk`) and where they are called, read off the source as text.
Free: no install, no sudo, no sd.

    python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/test-tkguards-units.py [--selftest]

WHAT THIS IS, AND WHAT IT IS NOT.  It reads BASIC as text, with comments removed.  ***IT RUNS NOTHING, SO IT CANNOT SAY THAT A FILE IS REFUSED, THAT A KEYWORD IS REFUSED OR THAT THE BREAK
KEY COMES BACK***: those are `sandbox-tool-query.py` section q13 (S2), `sandbox-tool-voc.py` section v7 (S4) and `sandbox-termsafe.py` section D4 (the break key), run on a private SD later.
What a text check is for: the ORDER and ABSENCE properties that make the guards worth having - each test comes before the one after it and the first reason found is returned; the guards
change nothing (no write, delete or execute); the break setting is kept BEFORE it is changed and given back by every way out (the app's own closing routine, the cleanup the command
processor runs before a prompt, a page that traps an abort, SED); and the callers are the pages that must have them.

THE DEFECTS (Opus_TUI_Plan.txt section 4): S2 (tool.query wrote and deleted records of &queries& with no K$EDIT.OK check), S4 (tool.voc's Delete on the VOC keyword `all` built
`delete voc all`), D4 (the break key left dead after an abort inside an app).

NOT COVERED, AND SAID SO: the IDE (`ide`) keeps its own copy of the break setting and gives it back in its own closing code; an abort inside it still leaves the key dead until it calls
`$tk_brk('save', ...)` and `$tk_brk('close', ...)` too (open, listed in the report of 28 Oct 26).  CED (`ced_edit`) does since the review of the same day (G13b).

--selftest breaks each invariant in the way an edit plausibly would and requires a check to notice; a mutant that nothing catches is a failure of the self-test.
"""

import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SDSYS = os.path.normpath(os.path.join(HERE, "..", "sdsys"))
GPL = os.path.join(SDSYS, "gpl.bp")
MSG = os.path.join(SDSYS, "messages")
FILES = {n: os.path.join(GPL, n) for n in ("tk_ownfile", "tk_word", "tk_brk", "tk_open", "tk_close", "sl_cleanup", "tool_bulk", "tool_query", "tool_voc", "tool_files", "tool_home", "ced_edit")}
MESSAGES = [str(n) for n in range(12760, 12766)]


def load():
    raw = {}
    for k, p in FILES.items():
        try:
            with open(p, encoding="latin-1") as f:
                raw[k] = f.read()
        except OSError:
            raw[k] = ""
    for n in MESSAGES:
        try:
            with open(os.path.join(MSG, n), encoding="latin-1") as f:
                raw["m" + n] = f.read()
        except OSError:
            raw["m" + n] = ""
    return raw


def strip_bas(src):
    out = []
    for line in src.split("\n"):
        s = line.lstrip()
        if s.startswith("*") or s.startswith("!"):
            out.append("")
            continue
        cut = line.find(";*")
        out.append((line if cut < 0 else line[:cut]).rstrip())
    return "\n".join(out)


def block(text, label):
    """The text of an internal subroutine: from its label to the next label at the start of a line (or to END)."""
    m = re.search(r"^" + re.escape(label) + r":\s*$", text, re.M)
    if not m:
        return ""
    n = re.search(r"^[a-z][a-z.0-9]*:\s*$|^end\s*$", text[m.end():], re.M)
    return text[m.start(): m.end() + (n.start() if n else len(text))]


def ordered(text, *needles):
    """every needle is in the text and they come in this order"""
    at = -1
    for n in needles:
        i = text.find(n, at + 1)
        if i < 0:
            return False
        at = i
    return True


def callers(raw, call):
    """the programs of the tree (the ones this check loads) whose code calls `call`"""
    return sorted(k for k in FILES if k not in ("tk_ownfile", "tk_word", "tk_brk") and call in strip_bas(raw[k]))


def checks(raw):
    rows = []

    def ck(i, what, ok, detail=""):
        rows.append((i, what, bool(ok), detail))

    own, word, brk = (strip_bas(raw[k]) for k in ("tk_ownfile", "tk_word", "tk_brk"))
    op, cl, cu = (strip_bas(raw[k]) for k in ("tk_open", "tk_close", "sl_cleanup"))
    ck("G0", "NULL CASE: the three guards, the callers and the six messages were found and are not empty (a check on nothing would pass)",
       all(len(x) > 150 for x in (own, word, brk, op, cl, cu)) and all(raw["m" + n].strip() for n in MESSAGES), repr([len(x) for x in (own, word, brk, op, cl, cu)]))

    # ------------------------------------------------------------------------------------------------------------------------------------ $tk_ownfile (S2)
    ck("G1", "$tk_ownfile is an internal subroutine catalogued $tk_ownfile with the four arguments (file, name, ok, why); ok and why are set FIRST (a refusal can never be read as an old yes), and it changes nothing: "
       "no write, delete, clearfile, execute or logto",
       re.search(r"^\$internal\s*\nsubroutine tk_ownfile\(fv, name, ok, why\)\s*\n\$catalog \$tk_ownfile\b", own, re.M) is not None and ordered(own, "ok = 0", "why = ''", "begin case")
       and not re.search(r"^\s*(write|writev|delete|clearfile|execute|logto|osdelete|oswrite)\b", own, re.M), "")
    ck("G2", "the tests come in this order and the FIRST that refuses wins: a dynamic file, not read only, directly in the account's own directory under the name it was opened by (the folder the VOC is in), "
       "of no VOC / dictionary / program kind, allowed by the kernel's edit rules, and of kind 0; the kernel is asked K$EDIT.KIND and K$EDIT.OK of THE OPEN FILE's path; only the last case sets ok",
       ordered(own, "ucd = fileinfo(uvf, FL$PATH)", "ucd = field(ucd, '/', 1, dcount(ucd, '/') - 1)", "ucp = fileinfo(fv, FL$PATH)", "uct = fileinfo(fv, FL$TYPE)", "ucek = kernel(K$EDIT.KIND, ucp)",
               "uceo = kernel(K$EDIT.OK, ucp)", "case uct # FL$TYPE.DH", "case fileinfo(fv, FL$READONLY) = 1", "case ucd = '' or ucp # ucd : '/' : name", "case ucek >= 1 and ucek <= 3",
               "case not(uceo)", "case ucek # 0", "case 1\n         ok = 1") and own.count("ok = 1") == 1, "")
    ck("G3", "its reasons are the messages 12761 (not a dynamic file), 12762 (read only), 12763 (not in the account's own directory) and 12764 (leads to the VOC, a dictionary or a program file), "
       "and the kernel's own words (!edit_msg) for an edit rule or a kind; the text is the wording TOOL.BULK has always shown",
       ordered(own, "why = sysmsg(12761, name)", "why = sysmsg(12762, name)", "why = sysmsg(12763, name)", "why = sysmsg(12764, name,", "why = edit_msg(ucek)", "why = edit_msg(ucek)")
       and "deffun edit_msg(kind) calling '!edit_msg'" in own, "")
    bu, qu = strip_bas(raw["tool_bulk"]), strip_bas(raw["tool_query"])
    ck("G4", "the callers: TOOL.BULK asks it of the undo file (check.undo), TOOL.QUERY of &queries& (check.qfile), each in ONE place with the open file and its name; no other page of the loaded set calls it",
       callers(raw, "$tk_ownfile") == ["tool_bulk", "tool_query"] and "call $tk_ownfile(uf, UNDOF, uck, ucw)" in block(bu, "check.undo") and "call $tk_ownfile(qf, '&queries&', qok, qwhy)" in block(qu, "check.qfile")
       and bu.count("$tk_ownfile") == 1 and qu.count("$tk_ownfile") == 1, repr(callers(raw, "$tk_ownfile")))

    # ------------------------------------------------------------------------------------------------------------------------------------ $tk_word (S4)
    ck("G5", "$tk_word is an internal subroutine catalogued $tk_word with (name, ok, why); the character test (a-z 0-9 dot dash underscore, 1 to 63 - the set $tk_run lets through) comes FIRST and returns with 12811 "
       "carrying printable ASCII only; the VOC is read only after it; a first letter K (case folded) refuses with 12760; it changes nothing",
       re.search(r"^\$internal\s*\nsubroutine tk_word\(name, ok, why\)\s*\n\$catalog \$tk_word\b", word, re.M) is not None
       and ordered(word, "ok = (len(name) > 0 and len(name) <= 63)", "good = 'abcdefghijklmnopqrstuvwxyz0123456789._-'", "if index(good, name[q, 1], 1) = 0 then ok = @false", "if not(ok) then",
                   "if sq >= 32 and sq <= 126 then shown := name[q, 1] else shown := '?'", "why = sysmsg(12811, shown)", "return", "open 'VOC' to kwf then", "read kwr from kwf, name then",
                   "if upcase(kwr<1>[1, 1]) = 'K' then ok = @false", "close kwf", "why = sysmsg(12760, name)")
       and not re.search(r"^\s*(write|writev|delete|clearfile|execute|logto)\b", word, re.M), "")
    ck("G6", "the callers: TOOL.VOC asks it before it builds `delete voc <id>`, TOOL.FILES asks it through check.kw in its four routes; no other page of the loaded set calls it",
       callers(raw, "$tk_word") == ["tool_files", "tool_voc"] and strip_bas(raw["tool_files"]).count("$tk_word") == 1 and strip_bas(raw["tool_voc"]).count("$tk_word") == 1, repr(callers(raw, "$tk_word")))

    # ------------------------------------------------------------------------------------------------------------------------------------ $tk_brk (D4)
    ck("G7", "$tk_brk is an internal subroutine catalogued $tk_brk with (op, trap) whose state is in a NAMED common block (it outlives the app that made it, as $sl_scr's does); the four ops are save, clear, close and give",
       re.search(r"^\$internal\s*\nsubroutine tk_brk\(op, trap\)\s*\n\$catalog \$tk_brk\b", brk, re.M) is not None and "common /tkbrk/ brk.held, brk.kept" in brk
       and all(("case op = '%s'" % o) in brk for o in ("save", "clear", "close", "give")), "")
    sv = brk[brk.find("case op = 'save'"): brk.find("case op = 'clear'")]
    gv = brk[brk.find("case op = 'give'"):]
    cs = brk[brk.find("case op = 'close'"): brk.find("case op = 'give'")]
    ck("G8", "save keeps the setting only when none is held (the first one is the person's own; a later one is what an aborted app left); give does nothing unless a setting is held, then puts it back with pterm(PT$BREAK, kept), turns BREAK ON and holds nothing; "
       "close prefers the setting that was held to the one it is given, puts it back, turns BREAK ON and holds nothing",
       "if not(brk.held) then" in sv and ordered(sv, "brk.kept =", "brk.held = 1") and "if brk.held then" in gv and ordered(gv, "if brk.held then", "void pterm(PT$BREAK, brk.kept)", "break on", "brk.held = 0")
       and ordered(cs, "tv = trap", "if brk.held then tv = brk.kept", "void pterm(PT$BREAK,", "break on", "brk.held = 0"), "")

    # ------------------------------------------------------------------------------------------------------------------------------------ who keeps and who gives back
    ck("G9", "$tk_open keeps the setting AFTER it reads it and BEFORE it turns the break key off, and a failure to take the screen gives it back through $tk_brk 'close' (so nothing stays held) before the error is returned",
       ordered(op, "saved.trap = pterm(PT$BREAK, -1)", "call $tk_brk('save', saved.trap)", "void pterm(PT$BREAK, @false)", "break off", "if not(opened) then", "call $tk_brk('close', saved.trap)", "err = sysmsg(12807, app)"), "")
    ck("G10", "$tk_close gives the screen back and then the setting through $tk_brk 'close' with the one $tk_open saved in the context",
       ordered(cl, "screen close", "call $tk_brk('close', ctx<TK.C.TRAP>)"), "")
    ck("G11", "$sl_cleanup - called by the command processor before a prompt and by a page that traps an abort - gives the break setting back with $tk_brk 'give' BEFORE it asks whether the library holds the screen "
       "(so the key comes back even where the screen was already closed), after the cursor lock is taken off, and writes nothing to the terminal for it",
       ordered(cu, "call $sl_guardmode('', 0, 0)", "call $tk_brk('give', '')", "call $sl_scr('get', scr)", "if not(scr<SL.S.OWNED>) then return"), "")
    th = strip_bas(raw["tool_home"])
    ck("G13", "HOME runs a tile's command trapping aborts and calls $sl_cleanup right after it (an app that was aborted may hold the screen and the break key)",
       ordered(block(th, "run.command"), "execute sentence trapping aborts", "call $sl_cleanup", "gosub reopen"), "")
    ce = strip_bas(raw["ced_edit"])
    ck("G13b", "CED keeps the break setting with $tk_brk 'save' AFTER it reads it and BEFORE it turns the break key off (so an abort inside the editor leaves it held for $sl_cleanup), gives it back through $tk_brk 'close' when the "
       "screen cannot be taken and again at its end, and no longer puts it back by hand (a hand copy would leave the kept one held)",
       ordered(ce, "saved.trap = pterm(PT$BREAK, -1)", "call $tk_brk('save', saved.trap)", "void pterm(PT$BREAK, @false)", "break off", "screen open clear then", "call $tk_brk('close', saved.trap)", "return",
               "screen close", "call $tk_brk('close', saved.trap)", "result<1> = st{'kept'}") and "void pterm(PT$BREAK, saved.trap)" not in ce and ce.count("$tk_brk") == 3, "")

    # ------------------------------------------------------------------------------------------------------------------------------------ the messages
    m = {n: raw["m" + n].strip() for n in MESSAGES}
    ck("G14", "messages 12760 to 12765: each begins with its subject (%1) in lower case, 12764 takes two values, 12760 says keyword and that the page does not give it to a command, 12765 names query1 and says it was not changed, "
       "and none begins with a capital command word",
       all(m[n].startswith("%1") for n in MESSAGES) and "%2" in m["12764"] and "keyword" in m["12760"] and "does not give it to a command" in m["12760"] and "query1" in m["12765"] and "not changed" in m["12765"]
       and m["12761"] == "%1 is not a dynamic file of this account" and m["12762"] == "%1 is read only" and m["12763"] == "%1 does not stand in this account's own directory", repr(m))
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
    ("the shared file test does not set ok first", "G1", sub("tk_ownfile", "   ok = 0\n   why = ''\n", "   why = ''\n")),
    ("the shared file test writes", "G1", sub("tk_ownfile", "   ok = 0\n   why = ''\n", "   ok = 0\n   why = ''\n   write 'x' on fv, 'y'\n")),
    ("a read only file is allowed", "G2", sub("tk_ownfile", "      case fileinfo(fv, FL$READONLY) = 1\n", "      case 0\n")),
    ("a file in another directory is allowed", "G2", sub("tk_ownfile", "      case ucd = '' or ucp # ucd : '/' : name\n", "      case 0\n")),
    ("the program file kind is allowed", "G2", sub("tk_ownfile", "      case ucek >= 1 and ucek <= 3\n", "      case 0\n")),
    ("the kernel's edit rules are not asked", "G2", sub("tk_ownfile", "      case not(uceo)\n", "      case 0\n")),
    ("the file is asked about by the wrong path", "G2", sub("tk_ownfile", "ucek = kernel(K$EDIT.KIND, ucp)", "ucek = kernel(K$EDIT.KIND, ucd)")),
    ("a hashed file is allowed", "G2", sub("tk_ownfile", "      case uct # FL$TYPE.DH\n", "      case 0\n")),
    ("the reason for a read only file is the wrong message", "G3", sub("tk_ownfile", "why = sysmsg(12762, name)", "why = sysmsg(12761, name)")),
    ("TOOL.BULK stops asking", "G4", sub("tool_bulk", "   call $tk_ownfile(uf, UNDOF, uck, ucw)\n", "   uck = 1\n")),
    ("TOOL.QUERY stops asking", "G4", sub("tool_query", "   call $tk_ownfile(qf, '&queries&', qok, qwhy)\n", "   qok = 1\n")),
    ("a name with a bad character goes on to the VOC test", "G5", sub("tk_word", "      why = sysmsg(12811, shown)\n      return\n", "      why = sysmsg(12811, shown)\n")),
    ("a keyword is allowed", "G5", sub("tk_word", "upcase(kwr<1>[1, 1]) = 'K'", "upcase(kwr<1>[1, 1]) = 'Z'")),
    ("a keyword is found by its exact case only", "G5", sub("tk_word", "if upcase(kwr<1>[1, 1]) = 'K' then ok = @false", "if kwr<1>[1, 1] = 'k' then ok = @false")),
    ("a name with a control character is shown raw", "G5", sub("tk_word", "why = sysmsg(12811, shown)", "why = sysmsg(12811, name)")),
    ("a long name is allowed", "G5", sub("tk_word", "len(name) <= 63", "len(name) <= 6300")),
    ("TOOL.VOC stops asking", "G6", sub("tool_voc", "   call $tk_word(vid, kwok, kwwhy)\n", "   kwok = 1\n")),
    ("TOOL.FILES stops asking", "G6", sub("tool_files", "   call $tk_word(fn, kwok, kwwhy)\n", "   kwok = 1\n")),
    ("the break state is in an unnamed place", "G7", sub("tk_brk", "common /tkbrk/ brk.held, brk.kept", "brk.held = 0 ; brk.kept = 0")),
    ("the give op is missing", "G7", sub("tk_brk", "case op = 'give'", "case op = 'gift'")),
    ("a later app's setting replaces the person's", "G8", sub("tk_brk", "         if not(brk.held) then\n            brk.kept", "         if 1 then\n            brk.kept")),
    ("give puts the break key back even when nothing is held", "G8", sub("tk_brk", "         if brk.held then\n            void pterm(PT$BREAK, brk.kept)", "         if 1 then\n            void pterm(PT$BREAK, brk.kept)")),
    ("give does not turn BREAK ON", "G8", sub("tk_brk", "            void pterm(PT$BREAK, brk.kept)\n            break on\n", "            void pterm(PT$BREAK, brk.kept)\n")),
    ("give holds on to the setting", "G8", sub("tk_brk", "            break on\n            brk.held = 0\n         end\n   end case", "            break on\n         end\n   end case")),
    ("close gives back what the app read, not the person's", "G8", sub("tk_brk", "         if brk.held then tv = brk.kept\n", "")),
    ("$tk_open keeps the setting after it is changed", "G9", sub("tk_open", "   call $tk_brk('save', saved.trap)                 ;* kept where $sl_cleanup can find it if the app is aborted (28 Oct 26, D4)\n   void pterm(PT$BREAK, @false)\n   break off", "   void pterm(PT$BREAK, @false)\n   break off\n   call $tk_brk('save', saved.trap)")),
    ("$tk_open leaves the setting held when the screen cannot be taken", "G9", sub("tk_open", "      call $tk_brk('close', saved.trap)\n", "      break on\n")),
    ("$tk_close gives back by hand", "G10", sub("tk_close", "   call $tk_brk('close', ctx<TK.C.TRAP>)", "   void pterm(PT$BREAK, ctx<TK.C.TRAP>)")),
    ("$sl_cleanup does not give the break key back", "G11", sub("sl_cleanup", "   call $tk_brk('give', '')", "   null")),
    ("$sl_cleanup gives it back only where the library holds the screen", "G11", sub("sl_cleanup", "   call $tk_brk('give', '')                   ;* ... nor a dead break key: the setting an app of the toolkit took and did not give back (28 Oct 26, D4); nothing is written\n   call $sl_scr('get', scr)\n   if not(scr<SL.S.OWNED>) then return        ;* the library holds nothing\n",
                                                                                "   call $sl_scr('get', scr)\n   if not(scr<SL.S.OWNED>) then return        ;* the library holds nothing\n   call $tk_brk('give', '')\n")),
    ("HOME's command is not trapped", "G13", sub("tool_home", "   execute sentence trapping aborts\n", "   execute sentence\n")),
    ("HOME does not clean up after the command", "G13", sub("tool_home", "   call $sl_cleanup\n   if pause or aborted then gosub wait.key", "   if pause or aborted then gosub wait.key")),
    ("CED keeps the setting after it is changed", "G13b", sub("ced_edit", "   call $tk_brk('save', saved.trap)         ;* 28 Oct 26: kept where $sl_cleanup can find it if the editor is aborted before it gives the setting back\n   void pterm(PT$BREAK, @false)\n   break off",
                                                           "   void pterm(PT$BREAK, @false)\n   break off\n   call $tk_brk('save', saved.trap)")),
    ("CED does not keep the setting", "G13b", sub("ced_edit", "   call $tk_brk('save', saved.trap)         ;* 28 Oct 26: kept where $sl_cleanup can find it if the editor is aborted before it gives the setting back\n", "")),
    ("CED leaves the setting held when the screen cannot be taken", "G13b", sub("ced_edit", "      call $tk_brk('close', saved.trap)\n      return", "      break on\n      return")),
    ("CED gives the setting back by hand at its end", "G13b", sub("ced_edit", "   call $tk_brk('close', saved.trap)        ;* the setting back (or the earlier app's, if one was aborted) and BREAK ON; nothing is held any more\n", "   break on\n   void pterm(PT$BREAK, saved.trap)\n")),
    ("message 12760 says nothing of a keyword", "G14", setkey("m11755", "%1 is a word this page does not give it to a command\n")),
    ("message 12765 is lost", "G14", setkey("m11760", "")),
    ("message 12762 has a capital", "G14", sub("m11757", "%1 is read only", "Read only: %1")),
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
    print("test-tkguards-units: tree %s" % os.path.dirname(GPL))
    if not raw["tk_brk"]:
        print("test-tkguards-units: CANNOT RUN - %s is not there" % FILES["tk_brk"])
        return 2
    rows = checks(raw)
    bad = report(rows)
    print("\ntest-tkguards-units: %d passed, %d failed" % (len(rows) - bad, bad))
    rc = 1 if bad else 0
    if "--selftest" in argv:
        rc = (selftest(raw) or rc)
    return rc


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
