#!/usr/bin/env python3
#
# sandbox-mode-q16.py - QM4 gaps bundle Q-16 ($MODE options).  No install, no sudo.
#
#   python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/sandbox-mode-q16.py <dir> [--build]
#
# <dir> is a sandbox made by sandbox-fromtree.py (needs a `make`d bin/sd).  With --build it is built first from
# THIS tree (it must be empty or absent).  Exit 0 every row passed, 1 a row failed, 2 it could not run.
#
# START-HISTORY:
# 27 Oct 26 dm  S.87 batch 17: the overlap modes, PICK.CONVERT and PICK.SELECT are gone with twenty-two other modes; each of the 22 names is a refusal row now, and the CONTROL rows of the
#               behaviour they changed stay.
# 15 Oct 26 dm  Written for QM4 gaps bundle Q-16: CHANGE.NO.OVERLAP, COUNT.OVERLAP, INDEX.OVERLAP, PICK.CONVERT,
#               CONDITIONAL.STATEMENTS, TRAP.UNUSED.MAIN.
# 27 Oct 26 dm  S.87 batch 3: the rows for the second spellings and forms removed that day (a CONTROL that runs the surviving spellings, then one row per removed word that
#               says the compiler REFUSES it, and the MCD / MCX conversions failing with STATUS 2); EREPLACE's two rows are gone with the function.
# 27 Oct 26 dm  S.87 batch 2: CONDITIONAL.STATEMENTS (a name that did nothing) and six other modes were removed; the row that said it was accepted is now seven rows
#               that say the seven names are refused (2842).
# END-HISTORY
#
# THE INSTRUMENT IS THE VALUE A BASIC PROGRAM PRINTED between brackets, value marks shown as |.  Every mode has its
# CONTROL: the same statement without the mode, which must give the old answer.  A body line that starts with a dollar
# sign is written at the left margin (a directive); the others are indented.  A body leaves its value in x.  A row can
# also name words the COMPILER's output must have (a warning, an error) or must not have, and a want of None means the
# program must not compile, so nothing may be printed by it.

import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.path.join(HERE, "sandbox-fromtree.py")
ANSI = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]")
passed = failed = 0

CASES = []   # (label, BASIC lines, wanted value or None for "must not compile", words the compile output must have, words it must not)
AUX = []     # (record name in bp, text, how): "include" is only written; "sub" is compiled and catalogued first


def case(label, body, want, has=(), lacks=()):
    CASES.append((label, body, want, tuple(has), tuple(lacks)))


def aux(name, text, how):
    AUX.append((name, text, how))


# ---- 27 Oct 26 (S.87 batch 17): the overlap modes and PICK.CONVERT are gone; the CONTROLS stay, and the names are refused ----
case("CONTROL: CHANGE from the 3rd occurrence, overlapping occurrences are skipped one byte at a time",
     "x = change(%s, 'aa', 'xx', 0, 3)" % S9, "aaxxxxxxa")
case("CONTROL: CHANGE, same string, no start argument (CHANGE replaces all)",
     "x = change(%s, 'aa', 'xx')" % S9, "xxxxxxxxa")
aux("zzq16sa", "subroutine zzq16sa(r)\n   r = index('aaaaaaaaa', 'aa', 3)\nreturn\nend\n", "sub")
case("CONTROL: the same without the mode finds the 2nd occurrence at position 3",
     "x = change('ababababa', 'aba', 'X', 0, 2)", "abXbX")
case("CONTROL: COUNT of overlapping a's is 4 by default",
     "x = count(%s, 'aa')" % S9, "4")
case("CONTROL: COUNTS is 4 and 1 by default",
     "x = change(counts(%s:@vm:'aaa', 'aa'), @vm, '|')" % S9, "4|1")
case("CONTROL: INDEX of the 3rd 'aa' is 5 by default",
     "x = index(%s, 'aa', 3)" % S9, "5")
