#!/usr/bin/env python3
"""test-modifya-multi-units.py - MODIFY.ACCOUNT with more than one action in one command (owner, 19 Oct 2026), as invariants read off modifya.

  python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/test-modifya-multi-units.py
  python3 .../test-modifya-multi-units.py --selftest

No sudo, no install, no sd.  Exit 0 every check passed, 1 a check failed, 2 it could not run.

THE RULE IT HOLDS.  A command of several actions is carried out WHOLE or not at all as far as its words go: validate.actions reads every word
first and refuses (stop) on an unknown word (12795), on two different words of one slot (12796: sh-on and sh-off, ssh and api; files-off with
files-write-on) and on add or delete among other words (12719), changing nothing; run.actions then does the words in the order of one list
whatever order they were typed, each through do.action, re-reading the account first, and ends with 12798 or 12799.  Silence about half of a
command, the fault of 18 Oct 2026, stays impossible.

THREE LISTS MUST AGREE and nothing but this check ties them: the word list of validate.actions (which is also the order of execution), the case
lines of do.action, and the words of the usage text.  A word added to one and not to another would be accepted and then ignored, or refused.

***IT READS modifya AS TEXT AND DOES NOT RUN BASIC.***  That the words are done, in the order, with the summary, is sandbox-gates.py section G
(rows "G: multi - ...").  A green run here is evidence that nothing has deleted or reordered the code that makes those rows true.

--selftest mutates the source in the ways this could plausibly be broken and requires each mutation to be CAUGHT and each mutation to match its
text exactly once: an injection that changed nothing is not a test.
"""

import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SDSYS = os.path.abspath(os.path.join(HERE, os.pardir, "sdsys"))
MD = os.path.join(SDSYS, "gpl.bp", "modifya")
GPL = os.path.join(SDSYS, "gpl.bp")
MESSAGES = os.path.join(SDSYS, "messages")
NEW = ("12719", "12795", "12796", "12798", "12799")


def strip(src):
    """The code: full-line comments and ;* tails removed."""
    out = []
    for ln in src.split("\n"):
        if ln.lstrip().startswith("*"):
            continue
        out.append(re.sub(r"\s*;\*.*$", "", ln))
    return "\n".join(out)


def between(text, a, b):
    i = text.find(a)
    if i < 0:
        return ""
    j = text.find(b, i + len(a))
    return text[i:j] if j >= 0 else text[i:]


