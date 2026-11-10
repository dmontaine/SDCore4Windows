#!/usr/bin/env python3
# test-fmtquiet-units.py - gpl.bp/fmtsub (!format) has a quiet mode (S.88 d2b, 29 Oct 2026; owner decision 10, Opus-refined).
# The IDE's Format command calls !format with the screen in the middle of a full-screen form; the program's three output sites -
# the progress dot, the error display and the data-mismatch message with its keyin() - would write over it, so the caller sets
# fq.quiet = 1 immediately before the call and reads fq.log after it, through the named COMMON /fmtq/ (the call keeps its six arguments).
#   * fmtsub copies the flag into a LOCAL and CLEARS it on entry, so an abort between setting and calling cannot leave every later
#     FORMAT at the command line silently quiet; the copy is `quiet`, tested by every output site.
#   * quiet: no dot, no error display, no keyin; the error line ('NNNN:  message') and the data mismatch go to fq.log, which is
#     emptied on entry in quiet mode only.
#   * not quiet: byte for byte what it printed before (the FORMAT verb, ED and SED never set the flag).
# FREE CHECK: the BASIC read as text; no install, no sd.  It cannot say a screen stays whole - that is the IDE's suite (ide-edit).
#
#   python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/test-fmtquiet-units.py
#   python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/test-fmtquiet-units.py --selftest
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
BP = os.environ.get("BPDIR", os.path.normpath(os.path.join(HERE, "..", "sdsys", "gpl.bp")))


def read():
    with open(os.path.join(BP, "fmtsub"), encoding="latin-1") as f:
        return f.read()


def code(src):
    """the source with whole-line comments (column 0 '*' or an indented '*') and trailing ';*' comments removed"""
    out = []
    for l in src.split("\n"):
        if l.lstrip().startswith("*"):
            continue
        out.append(re.sub(r"\s*;\*.*$", "", l))
    return "\n".join(out)


def sq(s):
    """one space between the words, to compare blocks whatever the indentation"""
    return re.sub(r"\s+", " ", s)


def checks(src):
    c = code(src)
    n = sq(c)
    rows = []

    def row(name, ok, detail=""):
        rows.append((name, bool(ok), detail))

    # the interface
    row("Q1 the named COMMON /fmtq/ fq.quiet, fq.log is declared once", len(re.findall(r"(?im)^\s*common\s+/fmtq/\s+fq\.quiet\s*,\s*fq\.log\s*$", c)) == 1)
    row("Q2 the CALL keeps its six arguments", "subroutine format(in.rec, out.rec, default.file, indent.step, case.option, errors)" in c)
    # the flag is taken into a local and cleared on entry, before any output site
    i_copy = c.find("quiet = (fq.quiet = 1)")
    i_clear = c.find("fq.quiet = 0")
    i_first = c.find("name.chars =")
    row("Q3 the flag is copied to a local", i_copy >= 0)
    row("Q4 the flag is cleared AFTER the copy and BEFORE the first statement of the work", 0 <= i_copy < i_clear < i_first, "copy %d clear %d work %d" % (i_copy, i_clear, i_first))
    reads = [l.strip() for l in c.split("\n") if re.search(r"\bfq\.quiet\b", l)]
    row("Q5 fq.quiet is read and written only by the copy, the clear and the declaration", len(reads) == 3, str(reads))
    row("Q6 fq.log is emptied on entry in quiet mode and nowhere else assigned from scratch", len(re.findall(r"if quiet then fq\.log = ''", c)) == 1 and len(re.findall(r"\bfq\.log\s*=", c)) == 1)
    # the three output sites
    row("D1 the progress dot is skipped in quiet mode", "if rem(lno,10) = 0 and not(quiet) then display '.' : dot.emitted = @true end" in n)
    row("D1b dot.emitted is set only there", len(re.findall(r"dot\.emitted\s*=\s*@true", c)) == 1)
    row("M1 the data mismatch: quiet logs it, with the line number, and shows nothing", re.search(r"if quiet then fq\.log<-1> = fmt\(lno, \"4'0'R\"\) : ':\s+Internal error - data mismatch\.' end else display ", n) is not None)
    row("M2 the data mismatch: the keyin is in the not-quiet branch", re.search(r"end else display 'Internal error - data mismatch\.' display \"I started with \":len\(in\.rec\):\" bytes and ended up with \": len\(new\.rec\):\" bytes\" display 'Press ENTER to continue' : i = keyin\(\) end new\.rec = in\.rec end", n) is not None)
    row("E1 the error line: quiet appends it to the log, otherwise it is displayed as before", re.search(r"error: if quiet then fq\.log<-1> = fmt\(lno, \"4'0'R\"\) : ':\s+' : message end else if dot\.emitted then display display fmt\(lno, \"4'0'R\"\) : ':\s+' : message end dot\.emitted = @false errors \+= 1 return", n) is not None)
    # every output statement is one of the known ones: no new unguarded display or keyin
    out = [l.strip() for l in c.split("\n") if re.search(r"\bdisplay\b|\bkeyin\(", l)]
    row("A1 the program has exactly eight lines that display or call keyin (dot, end-of-dots, 3 mismatch, keyin, 2 error)", len(out) == 8, str(len(out)))
    # not-quiet text byte for byte
    for what, text in (("the dot", "display '.' :"), ("the mismatch line", "display 'Internal error - data mismatch.'"),
                       ("the byte counts", 'display "I started with ":len(in.rec):" bytes and ended up with ": len(new.rec):" bytes"'),
                       ("the prompt", "display 'Press ENTER to continue' :"), ("the error line", "display fmt(lno, \"4'0'R\") : ':  ' : message")):
        row("T1 not quiet prints %s as before" % what, text in c)
    return rows


