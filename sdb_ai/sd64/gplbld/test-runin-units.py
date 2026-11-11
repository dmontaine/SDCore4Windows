#!/usr/bin/env python3
"""test-runin-units.py - RUN.IN, the administrator's account-scoped run, as invariants read off the source.

  python C:/Users/Don/Projects/SDCore4Windows/sdb_ai/sd64/gplbld/test-runin-units.py
  python .../test-runin-units.py --selftest

No elevation, no install, no sd.  Exit 0 all checks passed, 1 a check failed, 2 it could not run.  Written 3 Nov 26 for S.96 (owner, 2 Nov 2026: mechanism C, reserved for
sdsys, a fixed command list).

WINDOWS PORT, 10 Nov 26 (from Linux 8fc6b4e1 / d049d8bb at 074397f6; RELEASE_1.1 201).  Message ids are Linux's + 1005.  What differs, and why:
  - five commands: there is no debug (the session's token is elevated; the debugger would run the account's program on it).  R8 and R13 say five.
  - R31 (sandbox-runin.py's mutants still match) and R32 (registered in regress.sh / regress-map.txt) are NOT carried: neither file exists here.  A free guard is
    registered by being a test-*-units file (check-free-tier.ps1), and the sandbox suite has not been ported.
  - R30 looks in the Windows Solo tree instead of Linux Solo's.
  - W1-W7 are Windows-only: the checks made in the account before the command runs (paths inside the account, no trigger), $EXECUTE refused in $BCOMP while
    ri.active is set, $VOC.PARSER reloaded by the safety net, the register read upper case and no EUID change.
  - 10 Nov 26 (from Linux ca137620, S.213; RELEASE_1.1 230): R39-R51 as Linux numbers them, less R47 (Windows' $EXECUTE refusal is W5).  Linux 14070 to 14073 are
    15070 to 15073 here (Linux's second block lands at +1000).  R42 is asked of RUN.IN's own code only: LOGTO out of SDSYS drops the flag here too, and R50 keeps
    LOGTO out of a run.
  - 11 Nov 26 (RELEASE_1.1 231, owner 10 Nov: "should match linux"): R37 and R38 are Linux's, carried (ri.own.words against NEWVOC, 15070); Windows' own comparison with
    SDSYS's VOC (the old W2 first check, W3, message 12565) is gone, and 12568 became 15071 (W5).  --selftest --from=r231 runs the mutants added that day.

***WHAT THIS IS AND WHAT IT IS NOT.*** It reads sdsys/gpl.bp/cproc (int.runin, revert.account, load.account.switches, the abort branch and the /runin/ common), the
VOC record and the messages as TEXT.  IT CANNOT SAY THE VERB REFUSES ANYBODY OR THAT THE SESSION COMES BACK: that is sandbox-runin.py.  What it holds is the order the
design depends on, which a hand edit can break unnoticed:

  the administrator is asked FIRST; the command is rebuilt from checked words and is never the typed text; the list is exactly six commands; every word is a plain word before
  the register is read; what is needed to come back is kept BEFORE anything changes and the flag is set before the first change; the account's LOGIN is not run; the way back clears
  the flag first and puts the six switches back in the order they were kept; and the abort branch puts the session back before it does anything else - because LOGTO SDSYS is
  refused for everybody, an administrator who is not put back stays in the account for the rest of the session.

***AND THE CHECKS ARE THEMSELVES CHECKED.*** --selftest makes the changes that would plausibly break the verb and requires each to be CAUGHT.
"""

import importlib.util
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SD64 = os.path.abspath(os.path.join(HERE, os.pardir))
CPROC = os.path.join(SD64, "sdsys", "gpl.bp", "cproc")
VOCREC = os.path.join(SD64, "sdsys", "voc_template", "run.in")
NEWVOC = os.path.join(SD64, "sdsys", "newvoc")
MESSAGES = os.path.join(SD64, "sdsys", "messages")
SOLO_MESSAGES = os.path.join(SD64, os.pardir, os.pardir, os.pardir, "SDCore4WindowsSolo", "sdb_ai", "sd64", "sdsys", "messages")
BCOMP = os.path.join(SD64, "sdsys", "gpl.bp", "bcomp")
VOCREF = os.path.join(SD64, "sdsys", "gpl.bp", "_voc_ref")
WINDOWS_MESSAGES = [12566, 12567]
RETIRED_MESSAGES = [12565, 12568]                         # 11 Nov 26: replaced by Linux's 14070 and 14071 (15070, 15071 here)
S213_MESSAGES = [15070, 15071, 15072, 15073]              # Linux 14070 (a word that is not SD's own), 14071 ($execute), 14072 (an include or dictionary outside the account), 14073 (LOGTO during a run)

COMMANDS = ["basic", "catalog", "decatalog", "delete.catalog", "compile.dict"]
SWITCHES = ["K$SH", "K$OS.EXEC", "K$SD.ACCOUNTS", "K$NET", "K$SHARED.READ", "K$SHARED.WRITE"]
NEW_MESSAGES = [12452, 12453, 12454, 12181, 12182, 12183, 12246, 12247]
BASIC = os.path.join(SD64, "sdsys", "gpl.bp", "basic")
PARSERH = os.path.join(SD64, "sdsys", "syscom", "parser.h")
KW_NEWVOC = os.path.join(SD64, "sdsys", "newvoc", "no.catalog")
KW_TEMPLATE = os.path.join(SD64, "sdsys", "voc_template", "no.catalog")
KW_NUMBER = 239
NOCATALOG_MESSAGE = 12250
OPARRAY = os.path.join(SD64, "gplsrc", "op_array.c")      # 2 Nov 26: op_common keeps $ / _ named commons to internal programs (R26b)


def code(src):
    """[(line number, stripped code line)] with full-line comments dropped."""
    out = []
    for i, line in enumerate(src.splitlines(), 1):
        s = line.strip()
        if s and not s.startswith("*") and not s.startswith("!"):
            out.append((i, s))
    return out


def section(lines, start, end):
    """The code lines from the one that starts with `start` up to (not including) the one that starts with `end`."""
    a = next((n for n, s in lines if s.startswith(start)), None)
    if a is None:
        return []
    b = next((n for n, s in lines if n > a and s.startswith(end)), None)
    return [(n, s) for n, s in lines if n >= a and (b is None or n < b)]


def first(sec, needle, after=0):
    return next((n for n, s in sec if n > after and needle in s), None)


def last(sec, needle):
    hits = [n for n, s in sec if needle in s]
    return hits[-1] if hits else None


def count(sec, needle):
    return sum(1 for n, s in sec if needle in s)