case("CONTROL: INDEXS with the 2nd occurrence is 3 and 0 by default",
     "x = change(indexs(%s:@vm:'aaa', 'aa', 2), @vm, '|')" % S9, "3|0")
case("CONTROL: CONVERT(from, to, string)", "x = convert('ab', 'xy', 'abcab')", "xycxy")

# ---- CONDITIONAL.STATEMENTS --------------------------------------------------------------------------------------
# A file statement as the condition of WHILE or UNTIL: true when the THEN clause would run.  The rows write a sequential
# file in the account, then read it, so every statement is shown to run (a write shows in the next row's read).
SEQ = ("openseq 'zzq16.seq' to f else\n"
       "   create f else x = 'nocreate'\n"
       "end\n"
       "weofseq f\n")
case("CONTROL: WRITESEQ and READSEQ with ordinary THEN / ELSE, the file the next rows use",
     SEQ + "writeseq 'l1' to f else x = 'bad'\nwriteseq 'l2' to f else x = 'bad'\nwriteseq 'l3' to f else x = 'bad'\n"
     "seek f, 0, 0 else x = 'bad'\nn = 0\nloop\n   readseq s from f else exit\n   n += 1\nrepeat\nx = n", "3")
case("Q-16 WRITESEQ as the WHILE condition: three lines written",
     SEQ + "n = 0\nloop\nwhile writeseq 'l':n to f do\n   n += 1\nuntil n >= 3\nrepeat\nseek f, 0, 0 else null\nm = 0\nloop\n"
     "   readseq s from f else exit\n   m += 1\nrepeat\nx = n : '/' : m", "3/3")
case("Q-16 READSEQ as the UNTIL condition: the loop ends when a line has been read",
     SEQ + "writeseq 'a' to f else null\nwriteseq 'b' to f else null\nseek f, 0, 0 else null\nn = 0\nloop\n   n += 1\n"
     "   if n > 4 then exit\nuntil readseq s from f\nrepeat\nx = n : '/' : s", "1/a")
case("Q-16 SEEK as a condition: true on a file that is open",
     SEQ + "writeseq 'a' to f else null\nn = 0\nloop\nwhile seek f, 0, 0 do\n   n += 1\nuntil n >= 2\nrepeat\nx = n", "2")
case("Q-16 WRITEBLK as the WHILE condition",
     SEQ + "n = 0\nloop\nwhile writeblk 'abcd' to f do\n   n += 1\nuntil n >= 2\nrepeat\nx = n", "2")
case("Q-16 READBLK as a condition reads the blocks in turn (control: READBLK was already allowed)",
     SEQ + "writeblk 'abcdef' to f else null\nseek f, 0, 0 else null\nn = 0\nloop\nwhile readblk s from f, 2 do\n   n += 1\nrepeat\nx = n",
     "3")
case("Q-16 WRITECSV as the WHILE condition and READCSV as the next one",
     SEQ + "n = 0\nloop\nwhile writecsv 'a', n to f do\n   n += 1\nuntil n >= 2\nrepeat\nseek f, 0, 0 else null\nm = 0\n"
     "loop\nwhile readcsv from f to u, v do\n   m += 1\nrepeat\nx = n : '/' : m : '/' : v", "2/2/1")
case("Q-16 MATREAD as the WHILE condition on a file that has the record, and not on one that has not",
     "open 'VOC' to v else x = 'noopen'\ndim a(2)\nn = 0\nloop\nwhile matread a from v, 'LOGTO' do\n   n += 1\nuntil n >= 2\nrepeat\n"
     "m = 0\nloop\nwhile matread a from v, 'zzq16nosuch' do\n   m += 1\nuntil m >= 2\nrepeat\nx = n : '/' : m", "2/0")
case("Q-16 MATREADU as the condition, its lock released after",
     "open 'VOC' to v else x = 'noopen'\ndim a(2)\nn = 0\nloop\nwhile matreadu a from v, 'LOGTO' do\n   n += 1\n   release v, 'LOGTO'\n"
     "until n >= 2\nrepeat\nx = n", "2")
