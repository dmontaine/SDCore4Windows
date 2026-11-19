#!/usr/bin/env python3
"""test-examples-units.py - the example programs (examples.bp in every account, S.261) as invariants read off the source.  Free: no install, no elevation, no sd.

    python C:/Users/Don/Projects/SDCore4Windows/sdb_ai/sd64/gplbld/test-examples-units.py [--selftest]

16 Nov 2026, Windows port of Linux's guard of the same name (cc7e41c6, 657da3de).  The owner, 17 Nov 2026: "there should be a examples.bp file available
to all users that contains those programs and a set of training programs typical for a Computer Science 101 course"; asked how every account reaches
it, "A copy in every account".  What it holds:
  X1  THE GUIDE AND THE FILES ARE ONE TEXT: each of the five TUI programs (hello, menus, notes, browse, stock) is byte for byte the first code block of its
      chapter of the SD Text User Interface - Programmer's Guide in the docs checkout beside this one, SDCore4WindowsDocs (exit 2 when it is missing)
  X2  every shipped file has a name LOAD.EXAMPLES takes, begins "* <name> -", and each training program (cs..) is "program <name>" ... "end"
  X3  no shipped program writes a doubled quote inside a string (SD BASIC has no '' escape: test-sqescape-units.py's rule, for gpl.bp)
  X4  LOAD.EXAMPLES asks for the administrator before it reads anything, skips a SUSPENDED account, makes examples.bp and examples.bp.out DIRECTORY files
      by the account's pathname, judges each compile on the compiler's own success line, NEVER LOGTOs (on Windows a LOGTO out of SDSYS ends the
      administrator right), removes SDSYS's two compiler pointers when it is done, and writes one audit line
  X5  create.account runs load.examples for the account it made, after its audit line
  X6  the installer runs it: sd.iss LoadExamples after SharedDocs, its message in the closing box; load-examples.ps1 starts LOAD.EXAMPLES internally with
      the marker and judges it on message 15124's success wording; stage.py ships sdsys\\examples and the script; SecureSysdirs locks examples
  X7  load.examples is the administrator's verb: in voc_template, not in newvoc; the messages it cites exist
  X8, X9  LOAD.EXAMPLES and REMOVE.EXAMPLES take a LIST of accounts (owner, 17 Nov 2026), an unregistered name said and skipped
  X10, X11  REMOVE.EXAMPLES, the companion: only the shipped names deleted with their objects, the files only when nothing is left (judged on a reopen),
      no LOGTO, one audit line; its VOC record in voc_template only and its messages exist
It cannot say a program runs or what it prints: that needs an installed system.
"""
import importlib.util
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location("sqescape_for_examples", os.path.join(HERE, "test-sqescape-units.py"))
SQ = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(SQ)                         # its rule (doubled, COMMENT_LINE) is the one gpl.bp is held to; main() is not run
SD64 = os.path.normpath(os.path.join(HERE, ".."))
ROOT = os.path.normpath(os.path.join(SD64, "..", ".."))
SDSYS = os.path.join(SD64, "sdsys")
EX = os.path.join(SDSYS, "examples")
GUIDE = os.path.normpath(os.path.join(ROOT, "..", "SDCore4WindowsDocs", "TUIGuide", "markdown"))
PAGES = [("hello", "02-a-bare-page"), ("menus", "03-menus-and-the-finder"), ("notes", "04-a-form-and-a-confirm-box"),
         ("browse", "05-panes-and-pickers"), ("stock", "05b-a-form-in-the-body")]


def rd(p):
    try:
        with open(p, encoding="latin-1", newline="") as f:
            return f.read()
    except OSError:
        return None