def checks(src, voc_text, newvoc_names, extra=None):
    out = []

    def ck(name, ok, detail=""):
        out.append((name, bool(ok), detail))

    lines = code(src)
    run = section(lines, "int.runin:", "ri.plain.word:")
    plain = section(lines, "ri.plain.word:", "revert.account:")      # comments are dropped, so the banner between the two labels is not in the way
    rev = section(lines, "revert.account:", "int.if:")
    lsw = section(lines, "load.account.switches:", "int.runin:")
    logto = section(lines, "int.logto:", "load.account.switches:")
    a_n = next((n for n, s in lines if s == "abort.code = n"), None)
    b_n = next((n for n, s in lines if n and a_n and n > a_n and s == "begin case"), None)
    net = [(n, s) for n, s in lines if a_n and b_n and a_n < n < b_n]

    # ---- the VOC record and the verb list -------------------------------------------------------------------------------
    ck("R1 the VOC record is V / IN / 42, in SDSYS's template only (no newvoc record: an ordinary account has no verb)",
       voc_text == "V\nIN\n42\n" and "run.in" not in newvoc_names, "record %r, newvoc has it: %s" % (voc_text, "run.in" in newvoc_names))
    m = re.search(r"on voc\.rec<3> gosub(.*?)\n\s*case dispatch\.mode = \"OS\"", src, re.S)
    labels = []
    if m:
        for part in m.group(1).splitlines():
            t = re.sub(r";\*.*", "", part).strip().rstrip(",").split()
            if t:
                labels.append(t[0])
    ck("R2 int.runin is the 42nd internal verb, after int.logmsg (41)", len(labels) == 42 and labels[40] == "int.logmsg" and labels[41] == "int.runin",
       "%d labels, 41st %s, 42nd %s" % (len(labels), labels[40] if len(labels) > 40 else None, labels[41] if len(labels) > 41 else None))
    ck("R3 int.logto still is the 17th (the numbers of the others did not move)", len(labels) > 16 and labels[16] == "int.logto")

    # ---- the order inside int.runin -------------------------------------------------------------------------------------
    A = {
        "admin": first(run, "if not(kernel(K$ADMINISTRATOR, -1)) then"),
        "nest": first(run, "if ri.active then"),
        "parser": first(run, "call @parser(PARSER$GET.REST"),
        "loop": first(run, "for ri.w = 1 to ri.nwords"),
        "nocat": first(run, "if ri.cmd = 'basic' then ri.sentence := ' no.catalog'"),
        "bad": first(run, "if ri.bad # '' then"),
        "plain": first(run, "gosub ri.plain.word"),
        "sdsys": first(run, "if ri.acct = 'sdsys' then"),
        "register": first(run, "openpath @sdsys:@ds:'accounts' to acc.f"),
        "own": first(run, "gosub ri.own.words"),
        "save_path": first(run, "ri.path = ospath('', os$cwd)"),
        "save_sw": first(run, "ri.sw = kernel(K$SH, -1)"),
        "active": first(run, "ri.active = 1"),
        "begin": first(run, "'run.in begin account='"),
        "cd": first(run, "if not(ospath(acc.rec, OS$CD)) then"),
        "switches": first(run, "gosub load.account.switches"),
        "filechk": first(run, "if ri.n.names = 2 then"),
        "proc": first(run, "gosub proc.sentence"),
        "revert": last(run, "gosub revert.account"),
        "end": last(run, "'run.in end account=' : ri.acct)"),
    }
    order = ["admin", "nest", "parser", "loop", "nocat", "sdsys", "register", "own", "save_path", "save_sw", "active", "begin", "cd", "switches", "filechk", "proc", "revert", "end"]
    missing = [k for k in order if A[k] is None]
    ck("R4 every anchor of int.runin is there", not missing, "missing " + ", ".join(missing))
    ck("R5 the order: administrator first, then the nest test, the words, the register, THEN what is kept to come back, THEN the flag, THEN the first change",
       not missing and all(A[order[i]] < A[order[i + 1]] for i in range(len(order) - 1)),
       " ".join("%s=%s" % (k, A[k]) for k in order))
    ck("R6 the plain-word check runs inside the word loop, before the register is read",
       A["loop"] is not None and A["plain"] is not None and A["register"] is not None and A["loop"] < A["plain"] < A["register"])
    cds = [n for n, s in run if "OS$CD" in s]
    ck("R7 nothing changes the directory before the flag is set (every OS$CD in the verb is after ri.active = 1)",
       A["active"] is not None and cds and all(n > A["active"] for n in cds), "cd lines %s active %s" % (cds, A["active"]))

    # ---- the list, the sentence and the words ---------------------------------------------------------------------------
    cases = re.findall(r"case ri\.cmd = '([^']+)'", "\n".join(s for n, s in run))
    ck("R8 the commands are exactly basic, catalog, decatalog, delete.catalog and compile.dict (no debug on Windows)", sorted(cases) == sorted(COMMANDS), "found %s" % cases)
    assigns = [s for n, s in run if re.match(r"new\.sentence\s*=", s)]
    ck("R9 the only sentence the verb runs is the one built from checked words (new.sentence = ri.sentence, once)", assigns == ["new.sentence = ri.sentence"], "%s" % assigns)
    sent = re.findall(r"(ri\.sentence\s*:?=[^\n]*)", "\n".join(s for n, s in run))
    ck("R10 ri.sentence starts as the command word and grows only by checked words", sent == ["ri.sentence = ri.cmd", "ri.sentence := ' ' : ri.word", "ri.sentence := ' no.catalog'"], "%s" % sent)
    ck("R11 the verb never executes text (no execute, no ri.rest as a sentence, one proc.sentence)",
       not any(re.match(r"execute\b", s) for n, s in run) and count(run, "gosub proc.sentence") == 1 and not any("sentence" in s and "ri.rest" in s for n, s in run if re.match(r"new\.sentence", s)))
    ck("R12 the account's LOGIN and ON.LOGTO are NOT run, and no group test stands in for the administrator test",
       not any(re.search(r"LOGIN|ON\.LOGTO|is_grp_member", s) for n, s in run), "")
    opts = [o for o in re.findall(r"ri\.opts = '([^']*)'", "\n".join(s for n, s in run)) if o]
    ck("R13 the options are debugging and no.query for basic, local and no.query for catalog, local for delete.catalog, and none else",
       sorted(opts) == sorted(["debugging no.query", "local no.query", "local"]), "found %s" % opts)
    kw = re.search(r"ri\.kwords = '([^']*)'", "\n".join(s for n, s in run))
    kwords = set(kw.group(1).split()) if kw else set()
    ck("R14 the keyword list holds every option word and the words the verbs read as options", {"local", "global", "pcode", "no.query", "no.catalog", "debugging"} <= kwords, "%s" % sorted(kwords))
    ptxt = "\n".join(s for n, s in plain)
    ck("R15 a plain word: a letter or digit first, then a-z 0-9 . _ - only, at most 64, and not a keyword",
       "index('abcdefghijklmnopqrstuvwxyz0123456789', ri.word[1, 1], 1)" in ptxt and "index('abcdefghijklmnopqrstuvwxyz0123456789._-', ri.word[ri.i, 1], 1)" in ptxt
       and "len(ri.word) > 64" in ptxt and "ri.kwords" in ptxt)
    ck("R16 the account is checked as a word and refused when it is sdsys, and the register record gives the path (never the typed text)",
       "acc.rec = parse.pathname.tokens(acc.record<ACC$PATH>)" in "\n".join(s for n, s in run) and "if acc.record<ACC$PATH> = '' then" in "\n".join(s for n, s in run))

    # ---- the way back ---------------------------------------------------------------------------------------------------
    ck("R17 revert.account clears the flag FIRST (a failure below it must not run it twice)", bool(rev) and rev[0][1] == "revert.account:" and rev[1][1] == "ri.active = 0",
       "%s" % (rev[:2],))
    rtxt = "\n".join(s for n, s in rev)
    all_r = re.findall(r"void kernel\((K\$[A-Z.]+),\s+ri\.sw<(\d+)>\)", rtxt)
    order_r = [(k, i) for k, i in all_r if k in SWITCHES]        # 10 Nov 26 (S.213, as Linux): the edit gates and the flag are ri.sw<7..10>, held by R44
    ck("R18 it restores the six switches from ri.sw in the order they were kept", [k for k, i in order_r] == SWITCHES and [i for k, i in order_r] == list("123456"), "%s" % order_r)
    kept = re.findall(r"kernel\((K\$[A-Z.]+), -1\)", next((s for n, s in run if s.startswith("ri.sw = ")), ""))
    ck("R19 ... and that is the order int.runin kept them in", kept == SWITCHES, "%s" % kept)
    loaded = re.findall(r"void kernel\((K\$[A-Z.]+),", "\n".join(s for n, s in lsw))
    ck("R20 load.account.switches sets the same six, once, in the same order", loaded == SWITCHES, "%s" % loaded)
    ck("R21 the way back is fatal when it cannot get back (return to abort.cproc twice) and puts the name, the VOC, the catalogue and the object cache back",
       count(rev, "return to abort.cproc") == 2 and "void kernel(K$SET.ACCOUNT, who)" in rtxt and "voc = new.voc ; new.voc = 0" in rtxt and "gosub find.private.catalogue" in rtxt
       and "kernel(K$INVALIDATE.OBJECT, 0)" in rtxt and "account.path = ri.account.path" in rtxt and "who = ri.who" in rtxt)
    ltxt = "\n".join(s for n, s in logto)
    ck("R22 int.logto uses load.account.switches (once) and no longer carries the six statements itself",
       ltxt.count("gosub load.account.switches") == 1 and not re.search(r"void kernel\(K\$(SH|OS\.EXEC|SD\.ACCOUNTS|NET|SHARED\.READ|SHARED\.WRITE),", ltxt))

    # ---- the safety net -------------------------------------------------------------------------------------------------
    ntxt = "\n".join(s for n, s in net)
    ck("R23 the abort branch puts the session back BEFORE the case on the abort cause (the block sits between 'abort.code = n' and 'begin case')",
       bool(net) and "if ri.active then" in ntxt and "gosub revert.account" in ntxt, "%d lines between" % len(net))
    ck("R24 ... says so (12247 with the account) and audits it as run.in revert ... reason=abort",
       "display sysmsg(12247, ri.account)" in ntxt and "'run.in revert account=' : ri.account : ' reason=abort'" in ntxt)
    ck("R25 the test is the flag and nothing else, and it comes before the first 'case' of the branch",
       a_n is not None and b_n is not None and next((n for n, s in lines if n > a_n and s.startswith("case ")), 10 ** 9) > b_n)
    commons = [s for n, s in lines if re.match(r"common /\$?runin/", s)]
    ck("R26 the common /$runin/ is declared once, ri.active first, with everything the way back needs - and its name starts with $ (2 Nov 26: a plain /runin/ "
       "could be declared by any program, which then set ri.sw and ABORTed into revert.account with every gate on)",
       len(commons) == 1 and re.match(r"common /\$runin/ ri\.active,", commons[0]) and all(v in commons[0] for v in ("ri.path", "ri.account.path", "ri.who", "ri.sw", "ri.account")),
       "%s" % commons)
    opa = (extra or {}).get("op_array.c", "")
    body = opa[opa.find("void op_common()"):opa.find("void op_delcom()")]
    chk = body.find("k_error(sysmsg(12603))")
    ck("R26b the kernel refuses a $ or _ named common to a program that is not internal (op_common, message 12603), before the block is looked up or made",
       chk > 0 and re.search(r"\(\*block_name == '\$'\)\s*\|\|\s*\(\*block_name == '_'\)", body[:chk]) is not None and "!(process.program.flags & HDR_INTERNAL)" in body[:chk]
       and chk < body.find("process.named_common") and os.path.exists(os.path.join(MESSAGES, "12603")), "check at %d" % chk)

    # ---- audit and messages ---------------------------------------------------------------------------------------------
    audits = re.findall(r"K\$AUDIT, '([^']*)'", "\n".join(s for n, s in run + rev + net))
    bad = [a for a in audits if not a.startswith("run.in ") and not a.startswith("logto revert account=") or re.search(r"[A-Z]", a.split("=")[0])]
    ck("R27 every audit line the verb writes starts with run.in (or LOGTO's own revert line) and has no capital before its first =", audits and not bad, "%s" % bad)
    cited = sorted(set(int(x) for x in re.findall(r"sysmsg\((\d+)", "\n".join(s for n, s in run + rev + net))))
    absent = [n for n in cited if not os.path.isfile(os.path.join(MESSAGES, str(n)))]
    ck("R28 every message the verb cites is a file", cited and not absent, "cited %s, absent %s" % (cited, absent))
    ck("R29 the eight new messages exist and are cited", all(os.path.isfile(os.path.join(MESSAGES, str(n))) for n in NEW_MESSAGES) and all(n in cited for n in NEW_MESSAGES if n != 12247) and 12247 in cited,
       "cited %s" % cited)
    if os.path.isdir(SOLO_MESSAGES):
        clash = [n for n in NEW_MESSAGES if os.path.exists(os.path.join(SOLO_MESSAGES, str(n)))]
        ck("R30 none of the eight numbers (nor 12250) is used in Solo (a later carry cannot collide)", not clash and not os.path.exists(os.path.join(SOLO_MESSAGES, str(NOCATALOG_MESSAGE))), "in Solo: %s" % clash)

    # ---- the NO.CATALOG option (owner, 3 Nov 26: "compile option"): run.in basic always gives it, basic honours it at the one place the catalogue step runs ----------
    ck("R33 no option list lets a person give no.catalog (it is added by the verb, after the typed words are checked, and only to basic)",
       not any("no.catalog" in o for o in opts) and A["nocat"] is not None and A["bad"] is not None and A["loop"] < A["bad"] < A["nocat"] < A["register"],
       "loop %s bad %s nocat %s register %s" % (A["loop"], A["bad"], A["nocat"], A["register"]))
    if extra is not None:
        bl = code(extra["basic"])
        btxt = "\n".join(s for n, s in bl)
        init = first(bl, "no.catalog = @false")
        case_ = first(bl, "case keyword = KW$NO.CATALOG")
        setit = first(bl, "no.catalog = @true", case_ or 0)
        skip = first(bl, "if catalogue.name # '' and no.catalog then")
        msg = first(bl, "display sysmsg(12250, record.name)", skip or 0)
        els = first(bl, "end else if catalogue.name # '' then", msg or 0)
        exe = first(bl, "execute cat.cmd", els or 0)
        ck("R34 basic reads the option (KW$NO.CATALOG sets no.catalog, which starts false) and the catalogue step is run only in the branch where it is not set: the skip, its message, THEN the old test, "
           "and the one 'execute cat.cmd' after them",
           all(x is not None for x in (init, case_, setit, skip, msg, els, exe)) and init < case_ < setit < skip < msg < els < exe and btxt.count("execute cat.cmd") == 1,
           "init %s case %s set %s skip %s msg %s else %s exec %s" % (init, case_, setit, skip, msg, els, exe))
        ph = [(m.group(1), m.group(2)) for m in re.finditer(r"^\$define\s+(KW\$[A-Z.]+)\s+(\d+)", extra["parser.h"], re.M)]
        knums = [n for k, n in ph if k == "KW$NO.CATALOG"]
        ck("R35 the keyword is the same number in parser.h, in the newvoc record (K description, then the number) and in the template record (K, the number), and no other KW$ has it",
           knums == [str(KW_NUMBER)] and sum(1 for k, n in ph if n == str(KW_NUMBER)) == 1
           and extra["kw.newvoc"].split("\n")[:2][1:] == [str(KW_NUMBER)] and extra["kw.newvoc"].upper().startswith("K")
           and extra["kw.template"] == "K\n%d\n" % KW_NUMBER, "parser.h %s" % knums)
        mp = os.path.join(MESSAGES, str(NOCATALOG_MESSAGE))
        mt = open(mp, encoding="utf-8").read() if os.path.isfile(mp) else ""
        ck("R36 message 12250 exists, takes the program name and names the option", "%1" in mt and "no.catalog" in mt, repr(mt))

    # ---- Windows only (10 Nov 26, RELEASE_1.1 201): the session's own token is elevated, so the account's own code and pointers are kept out of the run ----------
    rtxt_run = "\n".join(s for n, s in run)
    g_chk = first(run, "gosub ri.windows.checks")
    g_cat = first(run, "gosub find.private.catalogue")
    ck("W1 the Windows checks run in the account, after its private catalogue is found and before the command, and the command runs only when they pass",
       None not in (g_chk, g_cat, A["proc"]) and g_cat < g_chk < A["proc"] and "if ri.file.ok and ri.why = '' then" in rtxt_run, "catalogue %s checks %s proc %s" % (g_cat, g_chk, A["proc"]))
    ck("W2 the checks: every path written is inside the account (12567), no file opened has a trigger (12566); the words are NOT compared here with SDSYS's VOC any more "
       "(ri.own.words asks, 11 Nov 26)",
       all(x in ptxt for x in ("gosub ri.path.inside", "fileinfo(voc, FL$TRIGGER)", "fileinfo(ri.tf, FL$TRIGGER)", "ri.p = private.catalogue", "sysmsg(12567", "sysmsg(12566"))
       and not any(x in "\n".join(s for n, s in lines) for x in ("ri.voc.key", "ri.vkeys", "ri.vwords", "sysmsg(12565")))
    ck("W4 a path inside the account: relative, no leading slash or backslash, no @ token, no drive, no '..'; and the longest part of it that exists is inside by the kernel's geometry (K$PATH.IN)",
       "if ri.q[1, 1] = '/' or ri.q[1, 1] = '@' or index(ri.q, ':', 1) or index('/' : ri.q : '/', '/../', 1) then" in ptxt and "ri.q = change(ri.p, '\\', '/')" in ptxt
       and "if not(kernel(K$PATH.IN, account.path : @fm : ri.chk)) then ri.ok = @false" in ptxt and "while ri.chk # '' and not(ospath(ri.chk, OS$EXISTS))" in ptxt)
    if extra is not None and "bcomp" in extra:
        bc = code(extra["bcomp"])
        bcom = [s for n, s in bc if re.match(r"common /\$?runin/", s)]
        ccom = [s for n, s in lines if re.match(r"common /\$?runin/", s)]
        b_if = first(bc, "if ri.active then")
        b_msg = first(bc, "err.msg = sysmsg(15071)", b_if or 0)
        b_exe = first(bc, "execute token.string")
        ck("W5 $BCOMP joins /$runin/ with the command processor's six names and refuses $EXECUTE while ri.active is set (15071, Linux 14071, before the execute); the old 12568 is gone",
           bcom == ccom and len(bcom) == 1 and None not in (b_if, b_msg, b_exe) and b_if < b_msg < b_exe and b_exe - b_if < 8 and not any("12568" in s for n, s in bc),
           "common %s, if %s msg %s execute %s" % (bcom, b_if, b_msg, b_exe))
    r_n = first(net, "gosub revert.account")
    v_n = first(net, "gosub get.voc.parser.rec")
    ck("W6 the safety net reads $VOC.PARSER again after the way back (it was read from the account the command visited)", None not in (r_n, v_n) and r_n < v_n)
    ck("W7 the register is read upper case, the session's name is the register's, and nothing changes the effective user",
       "read acc.record from acc.f, upcase(ri.acct) else acc.record = ''" in rtxt_run and "who = upcase(ri.acct)" in rtxt_run
       and "EUID" not in rtxt_run.upper() and "EUID" not in "\n".join(s for n, s in rev).upper())
    ck("W8 the Windows-only messages exist, and the two Linux replaced (12565, 12568) are gone",
       all(os.path.isfile(os.path.join(MESSAGES, str(n))) for n in WINDOWS_MESSAGES) and not any(os.path.exists(os.path.join(MESSAGES, str(n))) for n in RETIRED_MESSAGES))

    # ---- S.213 (10 Nov 26, from Linux ca137620; RELEASE_1.1 230): the command does not run as the administrator, and its reads stay in the account ----------
    # ---- 11 Nov 26 (RELEASE_1.1 231, from Linux ca137620): SD's own words, R37 and R38 as Linux's, with Windows' labels -------------------------------------------
    own = section(lines, "ri.own.words:", "ri.windows.checks:")
    otxt = "\n".join(s for n, s in own)
    ow = A["own"]
    ow_ref = first(run, "display sysmsg(15070, ri.bad[1, 40], ri.acct)", ow or 0)
    ow_aud = first(run, "'run.in refused account=' : ri.acct : ' word=' : ri.bad[1, 40] : ' reason=' : ri.why", ow or 0)
    ow_ret = first(run, "return", ow_aud or 0)
    ck("R37 (A) the words are asked after the register is read and BEFORE anything is kept or changed; a failure says so (15070, the word and the account), is audited "
       "with word= and reason=, and returns before the flag is set",
       None not in (ow, ow_ref, ow_aud, ow_ret, A["register"], A["save_path"], A["active"]) and A["register"] < ow < ow_ref < ow_aud < ow_ret < A["save_path"] < A["active"]
       and count(run, "gosub ri.own.words") == 1, "own %s refuse %s audit %s return %s save %s" % (ow, ow_ref, ow_aud, ow_ret, A["save_path"]))
    ck("R38 (A) ri.own.words reads the SHIPPED record (NEWVOC of the system directory) and the ACCOUNT's VOC by the register's path, for the command word and every word after "
       "the names, and compares the type letter and every field after the first; a file it cannot open and a record that is missing are refusals",
       "openpath @sdsys:@ds:'newvoc' to ri.nv.f then ri.nv.open = @true" in otxt and "openpath acc.rec:@ds:'voc' to ri.av.f then ri.av.open = @true" in otxt
       and "if (ri.w = 1 or ri.w > 1 + ri.n.names) and ri.bad = '' then" in otxt and "ri.word = field(ri.sentence, ' ', ri.w)" in otxt
       and "read ri.own from ri.nv.f, ri.word else ri.own = ''" in otxt and "read ri.vrec from ri.av.f, ri.word else ri.vrec = ''" in otxt
       and "case upcase(ri.vrec[1, 1]) # upcase(ri.own[1, 1])" in otxt and "case field(ri.vrec, @fm, 2, 9999) # field(ri.own, @fm, 2, 9999)" in otxt
       and "case ri.own = ''" in otxt and "case ri.vrec = ''" in otxt and "case not(ri.nv.open)" in otxt and "case not(ri.av.open)" in otxt
       and otxt.count("ri.bad = ri.") == 6 and not re.search(r"\bexecute\b|proc\.sentence|write ", otxt), "")
    k7 = first(run, "ri.sw<7> = kernel(K$VOC.EDIT, -1)")
    k10 = first(run, "ri.sw<10> = kernel(K$ADMINISTRATOR, -1)")
    k7s = next((s for n, s in run if n == k7), "")
    ck("R39 (B) the three edit gates and the administrator flag are kept in ri.sw<7> to ri.sw<10>, after the six and before the flag ri.active is set",
       None not in (k7, k10, A["save_sw"], A["active"]) and A["save_sw"] < k7 <= k10 < A["active"] and "ri.sw<8> = kernel(K$BP.EDIT, -1)" in k7s and "ri.sw<9> = kernel(K$DICT.EDIT, -1)" in k7s,
       "save_sw %s k7 %s k10 %s active %s" % (A["save_sw"], k7, k10, A["active"]))
    nar = [s for n, s in section(lines, "ri.narrow:", "ri.plain.word:")]
    want_nar = ["ri.narrow:", "void kernel(K$VOC.EDIT,  0)",
                "void kernel(K$BP.EDIT,   (ri.cmd = 'basic') or (ri.cmd = 'catalog') or (ri.cmd = 'decatalog') or (ri.cmd = 'delete.catalog'))",
                "void kernel(K$DICT.EDIT, (ri.cmd = 'compile.dict'))", "void kernel(K$SH, 0)", "void kernel(K$OS.EXEC, 0)", "void kernel(K$ADMINISTRATOR, 0)", "return"]
    ck("R40 (B) ri.narrow is exactly: voc-edit off, bp-edit on for basic / catalog / decatalog / delete.catalog only, dict-edit on for compile.dict only, SH off, OS.EXECUTE off, the flag off LAST",
       nar == want_nar, "%s" % nar)
    g_nar = first(run, "gosub ri.narrow")
    after_nar = next((n for n, s in run if g_nar is not None and n > g_nar), None)
    ck("R41 (B) the flag is dropped once, on the line before the command runs (gosub ri.narrow, then gosub proc.sentence), after the account's switches were loaded",
       None not in (g_nar, A["proc"], A["switches"]) and count(lines, "gosub ri.narrow") == 1 and after_nar == A["proc"] and A["switches"] < g_nar,
       "narrow %s next %s proc %s switches %s" % (g_nar, after_nar, A["proc"], A["switches"]))
    sets_run = [s for n, s in run + rev if re.search(r"kernel\(K\$ADMINISTRATOR,\s*(?!\s|-1\))", s)]
    ck("R42 (B) in RUN.IN's own code the flag is set exactly twice: off in ri.narrow, back from ri.sw<10> in revert.account; it is never turned ON there",
       sorted(sets_run) == sorted(["void kernel(K$ADMINISTRATOR, 0)", "void kernel(K$ADMINISTRATOR, ri.sw<10>)   ;* 10 Nov 26, S.213: LAST - see the note above"])
       and not any("K$ADMINISTRATOR, 1" in s for n, s in run + rev), "%s" % sets_run)
    lsw_txt = "\n".join(s for n, s in lsw)
    ck("R43 (B) load.account.switches never turns SH or OS.EXECUTE on while a run is in progress (not(ri.active) and ...)",
       "void kernel(K$SH,      not(ri.active) and (upcase(trim(acc.record<ACC$SH>)) = 'YES'))" in lsw_txt
       and "void kernel(K$OS.EXEC, not(ri.active) and (upcase(trim(acc.record<ACC$OS.EXEC>)) = 'YES'))" in lsw_txt)
    rv = [s for n, s in rev]
    i_cd = next((i for i, s in enumerate(rv) if "OS$CD" in s), None)
    i_flag = next((i for i, s in enumerate(rv) if "K$ADMINISTRATOR, ri.sw<10>" in s), None)
    i_sw6 = next((i for i, s in enumerate(rv) if "K$SHARED.WRITE, ri.sw<6>" in s), None)
    i_aud = next((i for i, s in enumerate(rv) if "'logto revert account='" in s), None)
    ck("R44 (B) the way back fails closed: the three edit gates go back right after ri.active is cleared and before the first OS$CD; the flag goes back LAST, after the six switches",
       len(rv) > 4 and rv[1:5] == ["ri.active = 0", "void kernel(K$VOC.EDIT,  ri.sw<7>)", "void kernel(K$BP.EDIT,   ri.sw<8>)", "void kernel(K$DICT.EDIT, ri.sw<9>)"]
       and None not in (i_cd, i_flag, i_sw6, i_aud) and 4 < i_cd and i_sw6 < i_flag < i_aud, "%s / cd %s sw6 %s flag %s" % (rv[:5], i_cd, i_sw6, i_flag))
    i_if = next((i for i, (n, s) in enumerate(net) if s == "if ri.active then"), None)
    ck("R45 (B) the abort branch calls revert.account FIRST inside its test of the flag (nothing runs between), so an aborted command gets the same way back",
       i_if is not None and i_if + 1 < len(net) and net[i_if + 1][1] == "gosub revert.account")
    lg_if = first(logto, "if ri.active then")
    lg_msg = first(logto, "display sysmsg(15073, ri.account)")
    lg_aud = first(logto, "' reason=logto')")
    lg_name = first(logto, "display sysmsg(5160)")
    lg_after = [n for n, s in logto if lg_if is not None and n > lg_if and ("sdsys" in s.lower() or "ON.LOGTO" in s.upper() or "OS$CD" in s)]
    ck("R50 LOGTO is refused while a run is in progress (15073, audited reason=logto): right after the account name is read, before the sdsys test, ON.LOGTO and any directory change",
       None not in (lg_if, lg_msg, lg_aud, lg_name) and lg_name < lg_if < lg_msg < lg_aud and lg_aud - lg_if <= 4 and lg_after and min(lg_after) > lg_aud
       and first(logto, "unwinding = 2", lg_aud) is not None, "name %s if %s msg %s audit %s later %s" % (lg_name, lg_if, lg_msg, lg_aud, lg_after[:1]))
    if extra is not None and "bcomp" in extra and "_voc_ref" in extra:
        bc = code(extra["bcomp"])
        ro = [s for n, s in section(bc, "ri.outside:", "get.token:")]
        n_calls = count(bc, "gosub ri.outside")
        pre = [bc[i - 1][1] for i, (n, s) in enumerate(bc) if s == "gosub ri.outside" and i > 0]
        oi = section(bc, "open.include.record:", "ri.outside:")
        oi_chk = first(oi, "ri.chk.path = fileinfo(incl.file, FL$PATH)")
        oi_lvl = first(oi, "level += 1")
        dtxt = "\n".join(s for n, s in bc)
        ck("R48 (C) an include file, the $dict dictionary and a FILE statement's dictionary are each asked of ri.outside (three calls, each just after the file's path is read), "
           "which refuses only under ri.active a file outside @path and SYSCOM (15072); the include is asked before it is read, and dict.f takes the dictionary only when it passed",
           n_calls == 3 and all(p.startswith("ri.chk.path = fileinfo(") and p.endswith("FL$PATH)") for p in pre)
           and ro == ["ri.outside:", "ri.out = @false", "if ri.active then", "if not(kernel(K$PATH.IN, @path : @fm : ri.chk.path)) then",
                      "if not(kernel(K$PATH.IN, @sdsys : @ds : 'syscom' : @fm : ri.chk.path : @ds : 'x')) then ri.out = @true", "end", "end", "return"]
           and None not in (oi_chk, oi_lvl) and oi_chk < oi_lvl and dtxt.count("sysmsg(15072") == 3 and "end else\ndict.f = ri.dict.f" in dtxt,
           "calls %d, before %s, include check %s level %s, outside %s" % (n_calls, pre, oi_chk, oi_lvl, ro))
        vr = code(extra["_voc_ref"])
        vcom = [s for n, s in vr if re.match(r"common /\$?runin/", s)]
        ccom2 = [s for n, s in lines if re.match(r"common /\$?runin/", s)]
        q = section(vr, "parse.as.q.pointer:", "check.q.hop:")
        q_reg = first(q, "q.registered = @true")
        q_if = first(q, "if ri.active then", q_reg or 0)
        q_test = first(q, "if not(q.registered and downcase(q.named) = ri.account) then", q_if or 0)
        q_perm = first(q, "set.status ER$PERM", q_test or 0)
        q_hop = first(q, "gosub check.q.hop")
        ck("R51 _voc_ref joins /$runin/ as CPROC does, and in the Q branch, after the register is read and BEFORE check.q.hop, a run lets a Q-pointer lead only into the run's own account (ER$PERM)",
           vcom == ccom2 and len(vcom) == 1 and None not in (q_reg, q_if, q_test, q_perm, q_hop) and q_reg < q_if < q_test < q_perm < q_hop and q_test - q_if == 1,
           "common %s, reg %s if %s test %s perm %s hop %s" % (vcom, q_reg, q_if, q_test, q_perm, q_hop))
        m70 = extra.get("msg15070", "")
        m71 = extra.get("msg15071", "")
        m72 = extra.get("msg15072", "")
        m73 = extra.get("msg15073", "")
        ck("R49 the four S.213 messages exist: 15070 takes the word and the account (%1, %2) and says the entry is not SD's own, 15071 names $execute and run.in, 15072 takes the file "
           "(%1) and names run.in and syscom, 15073 takes the account (%1) and names logto and run.in; all end in a newline",
           "%1" in m70 and "%2" in m70 and "not SD's own entry in the VOC" in m70 and m70.endswith("\n") and "$execute" in m71 and "run.in" in m71 and m71.endswith("\n")
           and "%1" in m72 and "run.in" in m72 and "syscom" in m72 and m72.endswith("\n") and "%1" in m73 and "logto" in m73 and "run.in" in m73 and m73.endswith("\n"),
           "%r / %r / %r / %r" % (m70, m71, m72, m73))
    return out


