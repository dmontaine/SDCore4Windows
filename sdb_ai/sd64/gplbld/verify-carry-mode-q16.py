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
# 15 Oct 26 dm  Written for QM4 gaps bundle Q-16: CHANGE.NO.OVERLAP, COUNT.OVERLAP, INDEX.OVERLAP, PICK.CONVERT,
#               CONDITIONAL.STATEMENTS, TRAP.UNUSED.MAIN.
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


# ---- the three overlap modes -----------------------------------------------------------------------------------
# The manual's own examples, over nine a's.
S9 = "'aaaaaaaaa'"
case("CONTROL: CHANGE from the 3rd occurrence, overlapping occurrences are skipped one byte at a time",
     "x = change(%s, 'aa', 'xx', 0, 3)" % S9, "aaxxxxxxa")
case("Q-16 CHANGE.NO.OVERLAP: the two skipped occurrences are passed over whole",
     "$mode change.no.overlap\nx = change(%s, 'aa', 'xx', 0, 3)" % S9, "aaaaxxxxa")
case("CONTROL: SWAP, same string, no start argument (SWAP replaces all)",
     "x = swap(%s, 'aa', 'xx')" % S9, "xxxxxxxxa")
case("Q-16 CHANGE.NO.OVERLAP leaves a replace-all alone (nothing is skipped)",
     "$mode change.no.overlap\nx = swap(%s, 'aa', 'xx')" % S9, "xxxxxxxxa")
case("CONTROL: EREPLACE from the 3rd occurrence",
     "x = ereplace(%s, 'aa', 'xx', 0, 3)" % S9, "aaxxxxxxa")
case("Q-16 CHANGE.NO.OVERLAP reaches EREPLACE",
     "$mode change.no.overlap\nx = ereplace(%s, 'aa', 'xx', 0, 3)" % S9, "aaaaxxxxa")
case("Q-16 CHANGE.NO.OVERLAP, one occurrence only (the 3rd, counting without overlap)",
     "$mode change.no.overlap\nx = change(%s, 'aa', 'xx', 1, 3)" % S9, "aaaaxxaaa")
case("CONTROL: CHANGE.NO.OVERLAP on a pattern of one character is the same as without",
     "$mode change.no.overlap\nx = change('abcabc', 'b', 'X', 0, 2)", "abcaXc")
case("Q-16 CHANGE.NO.OVERLAP with a pattern that overlaps itself by one (aba in ababababa): 1-3 is skipped whole",
     "$mode change.no.overlap\nx = change('ababababa', 'aba', 'X', 0, 2)", "ababXba")
case("CONTROL: the same without the mode finds the 2nd occurrence at position 3",
     "x = change('ababababa', 'aba', 'X', 0, 2)", "abXbX")
case("Q-16 CHANGE.NO.OVERLAP works with NOCASE.STRINGS (the skipped text keeps the source's case)",
     "$nocase.strings\n$mode change.no.overlap\nx = change('AaAaAaAaA', 'aa', 'xx', 0, 3)", "AaAaxxxxA")
case("CONTROL: COUNT of overlapping a's is 4 by default",
     "x = count(%s, 'aa')" % S9, "4")
case("Q-16 COUNT.OVERLAP counts every position (8)",
     "$mode count.overlap\nx = count(%s, 'aa')" % S9, "8")
case("Q-16 COUNT.OVERLAP does not change DCOUNT (a delimiter, never overlapping)",
     "$mode count.overlap\nx = dcount('a*b**c', '*')", "4")
case("CONTROL: COUNTS is 4 and 1 by default",
     "x = change(counts(%s:@vm:'aaa', 'aa'), @vm, '|')" % S9, "4|1")
case("Q-16 COUNT.OVERLAP reaches COUNTS (8 and 2)",
     "$mode count.overlap\nx = change(counts(%s:@vm:'aaa', 'aa'), @vm, '|')" % S9, "8|2")
