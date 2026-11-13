#!/usr/bin/env python3
# test-updatevoc-units.py - UPDATE.ACCOUNTS and the SDSYS account's own VOC (26 Oct 2026, found on a real install by witness-toolgates.py).
#
# The install builds the SDSYS account's VOC from the whole of VOC_TEMPLATE (bbproc); NEWVOC is a smaller set, the VOC of every other account.  Where the two hold the same
# id with different content - tool.gates is the administrator's matrix in one and the holder's read-only page in the other - an UPDATE.ACCOUNTS ALL run from SDSYS (the
# installer runs one on every install) wrote the holder's page over the administrator's.  gpl.bp/login's update.voc now reads VOC_TEMPLATE when the VOC it updates is the
# SDSYS account's own (mode 2 or 4, run by the administrator in the sdsys account) and NEWVOC for every other account.  FREE CHECK: the source read as text; no install, no sd.
#
#   python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/test-updatevoc-units.py
#   python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/test-updatevoc-units.py --selftest      (mutants of login, each must fail its named check)
#
#   V1  the premise: the template and NEWVOC hold tool.gates with DIFFERENT targets ($tool_gates / $tool_mygates); without that difference the rest guards nothing
#   V2  the SDSYS account's own update: update.sdsys.voc is set from `@who = 'sdsys'` AND the administrator test, in the mode 2 / 4 branch, before that branch's `gosub update.voc`
#   V3  the walk over the other accounts clears it (= 0) before ITS `gosub update.voc`, so a registered account never reads VOC_TEMPLATE
#   V4  update.voc names its source: "newvoc" first, "voc_template" only under the flag, and opens `@sdsys:@ds:upd.source`
#   V5  there are exactly two `gosub update.voc` and the flag is assigned before each (an unassigned variable stops the sign-on)
#   V6  a refused write ends the ACCOUNT's update, not the command (26 Oct 26, witness-release-run.sh V10): `on error`, upd.denied, the lock released, exit; nothing more written in that account;
#       both callers say 12988; the walk counts the account as denied, not updated; 12989 follows the count
#   V7  messages 12988 and 12989 exist, say what they must, and are under the message limit
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SD64 = os.path.normpath(os.path.join(HERE, ".."))
LOGIN = os.environ.get("LOGIN", os.path.join(SD64, "sdsys", "gpl.bp", "login"))
NEWVOC = os.environ.get("NEWVOC_TG", os.path.join(SD64, "sdsys", "newvoc", "tool.gates"))
TEMPLATE = os.environ.get("TEMPLATE_TG", os.path.join(SD64, "sdsys", "voc_template", "tool.gates"))
# 12 Nov 26 Windows port - RELEASE_1.1 266: @who was UPPER case on Windows until today, so Linux's `@who = 'sdsys'` was never true here and
# SDSYS's VOC was refreshed from NEWVOC.  @who is lower case now, as Linux, and V2 asks for Linux's form again.  The mutant "flag-who-upper"
# puts back the upper-case literal, the shape of that fault.
WHO = "@who = 'sdsys'"


def read(p):
    with open(p, encoding="latin-1") as f:
        return f.read()


def MSG(n):
    """the text of message n in sdsys/messages, without its line end ('' when there is no such file)"""
    p = os.path.join(os.environ.get("MSGDIR", os.path.join(SD64, "sdsys", "messages")), n)
    return read(p).rstrip("\n") if os.path.isfile(p) else ""


def code_lines(text):
    """(index, line) for the lines that are not whole-line comments"""
    return [(i, l) for i, l in enumerate(text.split("\n")) if not l.lstrip().startswith("*")]