case("Q-16 MATREADL as the condition",
     "open 'VOC' to v else x = 'noopen'\ndim a(2)\nn = 0\nloop\nwhile matreadl a from v, 'LOGTO' do\n   n += 1\n   release v, 'LOGTO'\n"
     "until n >= 2\nrepeat\nx = n", "2")
case("Q-16 GETLIST as the condition: false for a list that does not exist",
     "n = 0\nloop\nwhile getlist 'zzq16nolist' to 3 do\n   n += 1\nuntil n >= 2\nrepeat\nx = n", "0")
case("Q-16 LOCATE as the condition: true when the value is found",
     "s = 'a':@fm:'b':@fm:'c'\nn = 0\nloop\nwhile locate 'b' in s<1> setting p do\n   n += 1\nuntil n >= 2\nrepeat\nm = 0\n"
     "loop\nwhile locate 'z' in s<1> setting q do\n   m += 1\nuntil m >= 2\nrepeat\nx = n : '/' : p : '/' : m", "2/2/0")
case("Q-16 FIND as the condition: true when the value is found",
     "s = 'a':@fm:'b':@fm:'c'\nn = 0\nloop\nwhile find 'b' in s setting f, v do\n   n += 1\nuntil n >= 2\nrepeat\nx = n : '/' : f", "2/2")
case("Q-16 FINDSTR as the condition",
     "s = 'apple':@fm:'banana':@fm:'cherry'\nn = 0\nloop\nwhile findstr 'nan' in s setting f, v do\n   n += 1\nuntil n >= 2\nrepeat\nx = n : '/' : f",
     "2/2")
LOCKF = "execute 'CREATE.FILE zzq16lf DYNAMIC' capturing junk\nopen 'zzq16lf' to lf else x = 'noopen'\n"
case("Q-16 FILELOCK as the WHILE condition and FILEUNLOCK as the UNTIL condition",
     LOCKF + "n = 0\nloop\nwhile filelock lf do\n   n += 1\nuntil fileunlock lf\nrepeat\nx = n", "1")
# 27 Oct 26 (S.87 batch 2): the mode name CONDITIONAL.STATEMENTS, which was accepted and changed nothing, is gone with six others.  Each is REFUSED now, and the
# statements above are allowed without any mode, as they always were.
for _gone in ("conditional.statements", "prclose.default.0", "unassigned.common", "no.case.invert", "optional.then.else", "implied.stop", "exception.save.stack"):
    case("27 Oct 26: $MODE %s was removed and is refused (2842), as any name the compiler does not know" % _gone.upper(),
         "$mode %s\nx = 1" % _gone, None, has=["Unrecognised mode name"])

# ---- 27 Oct 26 (S.87 batch 3): second spellings and forms that were removed ---------------------------------------------------------
# One CONTROL row runs every spelling that stays, in the places the removed ones were written; then each removed word has a row that says the compiler REFUSES
# it ("N error(s)", and not "0 error(s)").  A refusal row alone would pass for any typing mistake, which is why the control comes first.
case("27 Oct 26 (S.87 batch 3) CONTROL: the spellings that stay - $INCLUDE, DIM, REM, SLEEP, CALL, EXECUTE ... RETURNING, @SENTENCE, LOCATE ... SETTING, "
     "OCONV / ICONV MX - compile and run",
     "$include bp zzq16inc\ndim a(5)\na(5) = 'k'\nrem a comment\nsleep 0\ncall zzq16sa(r)\nexecute 'who' capturing y returning z\n"
     "t = @sentence\ns = 'a':@fm:'b'\nlocate 'b' in s<1> setting p else p = 0\n"
     "x = zzinc : '/' : a(5) : '/' : r : '/' : (len(y) > 0) : '/' : assigned(z) : '/' : (len(t) >= 0) : '/' : p : '/' : oconv(255, 'MX') : '/' : iconv('FF', 'MX')",
     "7/k/5/1/1/1/2/FF/255")