def run():
    rows = checks(read())
    bad = 0
    for name, ok, detail in rows:
        print("  [%s] %s%s" % ("PASS" if ok else "FAIL", name, "" if ok else "   <- " + detail))
        bad += 0 if ok else 1
    print("test-fmtquiet-units: %d passed, %d failed" % (len(rows) - bad, bad))
    return 1 if bad or not rows else 0


def selftest():
    src = read()
    if not all(ok for _, ok, _ in checks(src)):
        print("  [FAIL] the real program does not pass")
        return 1
    print("  [ok] the real program passes")
    caught = missed = 0

    def mutant(name, old, new):
        nonlocal caught, missed
        if old not in src:
            print("  [MISSED] %s: the text to change is not there" % name)
            missed += 1
            return
        failing = [n for n, ok, _ in checks(src.replace(old, new, 1)) if not ok]
        if failing:
            print("  [caught] %s (%d row)" % (name, len(failing)))
            caught += 1
        else:
            print("  [MISSED] %s" % name)
            missed += 1

    mutant("flag not cleared on entry", "   fq.quiet = 0\n", "   null\n")
    mutant("flag cleared before it is copied", "   quiet = (fq.quiet = 1)\n   fq.quiet = 0\n", "   fq.quiet = 0\n   quiet = (fq.quiet = 1)\n")
    mutant("flag read again later", "   if quiet then fq.log = ''", "   if quiet or fq.quiet then fq.log = ''")
    mutant("log not emptied on entry", "   if quiet then fq.log = ''", "   null")
    mutant("quiet path still prints the dot", "if rem(lno,10) = 0 and not(quiet) then", "if rem(lno,10) = 0 then")
    mutant("quiet path still displays the error", "   if quiet then\n      fq.log<-1> = fmt(lno, \"4'0'R\") : ':  ' : message\n   end else", "   if 0 then\n      fq.log<-1> = fmt(lno, \"4'0'R\") : ':  ' : message\n   end else")
    mutant("error not logged", "      fq.log<-1> = fmt(lno, \"4'0'R\") : ':  ' : message\n", "      null\n")
    mutant("quiet path still waits at keyin", "      if quiet then\n         fq.log<-1>", "      if 0 then\n         fq.log<-1>")
    mutant("mismatch dropped instead of logged", ":  Internal error - data mismatch.'    ;* logged, not shown, no keyin", ":  Internal error - data mismatch.'    ;* logged, not shown, no keyin\n         fq.log = ''")
    mutant("mismatch not logged at all", "         fq.log<-1> = fmt(lno, \"4'0'R\") : ':  Internal error - data mismatch.'    ;* logged, not shown, no keyin\n", "         null\n")
    mutant("keyin taken out of the not-quiet branch", "         i = keyin()\n      end\n      new.rec = in.rec", "      end\n      i = keyin()\n      new.rec = in.rec")
    mutant("not-quiet prompt changed", "display 'Press ENTER to continue' :", "display 'Press ENTER' :")
    mutant("not-quiet error line changed", "      display fmt(lno, \"4'0'R\") : ':  ' : message", "      display fmt(lno, \"4'0'R\") : ': ' : message")
    mutant("an extra display added", "   if dot.emitted then display\n\n   * If all", "   if dot.emitted then display\n   display 'done'\n\n   * If all")
    mutant("the common taken out", "   common /fmtq/ fq.quiet, fq.log", "   null")
    mutant("a seventh argument", "case.option, errors)\n$catalog", "case.option, errors, quiet.arg)\n$catalog")
    print("selftest: %d of %d mutants caught, %d missed" % (caught, caught + missed, missed))
    return 0 if missed == 0 else 1


if __name__ == "__main__":
    sys.exit(selftest() if "--selftest" in sys.argv[1:] else run())