# R31 (sandbox-runin.py's mutants) and R32 (regress.sh registration) are Linux's and are not carried: neither file exists on Windows (see the header).


def load():
    with open(CPROC, encoding="utf-8", errors="replace") as f:
        src = f.read()
    with open(VOCREC, encoding="utf-8") as f:
        voc = f.read()
    names = set(os.listdir(NEWVOC)) if os.path.isdir(NEWVOC) else set()
    extra = {}
    for key, path in (("basic", BASIC), ("parser.h", PARSERH), ("kw.newvoc", KW_NEWVOC), ("kw.template", KW_TEMPLATE), ("op_array.c", OPARRAY), ("bcomp", BCOMP),
                      ("_voc_ref", VOCREF), ("msg15070", os.path.join(MESSAGES, "15070")), ("msg15071", os.path.join(MESSAGES, "15071")),
                      ("msg15072", os.path.join(MESSAGES, "15072")), ("msg15073", os.path.join(MESSAGES, "15073"))):
        with open(path, encoding="utf-8", errors="replace") as f:
            extra[key] = f.read()
    return src, voc, names, extra


def run_checks(src, voc, names, extra):
    return checks(src, voc, names, extra)


# Each mutant: (name, kind, old, new).  kind "cproc" edits the source text, "voc" the record text.
MUTANTS = [
    ("admin test off", "cproc", "   if not(kernel(K$ADMINISTRATOR, -1)) then\n      display sysmsg(2001)   ;* Command requires administrator privileges\n      void kernel(K$AUDIT, 'run.in refused reason=not the administrator')",
     "   if 0 then\n      display sysmsg(2001)   ;* Command requires administrator privileges\n      void kernel(K$AUDIT, 'run.in refused reason=not the administrator')"),
    ("nest test off", "cproc", "   if ri.active then\n      display sysmsg(12183)", "   if 0 then\n      display sysmsg(12183)"),
    ("a sixth command: sh", "cproc", "      case ri.cmd = 'compile.dict'\n         ri.n.names = 2\n", "      case ri.cmd = 'sh'\n         ri.n.names = 1\n      case ri.cmd = 'compile.dict'\n         ri.n.names = 2\n"),
    ("debug is back on the list", "cproc", "      case ri.cmd = 'compile.dict'\n         ri.n.names = 2\n", "      case ri.cmd = 'debug'\n         ri.n.names = 2\n      case ri.cmd = 'compile.dict'\n         ri.n.names = 2\n"),
    ("the typed text is run", "cproc", "      new.sentence = ri.sentence\n", "      new.sentence = ri.rest\n"),
    ("the flag is not cleared first", "cproc", "revert.account:\n   ri.active = 0\n", "revert.account:\n"),
    ("the switches are restored in another order", "cproc", "   void kernel(K$SH,          ri.sw<1>)\n", "   void kernel(K$SH,          ri.sw<2>)\n"),
    ("the safety net is off", "cproc", "         if ri.active then\n            gosub revert.account\n            display sysmsg(12247, ri.account)",
     "         if 0 then\n            gosub revert.account\n            display sysmsg(12247, ri.account)"),
    ("the flag is never set", "cproc", "   ri.active = 1\n   void kernel(K$AUDIT, 'run.in begin", "   ri.active = 0\n   void kernel(K$AUDIT, 'run.in begin"),
    ("the account's LOGIN is run", "cproc", "      new.sentence = ri.sentence\n", "      new.sentence = 'LOGIN'\n      gosub proc.sentence\n      new.sentence = ri.sentence\n"),
    ("a slash is a plain character", "cproc", "'abcdefghijklmnopqrstuvwxyz0123456789._-', ri.word[ri.i, 1], 1)", "'abcdefghijklmnopqrstuvwxyz0123456789._-/', ri.word[ri.i, 1], 1)"),
    ("sdsys is not refused", "cproc", "   if ri.acct = 'sdsys' then\n", "   if 0 then\n"),
    ("one switch is not restored", "cproc", "   void kernel(K$SD.ACCOUNTS, ri.sw<3>)\n", ""),
    ("LOGTO no longer loads through the routine", "cproc", "   gosub load.account.switches   ;* the account-scoped switches, from the new account's own register record",
     "   null   ;* the account-scoped switches, from the new account's own register record"),
    ("the verb is in the ordinary VOC too", "newvoc", None, None),
    ("the record says 43", "voc", "V\nIN\n42\n", "V\nIN\n43\n"),
    ("the check of a file in the account is dropped", "cproc", "   if ri.n.names = 2 then\n      ri.file = field(ri.rest, ' ', 3)", "   if 0 then\n      ri.file = field(ri.rest, ' ', 3)"),
    ("the word loop does not check the plain word", "cproc", "            gosub ri.plain.word\n", "            ri.ok = @true\n"),
    ("the directory is entered before the flag", "cproc", "   ri.active = 1\n   void kernel(K$AUDIT, 'run.in begin account=' : ri.acct : ' command=' : ri.sentence)\n",
     "   void kernel(K$AUDIT, 'run.in begin account=' : ri.acct : ' command=' : ri.sentence)\n   if ospath(acc.rec, OS$CD) then null\n   ri.active = 1\n"),
    ("no message after an abort", "cproc", "            display sysmsg(12247, ri.account)   ;* run.in: the command did not finish; the session is back in account %1\n", ""),
    # 3 Nov 26: the NO.CATALOG option
    ("run.in basic does not give no.catalog", "cproc", "   if ri.cmd = 'basic' then ri.sentence := ' no.catalog'\n", ""),
    ("no.catalog is given to every command", "cproc", "if ri.cmd = 'basic' then ri.sentence := ' no.catalog'", "ri.sentence := ' no.catalog'"),
    ("a person may give no.catalog", "cproc", "ri.n.names = 2 ; ri.opts = 'debugging no.query'", "ri.n.names = 2 ; ri.opts = 'debugging no.query no.catalog'"),
    ("no.catalog may be a name", "cproc", "ri.kwords = 'local global pcode no.query no.catalog noxref", "ri.kwords = 'local global pcode no.query noxref"),
    ("basic ignores the option", "basic", "      if catalogue.name # '' and no.catalog then\n", "      if 0 then\n"),
    ("basic catalogues after the skip as well", "basic", "      end else if catalogue.name # '' then\n", "      end\n      if catalogue.name # '' then\n"),
    ("basic never sets the flag", "basic", "            no.catalog = @true    ;* 3 Nov 26 dm  (S.96)", "            null"),
    ("the template record has another number", "kw.template", "K\n239\n", "K\n240\n"),
    ("the newvoc record has another number", "kw.newvoc", "\n239\n", "\n241\n"),
    ("parser.h has another number", "parser.h", "KW$NO.CATALOG     239", "KW$NO.CATALOG     240"),
    # 2 Nov 26: the forged-abort defect (probe-runin-forge.py on a real install)
    ("the common is a plain name again", "cproc", "   common /$runin/ ri.active,", "   common /runin/ ri.active,"),
    ("the kernel lets any program join a $ common", "op_array.c", "      !(process.program.flags & HDR_INTERNAL))\n    k_error(sysmsg(12603));", "      0)\n    k_error(sysmsg(12603));"),
    ("the kernel guards only $, not _", "op_array.c", "((*block_name == '$') || (*block_name == '_'))", "(*block_name == '$')"),
    # 10 Nov 26: the Windows-only checks
    ("the Windows checks are not asked", "cproc", "   if ri.file.ok then gosub ri.windows.checks\n", ""),
    ("the command runs when a check refused", "cproc", "   if ri.file.ok and ri.why = '' then\n", "   if ri.file.ok then\n"),
    ("a trigger on the VOC is not asked", "cproc", "      if fileinfo(voc, FL$TRIGGER) # '' then\n", "      if 0 then\n"),
    ("a drive letter is inside the account", "cproc", " or index(ri.q, ':', 1) or", " or"),
    ("a link in the account is not asked of the kernel", "cproc", "            if not(kernel(K$PATH.IN, account.path : @fm : ri.chk)) then ri.ok = @false\n", ""),
    ("$EXECUTE runs under run.in", "bcomp", "         if ri.active then\n            err.msg = sysmsg(15071)", "         if 0 then\n            err.msg = sysmsg(15071)"),
    ("$BCOMP's common has other names", "bcomp", "   common /$runin/ ri.active, ri.path,", "   common /$runin/ ri.active, ri.paths,"),
    ("the safety net keeps the visited account's $VOC.PARSER", "cproc", "            ri.active = 0\n            gosub get.voc.parser.rec\n", "            ri.active = 0\n"),
    ("the register is read as typed", "cproc", "read acc.record from acc.f, upcase(ri.acct) else", "read acc.record from acc.f, ri.acct else"),
    # 10 Nov 26: S.213 (from Linux ca137620), the command does not run as the administrator
    ("the command keeps the administrator flag", "cproc", "   void kernel(K$OS.EXEC, 0)\n   void kernel(K$ADMINISTRATOR, 0)\n   return\n", "   void kernel(K$OS.EXEC, 0)\n   return\n"),
    ("the flag is never dropped (no call)", "cproc", "      gosub ri.narrow            ;* 10 Nov 26, S.213: not the administrator from here to revert.account\n", ""),
    ("the flag is dropped after the command", "cproc", "      gosub ri.narrow            ;* 10 Nov 26, S.213: not the administrator from here to revert.account\n      gosub proc.sentence\n",
     "      gosub proc.sentence\n      gosub ri.narrow            ;* 10 Nov 26, S.213: not the administrator from here to revert.account\n"),
    ("compile.dict is given bp-edit", "cproc", "(ri.cmd = 'decatalog') or (ri.cmd = 'delete.catalog'))", "(ri.cmd = 'decatalog') or (ri.cmd = 'delete.catalog') or (ri.cmd = 'compile.dict'))"),
    ("every command is given voc-edit", "cproc", "   void kernel(K$VOC.EDIT,  0)\n   void kernel(K$BP.EDIT,", "   void kernel(K$VOC.EDIT,  1)\n   void kernel(K$BP.EDIT,"),
    ("SH stays on for the command", "cproc", "   void kernel(K$SH, 0)\n   void kernel(K$OS.EXEC, 0)\n   void kernel(K$ADMINISTRATOR, 0)\n", "   void kernel(K$OS.EXEC, 0)\n   void kernel(K$ADMINISTRATOR, 0)\n"),
    ("SH follows the account's record during a run", "cproc", "   void kernel(K$SH,      not(ri.active) and (upcase(trim(acc.record<ACC$SH>)) = 'YES'))", "   void kernel(K$SH,      (upcase(trim(acc.record<ACC$SH>)) = 'YES'))"),
    ("OS.EXECUTE follows the account's record during a run", "cproc", "   void kernel(K$OS.EXEC, not(ri.active) and (upcase(trim(acc.record<ACC$OS.EXEC>)) = 'YES'))",
     "   void kernel(K$OS.EXEC, (upcase(trim(acc.record<ACC$OS.EXEC>)) = 'YES'))"),
    ("revert does not restore the flag", "cproc", "   void kernel(K$ADMINISTRATOR, ri.sw<10>)   ;* 10 Nov 26, S.213: LAST - see the note above\n", ""),
    ("revert restores the flag first", "cproc", "revert.account:\n   ri.active = 0\n", "revert.account:\n   ri.active = 0\n   void kernel(K$ADMINISTRATOR, 1)\n"),
    ("revert leaves the account's edit gate on", "cproc", "   void kernel(K$BP.EDIT,   ri.sw<8>)\n", ""),
    ("the gates are restored after the directory change", "cproc",
     "   void kernel(K$VOC.EDIT,  ri.sw<7>)\n   void kernel(K$BP.EDIT,   ri.sw<8>)\n   void kernel(K$DICT.EDIT, ri.sw<9>)\n   if not(ospath(ri.path, OS$CD)) then\n      display sysmsg(5162)   ;* Fatal error : Cannot return to previous account\n      return to abort.cproc\n   end\n",
     "   if not(ospath(ri.path, OS$CD)) then\n      display sysmsg(5162)   ;* Fatal error : Cannot return to previous account\n      return to abort.cproc\n   end\n   void kernel(K$VOC.EDIT,  ri.sw<7>)\n   void kernel(K$BP.EDIT,   ri.sw<8>)\n   void kernel(K$DICT.EDIT, ri.sw<9>)\n"),
    ("the flag is not kept", "cproc", "   ri.sw<10> = kernel(K$ADMINISTRATOR, -1)", "   ri.sw<10> = 1 ;* kernel(K$ADMINISTRATOR, -1)"),
    ("the run is flagged before the gates are kept", "cproc", "   ri.sw<7> = kernel(K$VOC.EDIT, -1) ;", "   ri.active = 1\n   ri.sw<7> = kernel(K$VOC.EDIT, -1) ;"),
    ("the abort branch does something before revert", "cproc", "         if ri.active then\n            gosub revert.account\n            display sysmsg(12247, ri.account)",
     "         if ri.active then\n            void kernel(K$SH, 1)\n            gosub revert.account\n            display sysmsg(12247, ri.account)"),
    ("LOGTO is allowed during a run", "cproc", "   if ri.active then\n      display sysmsg(15073, ri.account)", "   if 0 then\n      display sysmsg(15073, ri.account)"),
    ("the LOGTO refusal is not audited", "cproc", "      void kernel(K$AUDIT, 'run.in refused account=' : ri.account : ' target=' : downcase(new.account)[1, 40] : ' reason=logto')\n", ""),
    ("an include file is not asked", "bcomp", "   ri.chk.path = fileinfo(incl.file, FL$PATH)\n   gosub ri.outside\n", "   ri.out = @false\n"),
    ("the $dict dictionary is not asked", "bcomp", "               ri.chk.path = fileinfo(ri.dict.f, FL$PATH)\n               gosub ri.outside\n", "               ri.out = @false\n"),
    ("a FILE dictionary is not asked", "bcomp", "      ri.chk.path = fileinfo(file.d(0), FL$PATH)\n      gosub ri.outside\n", "      ri.out = @false\n"),
    ("ri.outside refuses nothing", "bcomp", "then ri.out = @true\n", "then ri.out = @false\n"),
    ("ri.outside refuses outside a run too", "bcomp", "   ri.out = @false\n   if ri.active then\n      if not(kernel(K$PATH.IN, @path", "   ri.out = @false\n   if 1 then\n      if not(kernel(K$PATH.IN, @path"),
    ("an outside include is read before it is refused", "bcomp", "   ri.chk.path = fileinfo(incl.file, FL$PATH)\n   gosub ri.outside\n   if ri.out then\n      incl.file = 0\n      err.msg = sysmsg(15072, include.file.name)",
     "   level += 1\n   level -= 1\n   ri.chk.path = fileinfo(incl.file, FL$PATH)\n   gosub ri.outside\n   if ri.out then\n      incl.file = 0\n      err.msg = sysmsg(15072, include.file.name)"),
    ("the $dict dictionary is used even when it is outside", "bcomp", "               end else\n                  dict.f = ri.dict.f\n               end\n", "               end\n               dict.f = ri.dict.f\n"),
    ("_voc_ref follows a Q-pointer out during a run", "_voc_ref", "               if ri.active then\n                  if not(q.registered and downcase(q.named) = ri.account) then", "               if 0 then\n                  if not(q.registered and downcase(q.named) = ri.account) then"),
    ("_voc_ref lets any registered account in during a run", "_voc_ref", "if not(q.registered and downcase(q.named) = ri.account) then", "if not(q.registered) then"),
    ("_voc_ref's common differs from cproc's", "_voc_ref", "   common /$runin/ ri.active, ri.path, ri.account.path, ri.who, ri.sw, ri.account\n", "   common /$runin/ ri.active, ri.path, ri.account.path, ri.who, ri.sw, ri.acct\n"),
    ("message 15072 does not name syscom", "msg15072", " and syscom only", " only"),
    ("message 15073 does not take the account", "msg15073", " in account %1", ""),
]