case("27 Oct 26 (S.87 batch 3) CONTROL: a LOCAL SUBROUTINE written out compiles with no errors", "@RAW@   x = 1\nlocal subroutine zzl:\n   x = 2\nend\nend\n", None,
     has=["0 error(s)"])
# Every case is RUN after it is compiled, and an INPUT that ran would take the session's next line (the next row's BASIC command) as its answer, so this one is
# compiled and never reached.
case("27 Oct 26 (S.87 batch 3) CONTROL: INPUT ... WAITING compiles with no errors (it is behind an IF that is never true)",
     "@RAW@   if @false then\n      input y waiting 5\n   end\nend\n", None, has=["0 error(s)"])
case("27 Oct 26 (S.87 batch 3) CONTROL: OCONV MX gives hexadecimal and STATUS 0", "y = oconv(255, 'MX')\nx = status() : '/' : y", "0/FF")
case("27 Oct 26 (S.87 batch 3) CONTROL: ICONV MX gives the number and STATUS 0", "y = iconv('FF', 'MX')\nx = status() : '/' : y", "0/255")
for _mc in ("MCD", "MCDX", "MCX", "MCXD"):
    case("27 Oct 26 (S.87 batch 3): OCONV %s (a second spelling of MX) was removed: an invalid conversion, STATUS 2" % _mc,
         "y = oconv(255, '%s')\nx = status()" % _mc, "2")
for _mc in ("MCD", "MCX"):
    case("27 Oct 26 (S.87 batch 3): ICONV %s (a second spelling of MX) was removed: an invalid conversion, STATUS 2" % _mc,
         "y = iconv('FF', '%s')\nx = status()" % _mc, "2")


def _refused(label, body):
    case("27 Oct 26 (S.87 batch 3): %s is refused by the compiler" % label, body, None, has=["error(s)"], lacks=["0 error(s)"])


_refused("INPUT ... FOR (a second spelling of WAITING)", "@RAW@   if @false then\n      input y for 5\n   end\nend\n")
_refused("INPUT ... TIMEOUT (a second spelling of WAITING)", "@RAW@   if @false then\n      input y timeout 5\n   end\nend\n")
_refused("$INSERT (a second name for $INCLUDE)", "$insert bp zzq16inc\nx = 1")
_refused("INCLUDE without the dollar sign", "include bp zzq16inc\nx = 1")
_refused("COM (an abbreviation of COMMON)", "@RAW@   com zzcm\n   zzcm = 1\nend\n")
_refused("DIMENSION (a long spelling of DIM)", "dimension a(3)\nx = 1")
_refused("REDIMENSION (a long spelling of REDIM)", "@RAW@   subroutine zzq16bad(mat a)\n   dim a(1)\n   redimension a(10)\n   return\nend\n")
_refused("ENTER (a second name for CALL)", "enter zzq16sa\nx = 1")
case("27 Oct 26 (S.87 batch 3): $MODE PICK.ENTER was removed with ENTER and is refused (2842)", "$mode pick.enter\nx = 1", None, has=["Unrecognised mode name"])
for _m in ['change.no.overlap', 'count.overlap', 'index.overlap', 'pick.convert', 'pick.select', 'string.locate', 'composite.readnext', 'selectv', 'for.store.before.test', 'case.sensitive', 'pick.matrix', 'pick.jump.range', 'pick.read', 'optional.final.end', 'pick.substr', 'pick.substr.assign', 'compatible.append', 'heading.no.eject', 'write.delete.then.else', 'stdfil', 'stdfil.shared', 'autolock']:
    case("27 Oct 26 (S.87 batch 17): $MODE %s was removed and is refused (2842)" % _m, "$mode %s\nx = 1" % _m, None, has=["Unrecognised mode name"])