def checks(login, tg_new, tg_tpl):
    rows = []
    lines = login.split("\n")

    def row(name, ok, detail=""):
        rows.append((name, bool(ok), detail))

    row("V1 the premise: tool.gates is %s in the template and %s in NEWVOC" % (tg_tpl.split("\n")[-2:-1] or "?", tg_new.split("\n")[-2:-1] or "?"),
        "$tool_gates" in tg_tpl and "$tool_mygates" in tg_new and "$tool_mygates" not in tg_tpl, "template %r newvoc %r" % (tg_tpl[-40:], tg_new[-40:]))

    gosubs = [i for i, l in code_lines(login) if l.strip() == "gosub update.voc"]
    sets = [i for i, l in code_lines(login) if re.match(r"\s*update\.sdsys\.voc\s*=", l)]
    own = [i for i in sets if WHO in lines[i] and "kernel(K$ADMINISTRATOR,-1)" in lines[i]]
    zero = [i for i in sets if re.match(r"\s*update\.sdsys\.voc\s*=\s*0\b", lines[i])]
    mode24 = [i for i, l in code_lines(login) if "if mode = 2 or mode = 4 then" in l]
    row("V2 update.sdsys.voc is set from @who = 'sdsys' and the administrator test (line %s), after `if mode = 2 or mode = 4` (%s) and before the first gosub (%s)"
        % (own and own[0] + 1, mode24 and mode24[0] + 1, gosubs and gosubs[0] + 1),
        len(own) == 1 and mode24 and gosubs and mode24[0] < own[0] < gosubs[0], "sets %s" % [lines[i].strip() for i in sets])
    row("V3 the walk clears it (line %s) before its own gosub (%s)" % (zero and zero[0] + 1, len(gosubs) > 1 and gosubs[1] + 1),
        len(zero) == 1 and len(gosubs) == 2 and gosubs[0] < zero[0] < gosubs[1] and gosubs[1] - zero[0] <= 2, "zero lines %s, gosubs %s" % (zero, gosubs))

    base = [i for i, l in code_lines(login) if l.strip() == 'upd.source = "newvoc"']
    tpl = [i for i, l in code_lines(login) if re.match(r'\s*if update\.sdsys\.voc then upd\.source = "voc_template"', l)]
    opn = [i for i, l in code_lines(login) if l.strip() == 'openpath @sdsys:@ds:upd.source to sdsys.file else']
    row("V4 update.voc: upd.source = newvoc (%s), voc_template only under the flag (%s), then openpath @sdsys:@ds:upd.source (%s)"
        % (base and base[0] + 1, tpl and tpl[0] + 1, opn and opn[0] + 1),
        len(base) == 1 and len(tpl) == 1 and len(opn) == 1 and base[0] < tpl[0] < opn[0] and 'openpath @sdsys:@ds:"newvoc"' not in login, "")

    row("V5 exactly two `gosub update.voc`, each after an assignment of the flag (%s sets, %s gosubs)" % (len(sets), len(gosubs)),
        len(gosubs) == 2 and len(sets) == 2 and sets[0] < gosubs[0] < sets[1] < gosubs[1], "sets %s gosubs %s" % (sets, gosubs))

    # V6 (26 Oct 26, found on a real install by witness-release-run.sh V10): an UPDATE.ACCOUNTS ALL run by SDSYS cannot write the VOC of a user account that has not switched sdsys on (F6), and the
    # first refused write stopped the whole command with error 3018 and lost the count.  A refused write now ends that ACCOUNT's update, the caller says why (12988), the walk goes on and the number
    # left alone (12989) follows the count (10171).
    uv = [i for i, l in code_lines(login) if l.strip() == "update.voc:"]
    init = [i for i, l in code_lines(login) if re.match(r"\s*upd\.denied = 0\b", l)]
    wr = [i for i, l in code_lines(login) if l.strip() == "write rec to update.voc.f, id on error upd.wrote = @false"]
    body = "\n".join(lines[wr[0]:wr[0] + 12]) if wr else ""
    guard = [i for i, l in code_lines(login) if l.strip().startswith("if upd.denied then return")]
    mods = [i for i, l in code_lines(login) if l.strip() == 'openpath @sdsys:@ds:"newvoc.mods" to mods.f then']
    own = [i for i, l in code_lines(login) if l.strip() == "if upd.denied then display sysmsg(12988, @path : @ds : 'voc')"]
    walk = "\n".join(lines[gosubs[1]:gosubs[1] + 12]) if len(gosubs) == 2 else ""
    summ = [i for i, l in code_lines(login) if l.strip().startswith("if acc.denied then display sysmsg(12989, acc.denied)")]
    ok6 = (len(uv) == 1 and len(init) == 1 and uv[0] < init[0] < (wr[0] if wr else -1)
           and re.search(r"upd\.denied = 1\s*\n\s*release update\.voc\.f, id\s*\n\s*exit\b", body) is not None
           and len(guard) == 2 and len(mods) == 1 and wr and wr[0] < guard[0] < guard[1] < mods[0]
           and len(own) == 1 and "if upd.denied then" in walk and "sysmsg(12988, s)" in walk and "acc.denied += 1" in walk and "acc.updated += 1" in walk
           and re.search(r"acc\.denied \+= 1\s*\n\s*end else\s*\n\s*acc\.updated \+= 1\s*\n\s*end", walk) is not None and len(summ) == 1)
    row("V6 a refused write ends the account's update and not the command: upd.denied starts 0 (%s), the write has an on error (%s) and then upd.denied, release and exit, the return guard (%s) is before the newvoc.mods "
        "writes (%s), both callers say 12988, the walk counts the account as denied and not updated, and 12989 follows the count (%s)" % (init and init[0] + 1, wr and wr[0] + 1, guard and guard[0] + 1, mods and mods[0] + 1, summ and summ[0] + 1),
        ok6, "init %s write %s guard %s mods %s own %s summary %s body %r" % (init, wr, guard, mods, own, summ, body[:160]))
    m1, m2 = MSG("12988"), MSG("12989")
    # 7 Nov 26 Windows port: 12988 (Linux 11983) does not name 'sdsys-on' here - that is Linux's S.103 (the sdsys user's group), not on Windows.
    row("V7 messages 12988 (names the account's VOC and the upgrade) and 12989 (a count) exist and are under the 231-character limit (%d, %d)" % (len(m1), len(m2)),
        "%1" in m1 and "VOC" in m1 and "installer" in m1 and "sdsys-on" not in m1 and "%1" in m2 and 0 < len(m1) < 231 and 0 < len(m2) < 231, "%r %r" % (m1[:60], m2[:60]))
    return rows