# 11 Nov 26, RELEASE_1.1 231.  --selftest --from=r231 runs the mutants from here on (Linux's own-words mutants, with this tree's text).
M_R231 = len(MUTANTS)
MUTANTS += [
    ("the words are not compared with the shipped VOC", "cproc", "   gosub ri.own.words\n   if ri.bad # '' then\n", "   ri.bad = ''\n   if ri.bad # '' then\n"),
    ("the words are asked after the flag is set", "cproc", "   gosub ri.own.words\n   if ri.bad # '' then\n      display sysmsg(15070, ri.bad[1, 40], ri.acct)",
     "   ri.active = 1\n   gosub ri.own.words\n   if ri.bad # '' then\n      display sysmsg(15070, ri.bad[1, 40], ri.acct)"),
    ("the words are asked after what is kept to come back", "cproc", "   gosub ri.own.words\n   if ri.bad # '' then\n      display sysmsg(15070, ri.bad[1, 40], ri.acct)",
     "   ri.path = ospath('', os$cwd)\n   gosub ri.own.words\n   if ri.bad # '' then\n      display sysmsg(15070, ri.bad[1, 40], ri.acct)"),
    ("only the command word is compared, not the options", "cproc", "            if (ri.w = 1 or ri.w > 1 + ri.n.names) and ri.bad = '' then", "            if (ri.w = 1) and ri.bad = '' then"),
    ("only the type letter is compared", "cproc", "                  case field(ri.vrec, @fm, 2, 9999) # field(ri.own, @fm, 2, 9999)\n", "                  case 0\n"),
    ("a missing record passes", "cproc", "                  case ri.vrec = ''\n                     ri.bad = ri.word ; ri.why = 'no entry in the voc of the account'\n", ""),
    ("a word the shipped VOC lacks passes", "cproc", "                  case ri.own = ''\n                     ri.bad = ri.word ; ri.why = 'not in the shipped voc'\n", ""),
    ("an unreadable shipped VOC passes", "cproc", "      case not(ri.nv.open)\n         ri.bad = ri.cmd ; ri.why = 'the shipped voc cannot be read'\n", ""),
    ("the refusal of a word is not audited", "cproc", "      void kernel(K$AUDIT, 'run.in refused account=' : ri.acct : ' word=' : ri.bad[1, 40] : ' reason=' : ri.why)\n", ""),
    ("the words are compared with SDSYS's VOC again (the voc of the session)", "cproc", "   openpath acc.rec:@ds:'voc' to ri.av.f then ri.av.open = @true", "   openpath @sdsys:@ds:'voc' to ri.av.f then ri.av.open = @true"),
    ("the old message 12565 is used again", "cproc", "      display sysmsg(15070, ri.bad[1, 40], ri.acct)", "      display sysmsg(12565, ri.bad[1, 40], ri.acct)"),
    ("$execute is refused with the old id 12568", "bcomp", "            err.msg = sysmsg(15071)", "            err.msg = sysmsg(12568)"),
    ("message 15070 does not name the account", "msg15070", " of account %2", ""),
    ("message 15071 does not name run.in", "msg15071", "started by run.in", "started somewhere"),
]