def load():
    raw = {"load": rd(os.path.join(SDSYS, "gpl.bp", "loadexamples")), "createa": rd(os.path.join(SDSYS, "gpl.bp", "createa")),
           "iss": rd(os.path.join(HERE, "sd.iss")), "ps1": rd(os.path.join(HERE, "load-examples.ps1")), "stage": rd(os.path.join(HERE, "stage.py")),
           "vt": rd(os.path.join(SDSYS, "voc_template", "load.examples")),
           "nv": rd(os.path.join(SDSYS, "newvoc", "load.examples")),
           "rm": rd(os.path.join(SDSYS, "gpl.bp", "removeexamples")), "vtr": rd(os.path.join(SDSYS, "voc_template", "remove.examples")),
           "nvr": rd(os.path.join(SDSYS, "newvoc", "remove.examples")), "sec": rd(os.path.join(HERE, "secure-sysdirs.ps1"))}
    raw["files"] = {n: rd(os.path.join(EX, n)) for n in sorted(os.listdir(EX))} if os.path.isdir(EX) else {}
    raw["guide"] = {n: rd(os.path.join(GUIDE, p + ".md")) for n, p in PAGES}
    return raw


def code(src):
    return "\n".join(re.sub(r"\s*;\*.*$", "", l) for l in (src or "").split("\n") if not re.match(r"^\s*\*", l))


def first_block(md, name):
    blocks, cur, inside = [], [], False
    for ln in (md or "").split("\n"):
        if ln.startswith("```"):
            if inside:
                blocks.append(cur)
                cur = []
            inside = not inside
            continue
        if inside:
            cur.append(ln)
    b = next((b for b in blocks if b and b[0].startswith("* %s -" % name)), None)
    return None if b is None else "\n".join(b) + "\n"


def iss_code(src):
    """sd.iss without its { } and (* *) comments, so a call that is only mentioned in a comment does not count."""
    s = re.sub(r"\(\*.*?\*\)", "", src or "", flags=re.S)
    return re.sub(r"\{[^}]*\}", "", s, flags=re.S)


def py_list(src, name):
    """The body of the top-level list NAME = [ ... ] in stage.py, or '' when it is not there."""
    m = re.search(r"\n%s = \[\n(.*?)\n\]\n" % re.escape(name), src or "", re.S)
    return m.group(1) if m else ""