_refused("PERFORM (a second name for EXECUTE)", "perform 'who' capturing y\nx = 1")
_refused("PRINTERR (a second name for INPUTERR)", "printerr ''\nx = 1")
_refused("REMARK (a second name for REM)", "remark a comment\nx = 1")
_refused("RQM (a second name for SLEEP)", "rqm 0\nx = 1")
_refused("SUB (an abbreviation of SUBROUTINE)", "@RAW@sub zzq16bad(r)\nreturn\nend\n")
_refused("LOCAL SUB (an abbreviation of LOCAL SUBROUTINE)", "@RAW@   x = 1\nlocal sub zzl:\n   x = 2\nend\nend\n")
_refused("TCLREAD (a third way to read the command line)", "tclread t\nx = 1")
_refused("EXECUTE ... SETTING (the second spelling of RETURNING)", "execute 'who' capturing y setting z\nx = 1")
_refused("EXECUTE ... PASSLIST with no variable (a clause that did nothing)", "execute 'who' passlist\nx = 1")
# ECS was a word that was read and ignored.  It is not a word any more, and BASIC reads one expression after another as a value and its format, so ECS after a path (or
# alone) is a VARIABLE that nothing assigns: the compiler warns, and the program stops when it runs that line.
case("27 Oct 26 (S.87 batch 3): OPENTEMP 'path' ECS - ECS is no longer a word, so it is read as a variable that is never assigned (the compiler says so and the line does not run)",
     "opentemp 'zzq16tmp' ecs to f then null else null\nx = 1", None, has=["ECS is not assigned a value"])
_refused("LOCATE(expr, array, f, v; position; order), the bracketed Pick form", "s = 'a':@fm:'b'\nlocate('b', s, 1; p) then null else null\nx = 1")
_refused("EREPLACE() (a third name for CHANGE)", "x = ereplace('a-b', '-', '+')")
_refused("SENTENCE() (a third way to read the command line)", "x = sentence()")
_refused("SWAPMARKS() (it returned its argument)", "x = swapmarks('a')")
_refused("TERMINFO.EX() (an alias of TERMINFO)", "x = terminfo.ex('cols')")
_refused("@SYSTEM.SET (an alias of @SYSTEM.RETURN.CODE)", "x = @system.set")

# ---- default argument values and DEFAULT.UNASS.ARGS ----------------------------------------------------------------
aux("zzq16da", "subroutine zzq16da(r, a, b = 7, c = 'xyz', d = -2, e = @true) var.args\n"
    "   r = a : '/' : b : '/' : c : '/' : d : '/' : e : '/' : arg.count()\nreturn\nend\n", "sub")
aux("zzq16fa", "function zzq16fa(p, q = 10) var.args\n   return p + q\nend\n", "sub")
aux("zzq16db", "$mode default.unass.args\nsubroutine zzq16db(r, a = 3, b = 'k')\n   r = a : '/' : b\nreturn\nend\n", "sub")
aux("zzq16dc", "$mode default.unass.args\nsubroutine zzq16dc(r, a = 3) var.args\n   r = a : '/' : arg.count()\nreturn\nend\n", "sub")
case("Q-16 defaults: VAR.ARGS with only the first argument passed gives every default (negative number, string, @TRUE)",
     "call zzq16da(r, 1)\nx = r", "1/7/xyz/-2/1/2")
case("Q-16 defaults: an argument that is passed keeps its value and the ones after it still default",
     "call zzq16da(r, 1, 5)\nx = r", "1/5/xyz/-2/1/3")
case("Q-16 defaults: every argument passed, no default used",
     "call zzq16da(r, 1, 5, 'q', 9, 0)\nx = r", "1/5/q/9/0/6")
case("Q-16 defaults: ARG.COUNT is the number the caller passed, not what the defaults make of the rest",
     "call zzq16da(r, 1, 5, 'q')\nx = r", "1/5/q/-2/1/4")