def run():
    rows = checks(read(LOGIN), read(NEWVOC), read(TEMPLATE))
    bad = 0
    for name, ok, detail in rows:
        print("  [%s] %s%s" % ("PASS" if ok else "FAIL", name, "" if ok else "   <- " + detail))
        bad += 0 if ok else 1
    print("test-updatevoc-units: %d passed, %d failed" % (len(rows) - bad, bad))
    if not rows:
        print("test-updatevoc-units: NOTHING RAN")
        return 2
    return 1 if bad else 0


def selftest():
    login, tg_new, tg_tpl = read(LOGIN), read(NEWVOC), read(TEMPLATE)
    base = checks(login, tg_new, tg_tpl)
    if not all(ok for _, ok, _ in base):
        print("  [FAIL] the real files do not pass:")
        for name, ok, detail in base:
            if not ok:
                print("    ", name, detail)
        return 1
    print("  [ok] the real files pass")
    caught = missed = 0

    def mutant(name, expect, fn, which="login"):
        nonlocal caught, missed
        l, n, t = login, tg_new, tg_tpl
        if which == "login":
            l = fn(login)
        elif which == "new":
            n = fn(tg_new)
        else:
            t = fn(tg_tpl)
        if (l, n, t) == (login, tg_new, tg_tpl):
            print("  [MISSED] %s: the mutation changed nothing" % name)
            missed += 1
            return
        failing = [name_ for name_, ok, _ in checks(l, n, t) if not ok]
        if any(f.startswith(expect + " ") for f in failing):
            print("  [caught] %s by %s" % (name, expect))
            caught += 1
        else:
            print("  [MISSED] %s: failed %s, wanted %s" % (name, [f[:3] for f in failing], expect))
            missed += 1

    SET = re.search(r"\n(\s*update\.sdsys\.voc = \(" + re.escape(WHO) + r"[^\n]*\n)", login)
    SET = SET.group(1) if SET else "(the flag line was not found)"
    mutant("flag-never-set", "V2", lambda s: s.replace(SET, "", 1))
    mutant("flag-without-administrator", "V2", lambda s: s.replace("update.sdsys.voc = (" + WHO + " and kernel(K$ADMINISTRATOR,-1))", "update.sdsys.voc = (" + WHO + ")", 1))
    mutant("flag-always-on", "V2", lambda s: s.replace(SET, "         update.sdsys.voc = 1\n", 1))
    mutant("flag-who-upper", "V2", lambda s: s.replace("update.sdsys.voc = (" + WHO, "update.sdsys.voc = (@who = 'SDSYS'", 1))
    mutant("flag-set-after-gosub", "V2", lambda s: re.sub(r"(\n\s*update\.sdsys\.voc = \(@who[^\n]*)((?:\n\s*upd\.account[^\n]*)?)(\n\s*gosub update\.voc)", r"\2\3\1", s, count=1))
    mutant("walk-keeps-the-flag", "V3", lambda s: re.sub(r"\n\s*update\.sdsys\.voc = 0 [^\n]*", "", s, count=1))
    mutant("walk-flag-after-gosub", "V3", lambda s: re.sub(r"(\n\s*)update\.sdsys\.voc = 0 [^\n]*((?:\n\s*upd\.account[^\n]*)?)(\n\s*gosub update\.voc)", r"\2\3\1update.sdsys.voc = 0", s, count=1))
    mutant("source-always-newvoc", "V4", lambda s: s.replace('then upd.source = "voc_template"', 'then upd.source = "newvoc"', 1))
    mutant("source-always-template", "V4", lambda s: s.replace('upd.source = "newvoc"\n', 'upd.source = "voc_template"\n', 1))
    mutant("opens-newvoc-directly", "V4", lambda s: s.replace("openpath @sdsys:@ds:upd.source to sdsys.file else", 'openpath @sdsys:@ds:"newvoc" to sdsys.file else', 1))
    mutant("third-gosub", "V5", lambda s: s.replace("      ok = @true\n      return\n   end\n", "      gosub update.voc\n      ok = @true\n      return\n   end\n", 1))
    # V6 (26 Oct 26): a refused write must end the account's update, not the command
    W = "            write rec to update.voc.f, id on error upd.wrote = @false\n"
    mutant("write-without-on-error", "V6", lambda s: s.replace("write rec to update.voc.f, id on error upd.wrote = @false", "write rec to update.voc.f, id", 1))
    mutant("denied-not-set", "V6", lambda s: s.replace("               upd.denied = 1\n", "", 1))
    mutant("lock-not-released", "V6", lambda s: s.replace("               upd.denied = 1\n               release update.voc.f, id\n", "               upd.denied = 1\n", 1))
    mutant("loop-goes-on-after-a-refusal", "V6", lambda s: s.replace("               release update.voc.f, id\n               exit\n", "               release update.voc.f, id\n", 1))
    mutant("mods-written-after-a-refusal", "V6", lambda s: re.sub(r"\n   if upd\.denied then return[^\n]*\n", "\n", s, count=1))
    mutant("denied-never-reset", "V6", lambda s: re.sub(r"\n   upd\.denied = 0[^\n]*\n", "\n", s, count=1))
    mutant("walk-counts-a-denied-account-as-updated", "V6", lambda s: s.replace("                              acc.denied += 1\n                           end else\n                              acc.updated += 1\n                           end",
                                                                               "                              acc.denied += 1\n                           end\n                           acc.updated += 1", 1))
    mutant("walk-does-not-say-why", "V6", lambda s: s.replace("                              display sysmsg(12988, s)\n", "", 1))
    mutant("own-account-does-not-say-why", "V6", lambda s: s.replace("         if upd.denied then display sysmsg(12988, @path : @ds : 'voc')\n", "", 1))
    mutant("summary-gone", "V6", lambda s: re.sub(r"\n               if acc\.denied then display sysmsg\(12989, acc\.denied\)[^\n]*", "", s, count=1))
    mutant("premise-gone-newvoc", "V1", lambda s: s.replace("$tool_mygates", "$tool_gates"), which="new")
    mutant("premise-gone-template", "V1", lambda s: s.replace("$tool_gates", "$tool_mygates"), which="tpl")
    print("selftest: %d of %d mutants caught, %d missed" % (caught, caught + missed, missed))
    return 0 if missed == 0 else 1


if __name__ == "__main__":
    sys.exit(selftest() if "--selftest" in sys.argv else run())