def checks(raw):
    rows = []

    def ck(i, what, ok, detail=""):
        rows.append((i, what, bool(ok), detail))

    files = raw["files"]
    bad = [n for n, _ in PAGES if files.get(n) is None or first_block(raw["guide"][n], n) != files.get(n)]
    ck("X1", "each of the five TUI programs is byte for byte its chapter's first code block in the guide", not bad, repr(bad))
    badname = [n for n in files if not re.match(r"^[a-z][a-z0-9._-]{0,79}$", n)]
    badhead = [n for n, t in files.items() if not (t or "").startswith("* %s -" % n)]
    badcs = [n for n, t in files.items() if n.startswith("cs") and not (re.search(r"^program %s\s*$" % re.escape(n), t or "", re.M) and (t or "").rstrip().endswith("end"))]
    crlf = [n for n, t in files.items() if "\r" in (t or "")]
    ck("X2", "%d shipped files: every name is a key, every file begins '* <name> -', every training program is program <name> ... end, no CR" % len(files),
       len(files) >= 25 and not badname and not badhead and not badcs and not crlf and len([n for n in files if n.startswith("cs")]) >= 20,
       repr((badname, badhead, badcs, crlf)))
    dq = [n for n, t in files.items() for l in (t or "").split("\n") if not SQ.COMMENT_LINE.match(l) and SQ.doubled(l)]     # test-sqescape-units.py's own reading
    ck("X3", "no shipped program writes a doubled quote inside a string ('it''s' is two strings in SD BASIC)", not dq, repr(dq))
    ld = code(raw["load"])
    ck("X4", "LOAD.EXAMPLES: the administrator first, a SUSPENDED account skipped, examples.bp and its .out DIRECTORY files made by pathname, the compile "
             "judged on its success line, no LOGTO, SDSYS's compiler pointers dropped at the end, one audit line",
       raw["load"] is not None and 0 <= ld.find("if not(kernel(K$ADMINISTRATOR, -1)) then") < ld.find("dir(src)")
       and "if upcase(trim(arec<ACC$SUSPENDED>)) = 'SUSPENDED' then continue" in ld
       and "create.file x.path directory on error" in ld and "create.file o.path directory on error" in ld
       and "if index(out, 'Compiled 1 program(s) with no errors', 1) then" in ld and "execute 'basic ' : src.voc : ' ' : todo<p> capturing out" in ld
       and "logto" not in ld.lower() and 0 < ld.find("   next a\n   gosub drop.pointers") < ld.find("void kernel(K$AUDIT")
       and "read drec from sv, did then delete sv, did" in ld and ld.count("kernel(K$AUDIT") == 1)
    ca = code(raw["createa"])
    i_aud = ca.find("void kernel(K$AUDIT, 'create.account account='")
    i_ld = ca.find("execute 'load.examples ' : downcase(acc.name) trapping aborts\n")
    ck("X5", "create.account runs load.examples for the account it made, after its audit line, trapping aborts and NOT capturing (S.270: capturing "
             "around a trapped abort crashed the process), and says 15185 when its return code is not 0 (Linux ac4e08fb)", 0 < i_aud < i_ld
       and i_ld < ca.find("ex.code = @system.return.code") < ca.find("if ex.code # 0 then crt sysmsg(15185")
       and not re.search(r"execute 'load\.examples[^\n]*capturing", ca))
    iss = iss_code(raw["iss"])
    ps1 = "\n".join(l for l in (raw["ps1"] or "").split("\n") if not l.lstrip().startswith("#"))
    st = raw["stage"] or ""
    lock = re.search(r"LockSysdirNames\(Ps, Script,(.*?), Code\);", iss, re.S)
    ck("X6", "the installer: sd.iss runs LoadExamples once, after SharedDocs, and puts its message in the closing box; load-examples.ps1 starts LOAD.EXAMPLES "
             "internally with the marker and judges it on 15124's wording; stage.py ships examples and the script; SecureSysdirs locks examples",
       iss.count("ExamplesMsg := LoadExamples;") == 1 and 0 < iss.find("DocsMsg := SharedDocs;") < iss.find("ExamplesMsg := LoadExamples;")
       and re.search(r"(?m)^\s+ExamplesMsg \+\s*$", iss) is not None and "load-examples.ps1" in iss      # 17 Nov 26: the closing box's own line (":= ExamplesMsg + LockSdsysExamples" also holds the words)
       and "Invoke-Sd @('-internal', 'LOAD.EXAMPLES')" in ps1 and "Set-SdInternalMarker" in ps1
       and "'(?m)^Example programs in examples\\.bp of [1-9][0-9]* account\\(s\\)'" in ps1
       and "('examples'," in py_list(st, "SDSYS_SHIP") and "('examples'," in py_list(st, "SDSYS_MIRROR") and "'load-examples.ps1'," in st
       and lock is not None and "examples" in "".join(re.findall(r"'([^']*)'", lock.group(1))).split("/"))
    cited = set(re.findall(r"sysmsg\((\d+)", ld))
    gone = sorted(n for n in cited if not os.path.exists(os.path.join(SDSYS, "messages", n)))
    ck("X7", "load.examples is in voc_template (V CA $loadexamples) and not in newvoc; the %d messages it cites exist" % len(cited),
       (raw["vt"] or "").split("\n")[:3] == ["V", "CA", "$loadexamples"] and raw["nv"] is None and cited and not gone, repr(gone))
    # THE LIST (owner, 17 Nov 2026: "both load.examples and remove.examples should take a list of accounts") and the companion verb
    rm = code(raw["rm"])
    for who, t in (("LOAD.EXAMPLES", ld), ("REMOVE.EXAMPLES", rm)):
        ck("X8" if who[0] == "L" else "X9", "%s takes a LIST of accounts: each word after the verb, each once, an unregistered name said and skipped, the others go on" % who,
           t and "for w = 2 to dcount(want, ' ')" in t and t.count("locate aid in accts<1> by 'AL' setting ap else ins aid before accts<ap>") == 2     # the list and the register
           and "stop sysmsg(15122, want)" not in t and "n.bad += 1\n            continue" in t)
    ck("X10", "REMOVE.EXAMPLES: the administrator first, only the SHIPPED names deleted (each read first), the compiled object with its program, examples.bp and its .out "
              "deleted only when nothing is left (left = 0) and judged on a reopen, no LOGTO, one audit line, a SUSPENDED account skipped",
       raw["rm"] is not None and 0 <= rm.find("if not(kernel(K$ADMINISTRATOR, -1)) then") < rm.find("dir(src)")
       and "read old from xf, names<p> then" in rm and "delete xf, names<p> on error dok = @false" in rm and "delete of, names<p> on error dok = @false" in rm
       and 0 < rm.find("if left = 0 then") < rm.find("dummy = ospath(x.path, OS$DELETE)") < rm.find("dummy = ospath(o.path, OS$DELETE)")
       and rm.find("dummy = ospath(x.path, OS$DELETE)") < rm.find("openpath x.path to xf then\n         close xf\n         display sysmsg(15129")
       and "select xf to 12" in rm and rm.count("OS$DELETE") == 2 and "logto" not in rm.lower() and rm.count("kernel(K$AUDIT") == 1
       and "if upcase(trim(arec<ACC$SUSPENDED>)) = 'SUSPENDED' then continue" in rm and "clear.file" not in rm)
    cited_r = set(re.findall(r"sysmsg\((\d+)", rm))
    gone_r = sorted(n for n in cited_r if not os.path.exists(os.path.join(SDSYS, "messages", n)))
    ck("X11", "remove.examples is in voc_template (V CA $removeexamples) and not in newvoc; the %d messages it cites exist" % len(cited_r),
       (raw["vtr"] or "").split("\n")[:3] == ["V", "CA", "$removeexamples"] and raw["nvr"] is None and cited_r and not gone_r, repr(gone_r))
    # 17 Nov 26 (Linux 1557e270's reply, "close it in the verb"): SDSYS's two files get bp.out's rights from the verb itself, with the grants
    # secure-sysdirs.ps1 gives a directory, and the installer still locks them after its own LOAD.EXAMPLES (LockSdsysExamples).
    sec = raw.get("sec") or ""
    m = re.search(r"\$kind\s+=\s+'directory'\s*\n\s*\$grants = @\((.*?')\)", sec, re.S)
    dgr = re.findall(r"'([^']+)'", m.group(1)) if m else []
    lk = ld[ld.find("\nlock.sdsys:"):]
    want = " ".join('/grant "%s"' % g for g in dgr)
    ck("X12", "LOAD.EXAMPLES run for SDSYS gives its examples.bp and examples.bp.out secure-sysdirs.ps1's directory grants (SYSTEM and Administrators full, "
              "sdusers read), /inheritance:r, through !ps_script, both files, a failure said; the installer's LockSdsysExamples locks both after its own run",
       len(dgr) == 3 and "sdusers:(OI)(CI)(RX)" in dgr and "if acct = 'sdsys' then gosub lock.sdsys" in ld and lk.startswith("\nlock.sdsys:")
       and want in lk and "/inheritance:r" in lk and "ls.rc = ps_script(ls.ps)" in lk and "for li = 1 to 2" in lk and "x.path else o.path" in lk
       and "display sysmsg(10055, lp, ls.rc)" in lk
       and "ExamplesMsg := ExamplesMsg + LockSdsysExamples;" in iss and "Rest := 'examples.bp/examples.bp.out';" in iss, repr(dgr))
    return rows