case("Q-16 defaults: a FUNCTION with a default (DEFFUN names VAR.ARGS)",
     "deffun zzq16fa(p, q) var.args\nx = zzq16fa(5) : '/' : zzq16fa(5, 1)", "15/6")
case("Q-16 DEFAULT.UNASS.ARGS: an argument passed unassigned takes its default, one that is assigned keeps its value",
     "v = 'given'\ncall zzq16db(r, u, v)\nx = r", "3/given")
case("Q-16 DEFAULT.UNASS.ARGS: both unassigned",
     "call zzq16db(r, u, w)\nx = r", "3/k")
case("Q-16 DEFAULT.UNASS.ARGS with VAR.ARGS: an argument left out and one passed unassigned both default",
     "call zzq16dc(r)\ny = r\ncall zzq16dc(r, u)\nx = y : '|' : r", "3/1|3/2")
case("Q-16 defaults: a default without VAR.ARGS or the mode is refused",
     "@RAW@subroutine zzq16bad(r, a = 1)\nreturn\nend\n", None, has=["Default argument values need the VAR.ARGS option"])
case("Q-16 defaults: a default that is not a literal is refused",
     "@RAW@subroutine zzq16bad(r, a = r) var.args\nreturn\nend\n", None, has=["A default argument value must be a number"])
case("Q-16 defaults: a string holding both kinds of quote is refused",
     "@RAW@subroutine zzq16bad(r, a = \\a'b\"c\\) var.args\nreturn\nend\n", None, has=["A default argument value must be a number"])
case("CONTROL: the compiler reports an error in the line after the one with the bracket (r = ( is line 3 here)",
     "@RAW@subroutine zzq16bad(r, a)\n   r = a\n   r = (\nreturn\nend\n", None, has=["4: Data item or constant", "5: Mismatched brackets"])
case("Q-16 defaults: the program's own lines keep their line numbers, so the same two errors on the same lines",
     "@RAW@subroutine zzq16bad(r, a = 1) var.args\n   r = a\n   r = (\nreturn\nend\n", None,
     has=["4: Data item or constant", "5: Mismatched brackets"], lacks=["6: "])

# ---- EXPLICIT ----------------------------------------------------------------------------------------------------
ND = "Variable %s has not been declared"
case("CONTROL: an undeclared variable is fine without the mode",
     "yy = 5\nx = yy", "5", lacks=["not been declared"])
case("Q-16 EXPLICIT: DIM name declares scalars and they can be used",
     "$mode explicit\ndim a, b\na = 2\nb = 3\nx = a * b", "6", lacks=["not been declared"])
case("Q-16 EXPLICIT: an undeclared variable is a compile error naming it",
     "$mode explicit\ndim a\na = 2\nx = a + yy", None, has=[ND % "YY"])
case("Q-16 EXPLICIT: an assignment to an undeclared variable is the error too",
     "$mode explicit\nyy = 4\nx = 1", None, has=[ND % "YY"])
case("Q-16 EXPLICIT: a variable used before its DIM is the error (declared before any other reference)",
     "$mode explicit\ndim a\na = 2\nyy = 1\ndim yy\nx = yy", None, has=[ND % "YY"])
case("Q-16 EXPLICIT: a matrix is declared by its own DIM and works",
     "$mode explicit\ndim m(3), n\nm(2) = 'q'\nn = m(2)\nx = n", "q", lacks=["not been declared"])
case("Q-16 EXPLICIT: DIM of scalars and matrices in one statement, in any order",
     "$mode explicit\ndim p, m(2), q\np = 1\nm(1) = 2\nq = 3\nx = p + m(1) + q", "6", lacks=["not been declared"])
case("Q-16 EXPLICIT: a FOR variable has to be declared",
     "$mode explicit\ndim t\nfor ii = 1 to 3\n   t += ii\nnext ii\nx = t", None, has=[ND % "II"])