case("Q-16 COUNT.OVERLAP leaves INDEX alone",
     "$mode count.overlap\nx = index(%s, 'aa', 3)" % S9, "5")
case("CONTROL: INDEX of the 3rd 'aa' is 5 by default",
     "x = index(%s, 'aa', 3)" % S9, "5")
case("Q-16 INDEX.OVERLAP: the 3rd occurrence starts at 3",
     "$mode index.overlap\nx = index(%s, 'aa', 3)" % S9, "3")
case("Q-16 INDEX.OVERLAP: the 1st occurrence is where it always was",
     "$mode index.overlap\nx = index(%s, 'aa', 1)" % S9, "1")
case("Q-16 INDEX.OVERLAP: the 9th has no room, so zero (8 overlapping occurrences exist, not 9)",
     "$mode index.overlap\nx = index(%s, 'aa', 9)" % S9, "0")
case("Q-16 INDEX.OVERLAP: the 8th is at 8",
     "$mode index.overlap\nx = index(%s, 'aa', 8)" % S9, "8")
case("CONTROL: INDEXS with the 2nd occurrence is 3 and 0 by default",
     "x = change(indexs(%s:@vm:'aaa', 'aa', 2), @vm, '|')" % S9, "3|0")
case("Q-16 INDEX.OVERLAP reaches INDEXS (2 and 2)",
     "$mode index.overlap\nx = change(indexs(%s:@vm:'aaa', 'aa', 2), @vm, '|')" % S9, "2|2")
case("Q-16 INDEX.OVERLAP leaves COUNT alone",
     "$mode index.overlap\nx = count(%s, 'aa')" % S9, "4")
case("Q-16 two modes together: CHANGE.NO.OVERLAP and INDEX.OVERLAP, one comma list",
     "$mode change.no.overlap, index.overlap\nx = change(%s, 'aa', 'xx', 0, 3) : '/' : index(%s, 'aa', 3)" % (S9, S9),
     "aaaaxxxxa/3")
case("Q-16 $MODE -INDEX.OVERLAP turns it off from that line on",
     "$mode index.overlap\ny = index(%s, 'aa', 3)\n$mode -index.overlap\nx = y : '/' : index(%s, 'aa', 3)" % (S9, S9), "3/5")
case("Q-16 $MODE DEFAULT turns every overlap mode off",
     "$mode index.overlap, count.overlap\n$mode default\nx = count(%s, 'aa') : '/' : index(%s, 'aa', 3)" % (S9, S9), "4/5")
case("Q-16 the modes can come back on after being turned off",
     "$mode index.overlap\n$mode -index.overlap\n$mode index.overlap\nx = index(%s, 'aa', 3)" % S9, "3")
case("Q-16 a call before the directive in the source is not changed by it",
     "y = index(%s, 'aa', 3)\n$mode index.overlap\nx = y : '/' : index(%s, 'aa', 3)" % (S9, S9), "5/3")
case("Q-16 an unknown mode name is still refused",
     "$mode index.overlapped\nx = 1", None, has=["Unrecognised mode name"])

# The modes belong to the program that set them: a called subroutine is compiled on its own terms, and the caller's
# modes come back when it returns.
aux("zzq16sa", "subroutine zzq16sa(r)\n   r = index('aaaaaaaaa', 'aa', 3)\nreturn\nend\n", "sub")
aux("zzq16sb", "$mode index.overlap\nsubroutine zzq16sb(r)\n   r = index('aaaaaaaaa', 'aa', 3)\nreturn\nend\n", "sub")
case("Q-16 a subroutine compiled without the mode is not changed by its caller's",
     "$mode index.overlap\ncall zzq16sa(r)\nx = r : '/' : index(%s, 'aa', 3)" % S9, "5/3")
case("Q-16 a subroutine compiled with the mode does not change its caller, and the caller keeps its own after the call",
     "call zzq16sb(r)\nx = r : '/' : index(%s, 'aa', 3)" % S9, "3/5")