def checks(src, msgs):
    c = strip(src)
    rows = []

    def ck(name, ok, detail=""):
        rows.append((name, bool(ok), detail))

    m_words = re.search(r"word\.arr = convert\(',', @fm, '([^']*)'\)", c)
    m_slots = re.search(r"slot\.arr = convert\(',', @fm, '([^']*)'\)", c)
    words = m_words.group(1).split(",") if m_words else []
    slots = m_slots.group(1).split(",") if m_slots else []
    do_action = between(c, "\ndo.action:\n", "\nadd.delete.arm:\n")
    case_words = re.findall(r"case upcase\(action\) = '([A-Z.-]+)'", do_action)   # Windows port: the case lines test upcase(action), and none of them stops
    usage = between(c, "\nshow.usage:\n", "\n   return\n")
    usage_words = []
    for m in re.finditer(r"modify\.account <account> ([^']*)'", usage):
        for w in m.group(1).split("|"):
            w = w.strip()
            if w and "<" not in w and " " not in w:
                usage_words.append(w.upper())
    usage_words = [w for w in usage_words if w not in ("ADD", "DELETE")]

    ck("M0 the word list, the slot list, the case lines and the usage were all found (the null case: nothing to compare passes every row)",
       len(words) > 20 and len(slots) > 20 and len(case_words) > 20 and len(usage_words) > 20,
       "words %d slots %d cases %d usage %d" % (len(words), len(slots), len(case_words), len(usage_words)))
    ck("M1 the word list of validate.actions, the case lines of do.action and the words of the usage are ONE set",
       set(words) == set(case_words) == set(usage_words) and len(words) == len(set(words)),
       "list-only %s, case-only %s, usage-only %s" % (sorted(set(words) - set(case_words)), sorted(set(case_words) - set(words)),
                                                       sorted(set(usage_words) - set(words))))
    pairs_ok = len(words) == len(slots)
    for w, s in zip(words, slots):
        base = re.sub(r"-(ON|OFF)$", "", w)
        mate = [x for x, t in zip(words, slots) if re.sub(r"-(ON|OFF)$", "", x) == base and x != w]
        for x in mate:
            if slots[words.index(x)] != s:
                pairs_ok = False
    ck("M2 the slot list has a slot for every word, the ON and OFF of one gate share one, and the four route words share one",
       pairs_ok and len({s for w, s in zip(words, slots) if w in ("SSH", "API", "BOTH", "NONE")}) == 1, "slots %s" % slots)
    by_slot = {}
    for w, s in zip(words, slots):
        gate = "SUSPEND" if w in ("SUSPENDED", "UNSUSPENDED") else re.sub(r"-(ON|OFF)$", "", w)   # the two suspension words are one gate
        by_slot.setdefault(s, set()).add(gate if s != "R" else "R")
    ck("M2b ...and two different gates never share a slot (a shared slot would call sh-on with os-on a conflict)",
       all(len(v) == 1 for v in by_slot.values()), "%s" % {k: sorted(v) for k, v in by_slot.items() if len(v) > 1})
    ck("M3 the order of execution (the word list): the routes first, the suspension last",
       words[:4] == ["SSH", "API", "BOTH", "NONE"] and words and words[-2:] == ["SUSPENDED", "UNSUSPENDED"], "list %s" % words)

    g = c.find("if (upcase(action) # 'ADD') and (upcase(action) # 'DELETE') then")
    v = c.find("gosub validate.actions")
    r = c.find("gosub run.actions")
    t = c.find("goto add.delete.arm")
    ck("M4 the main flow: the guard (not ADD or DELETE), then validate, then run, then the end of the program, then the goto that skips do.action for ADD / DELETE",
       0 <= g < v < r < t and c.count("gosub validate.actions") == 1 and c.count("gosub run.actions") == 1
       and "goto program.end" in c[r:t] and c.count("goto add.delete.arm") == 1 and c.count("\nadd.delete.arm:\n") == 1,
       "guard %s validate %s run %s goto %s" % (g, v, r, t))

    val = between(c, "\nvalidate.actions:\n", "\nrun.actions:\n")
    stops = [m.start() for m in re.finditer(r"stop sysmsg\(", val)]
    ck("M5 validate.actions refuses with stop: ADD / DELETE 12719, an unknown word 12795, a conflict 12796 (a slot; Linux's files-off with files-write-on is not here)",
       "stop sysmsg(12719, typed.list<i>)" in val and "stop sysmsg(12795, typed.list<i>)" in val
       and "stop sysmsg(12796, downcase(actions<i>), downcase(actions<j>))" in val
       and len(stops) == 3)
    ck("M5b ...each refusal sets the failure code first, and the add / delete test comes before the word lookup, which comes before the conflict test",
       all(val[max(0, s - 60):s].count("@system.return.code = -ER$ARGS") == 1 for s in stops)
       and 0 < val.find("(w = 'ADD')") < val.find("locate w in word.arr<1>") < val.find("if slot.arr<pi> = slot.arr<pj> then"))
    ck("M5c ...and it CHANGES NOTHING: no gosub, no write, no readu, no os.execute and no audit line in it",
       val != "" and not re.search(r"\bgosub\b|\bwrite\b|\breadu\b|os\.execute|K\$AUDIT", re.sub(r"'[^']*'", "''", val)))
    ck("M5d ...the conflict test compares DIFFERENT words only (the same word twice is one action)", "if actions<i> # actions<j> then" in val)

    run = between(c, "\nrun.actions:\n", "\naccount.user:\n")
    ck("M6 run.actions builds its list from word.arr (the fixed order), re-reads the account and clears the code before each action",
       "if want.at<p> then run.list<-1> = word.arr<p>" in run and 0 < run.find("read acc.rec from acc.f, acc.name else null")
       < run.find("@system.return.code = 0") < run.find("gosub do.action"))
    ck("M6b ...a failure leaves the rest to be tried, the summary only for more than one action: 12798 when none failed, else 12799",
       "if n.run > 1 then" in run and re.search(r"if undone\.list = '' then\s+crt sysmsg\(12798, acc\.name, n\.run,", run)
       and "crt sysmsg(12799, acc.name, done.said, change(undone.list, @fm, ', '))" in run
       and run.find("if n.run > 1 then") < run.find("12798") < run.find("12799"))
    ck("M6c ...the code after the run is 0 only when every action was carried out",
       re.search(r"if undone\.list = '' then\s+@system\.return\.code = 0\s+end else\s+@system\.return\.code = -ER\$FAILED\s+end\s+return\s*$", run.rstrip() + "\n") is not None)

    ck("M7 do.action has no stop (a stop would end the run after the first word), and it ends in return; a word it does not know leaves route.done false "
       "(validate.actions has already refused every such word with 12795)",
       do_action != "" and not re.search(r"\bstop\b", do_action)
       and "case 1\n            route.done = @false\n      end case\n      return" in do_action
       and do_action.rstrip().endswith("return"))
    add_arm = c[c.find("\nadd.delete.arm:\n"):]
    ck("M8 ADD and DELETE are as they were: a word after the user name is refused with 12719, and no other path reads extra.word",
       add_arm.count("stop sysmsg(12719, extra.word)") == 1 and c.count("extra.word") == 2, "extra.word lines: %d" % c.count("extra.word"))
    ck("M9 the usage says that several actions may be given together, with an example",
       "may be given together in one command" in usage and "modify.account <account> sh-on os-on voc-on bp-on" in usage)

    texts = {}
    for n in NEW:
        texts[n] = msgs.get(n)
    ck("M10 the five messages exist, end in a newline, and carry their words and their %n",
       all(texts[n] is not None and texts[n].endswith("\n") for n in NEW)
       and texts["12719"] is not None and "add and delete" in texts["12719"] and "%1" in texts["12719"] and "nothing was changed" in texts["12719"]
       and texts["12795"] is not None and "%1" in texts["12795"] and "modify.account" in texts["12795"] and "nothing was changed" in texts["12795"]
       and texts["12796"] is not None and "%1" in texts["12796"] and "%2" in texts["12796"] and "nothing was changed" in texts["12796"]
       and texts["12798"] is not None and all(x in texts["12798"] for x in ("%1", "%2", "%3", "carried out"))
       and texts["12799"] is not None and all(x in texts["12799"] for x in ("%1", "%2", "%3", "NOT every action")),
       "%s" % {n: (texts[n] or "MISSING")[:50] for n in NEW})
    ck("M10b ...no command word in them is in capitals (the lower-case rule)",
       all(texts[n] is not None and "MODIFY.ACCOUNT" not in texts[n] for n in NEW))
    cited = {}
    for fn in sorted(os.listdir(GPL)):
        p = os.path.join(GPL, fn)
        if fn == "modifya" or not os.path.isfile(p):
            continue
        try:
            body = open(p, encoding="latin-1").read()
        except OSError:
            continue
        for n in ("12795", "12796", "12798", "12799"):
            if "sysmsg(%s" % n in body:
                cited.setdefault(n, []).append(fn)
    ck("M10c ...and 12795, 12796, 12798 and 12799 are cited by modifya alone (no other program has taken the number)", not cited, "%s" % cited)
    return rows