case("Q-16 EXPLICIT: a FOR variable that is declared works",
     "$mode explicit\ndim t, ii\nt = 0\nfor ii = 1 to 3\n   t += ii\nnext ii\nx = t", "6", lacks=["not been declared"])
case("Q-16 EXPLICIT: a COMMON variable is declared by the COMMON statement",
     "$mode explicit\ncommon /zzq16c/ cv1\ncv1 = 4\nx = cv1", "4", lacks=["not been declared"])
case("Q-16 EXPLICIT: $MODE -EXPLICIT lets undeclared names through again",
     "$mode explicit\n$mode -explicit\nyy = 7\nx = yy", "7", lacks=["not been declared"])
case("Q-16 EXPLICIT: a name declared twice is accepted",
     "$mode explicit\ndim a\ndim a\na = 3\nx = a", "3", lacks=["not been declared"])
aux("zzq16sc", "$mode explicit\nsubroutine zzq16sc(r, s)\n   r = s + 1\nreturn\nend\n", "sub")
case("Q-16 EXPLICIT: the arguments of a SUBROUTINE statement are declared by it",
     "call zzq16sc(r, 4)\nx = r", "5", lacks=["not been declared"])

# ---- 27 Oct 26 (S.87 batch 17): PICK.SELECT is gone; its CONTROL stays ----
# List 0 is made with FORMLIST, two ids that are in no file; the file the SELECTV names is the VOC.
PS = ("open 'VOC' to v else x = 'noopen'\nformlist 'k1':@fm:'k2'\n")
case("CONTROL: SELECTV with list 0 active selects from the file as always; list 0 is left alone",
     PS + "selectv v to lst\nreadnext id1 from lst else id1 = 'none'\nx = (id1 # 'k1') : '/' : system(11)", "1/1")

# ---- TRAP.UNUSED.MAIN --------------------------------------------------------------------------------------------
aux("zzq16inc", "   zzinc = 7\n", "include")
W = "is assigned a value but never used"
case("CONTROL: an unused assigned variable draws no warning without a mode",
     "zzmain = 5\nx = 1", "1", lacks=[W])
case("Q-16 TRAP.UNUSED.MAIN warns about one set in the program itself",
     "$mode trap.unused.main\nzzmain = 5\nx = 1", "1", has=["ZZMAIN " + W])
case("Q-16 TRAP.UNUSED.MAIN does not warn about one set only in an include record",
     "$mode trap.unused.main\n$include bp zzq16inc\nx = 1", "1", lacks=[W])
case("CONTROL: TRAP.UNUSED warns about the include record's variable too",
     "$mode trap.unused\n$include bp zzq16inc\nx = 1", "1", has=["ZZINC " + W])
case("Q-16 TRAP.UNUSED.MAIN: a variable set in the program and used is not reported",
     "$mode trap.unused.main\nzzmain = 5\nx = zzmain", "5", lacks=[W])
case("Q-16 TRAP.UNUSED.MAIN: set in the include record and in the program, used nowhere, is reported",
     "$mode trap.unused.main\n$include bp zzq16inc\nzzinc = 8\nx = 1", "1", has=["ZZINC " + W])


def say(s=""):
    print(s)


def row(name, ok, detail=""):
    global passed, failed
    if ok:
        passed += 1
        say("  [PASS] " + name)
    else:
        failed += 1
        say("  [FAIL] " + name + ("   <- " + detail if detail else ""))


def bail(msg):
    say("sandbox-mode-q16: CANNOT RUN - " + msg)
    sys.exit(2)


def sess(box, *cmds):
    say("    > %d commands" % len(cmds))
    p = subprocess.run([sys.executable, TOOL, box, "sess", os.path.join(box, "user_accounts")] + list(cmds),
                       capture_output=True, text=True, timeout=900)
    out = ANSI.sub("", p.stdout + p.stderr)
    return out.split(":TERM 200,9999", 1)[-1]