def sub(key, old, new):
    def f(raw):
        if raw.get(key) is None or old not in raw[key]:
            return None
        r = dict(raw)
        r[key] = raw[key].replace(old, new, 1)
        return r
    return f


def subfile(name, old, new):
    def f(raw):
        t = raw["files"].get(name)
        if t is None or old not in t:
            return None
        r = dict(raw)
        r["files"] = dict(raw["files"])
        r["files"][name] = t.replace(old, new, 1)
        return r
    return f


MUTANTS = [
    ("a TUI program drifts from the guide", "X1", subfile("hello", "Ctrl-Q", "Ctrl-X")),
    ("a training program loses its program line", "X2", subfile("cs06.fizzbuzz", "program cs06.fizzbuzz", "program fizz")),
    ("a shipped program is copied with CR LF line ends", "X2", subfile("cs01.hello", "\n", "\r\n")),
    ("a doubled quote in a string", "X3", subfile("cs09.subroutines", "\"the main program's i\"", "'the main program''s i'")),
    ("load.examples does not ask for the administrator", "X4", sub("load", "   if not(kernel(K$ADMINISTRATOR, -1)) then\n      stop sysmsg(2001)", "   if 0 then\n      stop sysmsg(2001)")),
    ("a suspended account is entered", "X4", sub("load", "if upcase(trim(arec<ACC$SUSPENDED>)) = 'SUSPENDED' then continue", "null")),
    ("the compile is not judged", "X4", sub("load", "if index(out, 'Compiled 1 program(s) with no errors', 1) then", "if 1 then")),
    ("load.examples enters the account with LOGTO, as on Linux", "X4", sub("load", "   x.path = acct.dir : '/examples.bp'", "   execute 'logto ' : acct capturing lt\n   x.path = acct.dir : '/examples.bp'")),
    ("SDSYS's compiler pointers are left behind", "X4", sub("load", "   next a\n   gosub drop.pointers", "   next a")),
    ("create.account does not load the examples", "X5", sub("createa", "   execute 'load.examples ' : downcase(acc.name) trapping aborts\n", "   null\n")),
    ("create.account captures load.examples again (S.270 crash)", "X5", sub("createa", "   execute 'load.examples ' : downcase(acc.name) trapping aborts\n",
                                                                           "   execute 'load.examples ' : downcase(acc.name) trapping aborts capturing ex.out\n")),
    ("create.account does not say a failed load", "X5", sub("createa", "   if ex.code # 0 then crt sysmsg(15185, downcase(acc.name))\n", "")),
    ("the installer does not run load-examples", "X6", sub("iss", "    ExamplesMsg := LoadExamples;", "    ExamplesMsg := '';")),
    ("the installer's failure line is not in the closing box", "X6", sub("iss", "           ExamplesMsg +\n", "")),
    ("load-examples.ps1 starts LOAD.EXAMPLES as an ordinary session", "X6", sub("ps1", "Invoke-Sd @('-internal', 'LOAD.EXAMPLES')", "Invoke-Sd @('LOAD.EXAMPLES')")),
    ("load-examples.ps1 judges on any text", "X6", sub("ps1", "'(?m)^Example programs in examples\\.bp of [1-9][0-9]* account\\(s\\)'", "'examples\\.bp'")),
    ("stage.py does not ship sdsys\\examples", "X6", sub("stage", "    ('examples',      'the example programs LOAD.EXAMPLES", "    ('examplez',      'the example programs LOAD.EXAMPLES")),
    ("SecureSysdirs does not lock examples", "X6", sub("iss", "      'examples/' +\n", "")),
    ("load.examples is given to every account", "X7", lambda raw: dict(raw, nv="V\nCA\n$loadexamples\n")),
    ("load.examples takes one account again", "X8", sub("load", "for w = 2 to dcount(want, ' ')", "for w = 2 to 2")),
    ("load.examples stops at an unregistered name", "X8", sub("load", "            display sysmsg(15122, aid)                           ;* No account is registered as %1 ...\n            n.bad += 1\n            continue",
                                                              "            stop sysmsg(15122, want)")),
    ("remove.examples takes one account only", "X9", sub("rm", "for w = 2 to dcount(want, ' ')", "for w = 2 to 2")),
    ("remove.examples lists a name twice", "X9", sub("rm", "locate aid in accts<1> by 'AL' setting ap else ins aid before accts<ap>\n      next w",
                                                     "ins aid before accts<1>\n      next w")),
    ("remove.examples does not ask for the administrator", "X10", sub("rm", "   if not(kernel(K$ADMINISTRATOR, -1)) then\n      stop sysmsg(2001)", "   if 0 then\n      stop sysmsg(2001)")),
    ("remove.examples deletes a program the system does not ship (clears the file)", "X10", sub("rm", "   for p = 1 to dcount(names, @fm)\n      read old from xf, names<p> then",
                                                                                                "   execute 'clear.file examples.bp' capturing out\n   for p = 1 to dcount(names, @fm)\n      read old from xf, names<p> then")),
    ("remove.examples deletes the file although programs are left", "X10", sub("rm", "   if left = 0 then", "   if 1 then")),
    ("remove.examples keeps the compiled object", "X10", sub("rm", "delete of, names<p> on error dok = @false", "dok = @true")),
    ("remove.examples is not judged on a reopen", "X10", sub("rm", "      openpath x.path to xf then\n         close xf\n         display sysmsg(15129, acct : ' examples.bp', 'the file could not be deleted')",
                                                             "      if 0 then\n         display sysmsg(15129, acct : ' examples.bp', 'the file could not be deleted')")),
    ("remove.examples enters the account with LOGTO, as on Linux", "X10", sub("rm", "   x.path = acct.dir : '/examples.bp'", "   execute 'logto ' : acct capturing lt\n   x.path = acct.dir : '/examples.bp'")),
    ("remove.examples is given to every account", "X11", lambda raw: dict(raw, nvr="V\nCA\n$removeexamples\n")),
    ("SDSYS's examples are not locked by the verb", "X12", sub("load", "   if acct = 'sdsys' then gosub lock.sdsys\n", "")),
    ("the verb leaves sdusers Modify on them", "X12", sub("load", '/grant "sdusers:(OI)(CI)(RX)"', '/grant "sdusers:(OI)(CI)(M)"')),
    ("the verb keeps the inherited rights", "X12", sub("load", "' /inheritance:r'", "''")),
    ("only examples.bp is locked", "X12", sub("load", "for li = 1 to 2", "for li = 1 to 1")),
    ("the installer no longer locks them", "X12", sub("iss", "    ExamplesMsg := ExamplesMsg + LockSdsysExamples;", "    ExamplesMsg := ExamplesMsg;")),
]