def load(path=MD):
    with open(path, encoding="latin-1") as f:
        src = f.read()
    msgs = {}
    for n in NEW:
        p = os.path.join(MESSAGES, n)
        if os.path.isfile(p):
            with open(p, encoding="latin-1") as f:
                msgs[n] = f.read()
    return src, msgs


def report(rows, quiet=False):
    bad = 0
    for name, ok, detail in rows:
        if not ok:
            bad += 1
        if not quiet or not ok:
            print("  [%s] %s%s" % ("PASS" if ok else "FAIL", name, "" if ok else "   <- " + detail))
    return bad


MUTANTS = [
    ("validate.actions is never called", "         gosub validate.actions\n", ""),
    ("run.actions is called before validate.actions", "         gosub validate.actions\n         gosub run.actions\n", "         gosub run.actions\n         gosub validate.actions\n"),
    ("a word is missing from the word list", ",DICT-OFF,SHARED-READ-ON,", ",SHARED-READ-ON,"),
    ("the usage forgets a word", "voc-on | voc-off | bp-on | bp-off | dict-on | dict-off", "voc-on | voc-off | bp-on | dict-on | dict-off"),
    ("sh-on and os-on share a slot", "'R,R,R,R,SH,SH,OS,OS,", "'R,R,R,R,SH,SH,SH,SH,"),
    ("the suspension runs first", "SHARED-WRITE-OFF,SUSPENDED,UNSUSPENDED'", "SHARED-WRITE-OFF,UNSUSPENDED,SUSPENDED'"),
    ("a case of do.action ends in stop", "            gosub os.set\n         case upcase(action) = 'SH-OFF'", "            gosub os.set\n            stop\n         case upcase(action) = 'SH-OFF'"),
    ("the account is not read again before each action", "      read acc.rec from acc.f, acc.name else null\n", ""),
    ("the code is not cleared before each action", "      @system.return.code = 0\n      gosub do.action\n", "      gosub do.action\n"),
    ("the summary is printed for one action too", "   if n.run > 1 then\n", "   if @true then\n"),
    ("the summary always says every action was carried out", "      if undone.list = '' then\n         crt sysmsg(12798", "      if @true then\n         crt sysmsg(12798"),
    ("a failed run ends with code 0", "   end else\n      @system.return.code = -ER$FAILED\n   end\n   return\n", "   end else\n      @system.return.code = 0\n   end\n   return\n"),
    ("an unknown word is not refused", "         stop sysmsg(12795, typed.list<i>)", "         null"),
    ("the slot conflict is not tested", "            if slot.arr<pi> = slot.arr<pj> then", "            if @false then"),
    ("add or delete among other words is accepted", "      if (w = 'ADD') or (w = 'DELETE') then", "      if @false then"),
    ("validate.actions does an action", "   n.words = dcount(actions, @fm)\n   pos.of = ''\n", "   n.words = dcount(actions, @fm)\n   gosub set.suspended\n   pos.of = ''\n"),
    ("the same word twice is a conflict", "         if actions<i> # actions<j> then", "         if @true then"),
    ("DELETE is no longer kept for the old arm", "if (upcase(action) # 'ADD') and (upcase(action) # 'DELETE') then\n         actions = upcase(action)", "if (upcase(action) # 'ADD') then\n         actions = upcase(action)"),
    ("the goto that skips do.action for ADD is gone", "      goto add.delete.arm\n", ""),
    ("the 18 Oct refusal of a second word is back", "      typed.first = action\n", "      typed.first = action\n      call @parser(PARSER$GET.TOKEN, token.type, extra.word, keyword)\n      if token.type # PARSER$END then stop sysmsg(12719, extra.word)\n"),
    ("the usage no longer says several actions may be given", "may be given together in one command", "may be given one at a time"),
]
MSG_MUTANTS = [
    ("message 12798 loses its list", "12798", "%3", "(none)"),
    ("message 12799 does not say NOT", "12799", "NOT every action was carried out", "every action was carried out"),
    ("message 12719 says the old thing", "12719", "add and delete take a user name and stand alone", "modify.account does one action at a time"),
    ("message 12796 loses its second word", "12796", "%2", "that"),
    ("message 12795 has a capital command", "12795", "is not a modify.account action", "is not a MODIFY.ACCOUNT action"),
]