case("Q-16 the caller's mode is still there after a call to a subroutine that has none",
     "$mode index.overlap\ncall zzq16sa(r)\ncall zzq16sa(r2)\nx = index(%s, 'aa', 3)" % S9, "3")

# ---- PICK.CONVERT ------------------------------------------------------------------------------------------------
case("CONTROL: CONVERT(from, to, string)", "x = convert('ab', 'xy', 'abcab')", "xycxy")
case("Q-16 PICK.CONVERT: CONVERT(string, from, to)",
     "$mode pick.convert\nx = convert('abcab', 'ab', 'xy')", "xycxy")
case("Q-16 PICK.CONVERT: a shorter to-list deletes the characters it has no partner for",
     "$mode pick.convert\nx = convert('abcab', 'ab', 'x')", "xcx")
case("Q-16 PICK.CONVERT: calls nest, the string is the first argument at each level",
     "$mode pick.convert\nx = convert(convert('abcab', 'a', 'z'), 'b', 'y')", "zycz" + "y")
case("Q-16 PICK.CONVERT applies from its line on: $MODE -PICK.CONVERT brings the old order back",
     "$mode pick.convert\ny = convert('abcab', 'ab', 'xy')\n$mode -pick.convert\nx = y : '/' : convert('ab', 'xy', 'abcab')",
     "xycxy/xycxy")
case("Q-16 PICK.CONVERT leaves the CONVERT statement alone",
     "$mode pick.convert\ns = 'abcab'\nconvert 'ab' to 'xy' in s\nx = s", "xycxy")
case("Q-16 PICK.CONVERT with a field mark in the string (the list of characters is not a pattern)",
     "$mode pick.convert\nx = change(convert('a' : @fm : 'b', @fm, '/'), '/', '|')", "a|b")

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

# ---- PICK.SELECT -------------------------------------------------------------------------------------------------
# List 0 is made with FORMLIST, two ids that are in no file; the file the SELECTV names is the VOC.
PS = ("open 'VOC' to v else x = 'noopen'\nformlist 'k1':@fm:'k2'\n")
case("CONTROL: SELECTV with list 0 active selects from the file as always; list 0 is left alone",
     PS + "selectv v to lst\nreadnext id1 from lst else id1 = 'none'\nx = (id1 # 'k1') : '/' : system(11)", "1/1")
case("Q-16 PICK.SELECT: SELECTV moves list 0 to the variable, ignoring the file",
     "$mode pick.select\n" + PS + "selectv v to lst\nreadnext id1 from lst else id1 = 'none'\nreadnext id2 from lst else id2 = 'none'\n"
     "readnext id3 from lst else id3 = 'none'\nx = id1 : '/' : id2 : '/' : id3 : '/' : system(11)", "k1/k2/none/0")
case("Q-16 PICK.SELECT: with no list 0 active SELECTV selects from the file",
     "$mode pick.select\nopen 'VOC' to v else x = 'noopen'\nselectv v to lst\nreadnext id1 from lst else id1 = 'none'\n"
     "x = (id1 # 'none') : '/' : system(11)", "1/0")
case("Q-16 PICK.SELECT reaches SELECT when $MODE SELECTV makes it a SELECTV",
     "$mode selectv, pick.select\n" + PS + "select v to lst\nreadnext id1 from lst else id1 = 'none'\nx = id1 : '/' : system(11)", "k1/0")
case("Q-16 PICK.SELECT leaves a numbered SELECT alone (list 0 stays, the file is selected into list 3)",
     "$mode pick.select\n" + PS + "select v to 3\nreadnext id1 from 3 else id1 = 'none'\nx = (id1 # 'k1') : '/' : system(11)", "1/1")
case("Q-16 PICK.SELECT: $MODE -PICK.SELECT puts the old behaviour back",
     "$mode pick.select\n$mode -pick.select\n" + PS + "selectv v to lst\nreadnext id1 from lst else id1 = 'none'\n"
     "x = (id1 # 'k1') : '/' : system(11)", "1/1")

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