def selftest():
    src, voc, names, extra = load()
    base = run_checks(src, voc, names, extra)
    if any(not ok for _, ok, _ in base):
        print("selftest: the unmutated source already fails; fix that first")
        return 1
    missed = 0
    start = 0
    for a in sys.argv:
        if a.startswith("--from="):
            v = a[len("--from="):].lower()
            start = M_R231 if v == "r231" else int(v)
    if start:
        print("selftest: from mutant %d of %d" % (start, len(MUTANTS)))
    for name, kind, old, new in MUTANTS[start:]:
        s, v, nm, ex = src, voc, set(names), dict(extra)
        if kind == "cproc":
            if s.count(old) != 1:
                print("  [CANNOT] %-60s the text does not occur exactly once (%d)" % (name, s.count(old)))
                missed += 1
                continue
            s = s.replace(old, new)
        elif kind == "voc":
            v = v.replace(old, new)
        elif kind == "newvoc":
            nm.add("run.in")
        elif kind in ex:
            if ex[kind].count(old) != 1:
                print("  [CANNOT] %-60s the text does not occur exactly once (%d)" % (name, ex[kind].count(old)))
                missed += 1
                continue
            ex[kind] = ex[kind].replace(old, new)
        res = run_checks(s, v, nm, ex)
        caught = [n for n, ok, _ in res if not ok]
        if caught:
            print("  [caught] %-60s by %s" % (name, ", ".join(c.split()[0] for c in caught[:4])))
        else:
            print("  [MISSED] %-60s" % name)
            missed += 1
    print("selftest: %d mutants, %d missed or not applied" % (len(MUTANTS) - start, missed))
    return 0 if missed == 0 else 1


def main():
    if "--selftest" in sys.argv:
        return selftest()
    try:
        src, voc, names, extra = load()
    except OSError as e:
        print("cannot read the source: %s" % e)
        return 2
    res = run_checks(src, voc, names, extra)
    failed = 0
    for name, ok, detail in res:
        print("  [%s] %s%s" % ("PASS" if ok else "FAIL", name, "" if ok else "   <- " + detail))
        failed += 0 if ok else 1
    print("test-runin-units: %d checks, %d failed" % (len(res), failed))
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