def selftest():
    src, msgs = load()
    base = [n for n, ok, _ in checks(src, msgs) if not ok]
    if base:
        print("REFUSING - the unmutated source already fails: %s" % ", ".join(base), file=sys.stderr)
        return 2
    holes = 0
    print("--- self-test: the unmutated source passes; each mutation must be CAUGHT and match its text once ---")
    for name, old, new in MUTANTS:
        if src.count(old) != 1:
            print("  [FAIL] %s: the text to mutate matches %d times, not once (this test no longer understands the source)" % (name, src.count(old)))
            holes += 1
            continue
        caught = [n for n, ok, _ in checks(src.replace(old, new), msgs) if not ok]
        if caught:
            print("  [pass] %s: caught by %s" % (name, ", ".join(caught[:3])))
        else:
            print("  [FAIL] %s: NOT CAUGHT by any check" % name)
            holes += 1
    for name, n, old, new in MSG_MUTANTS:
        if msgs.get(n, "").count(old) != 1:
            print("  [FAIL] %s: message %s text matches %d times, not once" % (name, n, msgs.get(n, "").count(old)))
            holes += 1
            continue
        m2 = dict(msgs)
        m2[n] = msgs[n].replace(old, new)
        caught = [x for x, ok, _ in checks(src, m2) if not ok]
        if caught:
            print("  [pass] %s: caught by %s" % (name, ", ".join(caught[:3])))
        else:
            print("  [FAIL] %s: NOT CAUGHT by any check" % name)
            holes += 1
    total = len(MUTANTS) + len(MSG_MUTANTS)
    print("\n%d of %d mutants caught, %d missed" % (total - holes, total, holes))
    return 1 if holes else 0


def main():
    if not os.path.isfile(MD):
        print("test-modifya-multi-units: CANNOT RUN - %s is not readable" % MD, file=sys.stderr)
        return 2
    if "--selftest" in sys.argv[1:]:
        return selftest()
    src, msgs = load()
    print("test-modifya-multi-units: %s" % MD)
    rows = checks(src, msgs)
    bad = report(rows)
    print("\ntest-modifya-multi-units: %d checks, %d failed" % (len(rows), bad))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