def main(argv):
    print("examples  : %s" % EX)
    print("guide     : %s" % GUIDE)
    raw = load()
    if not all(raw["guide"].values()):
        print("test-examples-units: CANNOT RUN - the docs checkout %s is missing or incomplete" % GUIDE)
        return 2
    if not raw["files"]:
        print("test-examples-units: CANNOT RUN - no %s" % EX)
        return 2
    print("read      : %d example files, loadexamples %s, removeexamples %s, sd.iss %s, load-examples.ps1 %s"
          % (len(raw["files"]), raw["load"] is not None, raw["rm"] is not None, raw["iss"] is not None, raw["ps1"] is not None))
    if "--selftest" in argv:
        if any(not ok for _, _, ok, _ in checks(raw)):
            print("REFUSING - the unmutated source already fails")
            return 1
        missed = 0
        for name, tag, f in MUTANTS:
            m = f(raw)
            failed = [i for i, _, ok, _ in checks(m)] if m is None else [i for i, _, ok, _ in checks(m) if not ok]
            if m is None or tag not in failed:
                print("  [MISSED] %s%s" % (name, " (the text to mutate is not there)" if m is None else ""))
                missed += 1
            else:
                print("  [pass] %s: caught by %s" % (name, tag))
        print("self-test: %d mutants, %d not caught" % (len(MUTANTS), missed))
        return 1 if missed else 0
    rows = checks(raw)
    bad = 0
    for i, what, ok, detail in rows:
        print("  [%s] %s %s%s" % ("PASS" if ok else "FAIL", i, what, "" if ok else "   <- " + str(detail)[:300]))
        bad += 0 if ok else 1
    print("test-examples-units: %d checks, %d failed" % (len(rows), bad))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