def source(i, body):
    # a body that starts with @RAW@ is the whole program, written as given (a SUBROUTINE statement has to be the first)
    if body.startswith("@RAW@"):
        return body[5:]
    # $NOCASE.STRINGS has to come before any executable statement, so it goes above the x = '' line
    lines = [ln for ln in body.split("\n") if ln.lower() == "$nocase.strings"]
    lines.append("   x = ''")
    for ln in body.split("\n"):
        if ln.lower() != "$nocase.strings":
            lines.append(ln if ln.startswith("$") else "   " + ln)
    lines.append("   crt 'C%02d[':x:']'" % i)
    lines.append("end")
    return "\n".join(lines) + "\n"


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) != 1:
        bail("usage: sandbox-mode-q16.py <dir> [--build]")
    box = os.path.abspath(args[0])
    sysd = os.path.join(box, "sys")
    say("sandbox-mode-q16: sandbox %s" % box)
    if "--build" in sys.argv:
        if os.path.exists(box) and os.listdir(box):
            bail("%s is not empty" % box)
        r = subprocess.run([sys.executable, TOOL, box, "all"], capture_output=True, text=True, errors="replace", timeout=900)
        if "[FAIL]" in r.stdout or r.returncode != 0 or "[PASS] THIRD.COMPILE" not in r.stdout:
            bail("the sandbox build did not pass:\n" + r.stdout[-800:])
        say("sandbox-mode-q16: built, bootstrap passed")
    elif not os.path.isfile(os.path.join(sysd, "bin", "sd")):
        bail("%s holds no built sandbox (use --build, or point it at one)" % box)
    subprocess.run([sys.executable, TOOL, box, "start"], capture_output=True, text=True, errors="replace", timeout=120)

    cmds, names = [], []
    for name, text, how in AUX:
        names.append(name)
        with open(os.path.join(sysd, "bp", name), "w") as f:
            f.write(text)
        if how == "sub":
            cmds += ["BASIC bp %s" % name, "CATALOG bp %s" % name]
    for i, (_label, body, _w, _h, _l) in enumerate(CASES):
        nm = "zzq16%02d" % i
        names.append(nm)
        with open(os.path.join(sysd, "bp", nm), "w") as f:
            f.write(source(i, body))
        cmds += ["BASIC bp %s" % nm, "RUN bp %s" % nm]
    try:
        out = sess(box, *cmds)
        if os.environ.get("SDSUITE_RAW"):
            say(out)
        say("\n--- the modes -----------------------------------------------------------------------")
        for i, (label, _body, want, has, lacks) in enumerate(CASES):
            # the compiler's output is what the session printed between this row's BASIC and RUN commands (each command
            # is echoed after the colon prompt, so the anchors are the echoes)
            m = re.search(r"(?s):BASIC bp zzq16%02d\b(.*?):RUN bp zzq16%02d\b" % (i, i), out)
            seg = m.group(1) if m else ""
            m = re.search(r"(?m)^C%02d\[(.*)\]\s*$" % i, out)
            got = m.group(1).replace("\xfd", "|") if m else None
            ok = (got == want) if want is not None else (got is None)
            ok = ok and all(w in seg for w in has) and not any(w in seg for w in lacks)
            say_want = "must not run" if want is None else repr(want)
            row("%s: wanted %s%s" % (label, say_want, "".join(", compile says %r" % w for w in has)), ok,
                "got %r, compiler said %r" % (got, " ".join(seg.split())[:300]))
    finally:
        for nm in names:
            for d in ("bp", "bp.out"):
                pth = os.path.join(sysd, d, nm)
                if os.path.exists(pth):
                    os.remove(pth)

    say("\nsandbox-mode-q16: %d passed, %d failed" % (passed, failed))
    sys.exit(0 if failed == 0 else 1)


if __name__ == "__main__":
    main()
