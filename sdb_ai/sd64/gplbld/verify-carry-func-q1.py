#!/usr/bin/env python3
#
# sandbox-func-q1.py - QM4 gaps bundle Q-1 (BASIC functions): CEIL FLOOR ROUNDUP ROUNDDOWN IS.ALNUM IS.ALPHA IS.DIGIT
# IS.GRAPH IS.MARK IS.SPACE LEFT RIGHT LAST LASTS NV NS TRIMWS MATCHESS MATCHFIELDS, all behind the one opcode XFUN.  No
# install, no sudo.
#
#   python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/sandbox-func-q1.py <dir> [--build]
#
# <dir> is a sandbox made by sandbox-fromtree.py (needs a `make`d bin/sd).  With --build it is built first from
# THIS tree (it must be empty or absent).  Exit 0 every row passed, 1 a row failed, 2 it could not run.
#
# START-HISTORY:
# 27 Oct 26 dm  S.87 batch 3: TERMINFO.EX (an alias of TERMINFO) was removed, with its two rows; the refusal is a row of sandbox-mode-q16.py.
# 15 Oct 26 dm  Written for QM4 gaps bundle Q-1.
# 15 Oct 26 dm  RMVD, REVREMOVE, GROUPSTORE and PARSE (the rest of Q-1), and TERMINFO.EX, TTYGET and TTYSET (Q-7).
# END-HISTORY
#
# THE INSTRUMENT IS THE VALUE A BASIC PROGRAM PRINTED between brackets, with the marks shown as letters: a field mark F, a
# value mark V, a subvalue mark S.  Where a function has an older relative that already works (INT, TRIMW, MATCHFIELD,
# FIELD) the row before it is that relative as the CONTROL.  The manual's own examples are used where it gives them.

import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.path.join(HERE, "sandbox-fromtree.py")
ANSI = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]")
passed = failed = 0

# (label, BASIC statements one per line leaving the value in x, wanted)
CASES = []
AUX = []   # (record name in bp, text): a subroutine, compiled and catalogued before the rows run


def case(label, body, want, has=(), lacks=()):
    CASES.append((label, body, want, tuple(has), tuple(lacks)))


def aux(name, text):
    AUX.append((name, text))


# ---- CEIL and FLOOR --------------------------------------------------------------------------------------------------
case("CONTROL: INT of 3.7 is 3", "x = int(3.7)", "3")
for v, c, f in [("0", "0", "0"), ("3", "3", "3"), ("3.1", "4", "3"), ("3.7", "4", "3"), ("-3", "-3", "-3"),
                ("-3.1", "-3", "-4"), ("-3.7", "-3", "-4"), ("-0.5", "0", "-1"), ("0.5", "1", "0"),
                ("1234567.25", "1234568", "1234567")]:
    case("CEIL(%s)" % v, "x = ceil(%s)" % v, c)
    case("FLOOR(%s)" % v, "x = floor(%s)" % v, f)
case("CEIL of an array is an array of the same shape",
     "x = ceil('1.2':@vm:'3.5':@fm:'-1.2':@sm:'7')", "2V4F-1S7")
case("FLOOR of an array is an array of the same shape",
     "x = floor('1.2':@vm:'3.5':@fm:'-1.2':@sm:'7')", "1V3F-2S7")
case("CEIL of a numeric string", "x = ceil('2.000001')", "3")

# ---- ROUNDUP and ROUNDDOWN: the manual's own table for steps of 3 ------------------------------------------------------
TABLE = [(-10, -9, -12), (-9, -9, -9), (-5, -3, -6), (-4, -3, -6), (-3, -3, -3), (-2, 0, -3), (-1, 0, -3), (0, 0, 0),
         (1, 0, 3), (2, 0, 3), (3, 3, 3), (4, 3, 6), (5, 3, 6), (6, 6, 6), (9, 9, 9), (10, 9, 12)]
for i, down, up in TABLE:
    case("ROUNDDOWN(%d, 3) and ROUNDUP(%d, 3)" % (i, i), "x = rounddown(%d, 3) : '/' : roundup(%d, 3)" % (i, i), "%d/%d" % (down, up))
case("ROUNDUP with a step of one is the value", "x = roundup(7, 1) : '/' : rounddown(7, 1)", "7/7")
case("ROUNDUP and ROUNDDOWN with a step under one give zero", "x = roundup(7, 0) : '/' : rounddown(7, 0) : '/' : roundup(7, -2)", "0/0/0")
case("ROUNDUP of a fractional value", "x = roundup(7.2, 3) : '/' : rounddown(7.9, 3)", "9/6")

# (IS.ALNUM IS.ALPHA IS.DIGIT IS.GRAPH IS.MARK IS.SPACE, LEFT and RIGHT were removed on 27 Oct 26, S.87 batch 13)

# ---- LAST and LASTS ----------------------------------------------------------------------------------------------------
case("CONTROL: FIELD with DCOUNT, the older way to the final element", "s = '1*2*3*4*5'\nx = field(s, '*', dcount(s, '*'))", "5")
case("LAST(string, delimiter), the manual's example", "x = last('1*2*3*4*5', '*')", "5")
case("LAST of a string with no delimiter is the whole string", "x = last('abc', '*')", "abc")
case("LAST of a string that ends in the delimiter is null", "x = last('a*b*', '*') : '/'", "/")
case("LAST of a null string is null", "x = last('', '*') : '/'", "/")
case("LAST sets COL1 and COL2 to the places either side of the element", "x = last('1*2*3*4*5', '*') : '/' : col1() : '/' : col2()", "5/8/10")
case("LASTS, the manual's example", "x = lasts('1*2*3*4*5':@vm:'A*B*C', '*')", "5VC")
case("LASTS keeps the structure of the array", "x = lasts('a*b':@fm:'c*d*e':@vm:'f', '*')", "bFeVf")

# ---- NV and NS: the manual's examples over 111 VM 121 SM 122 SM 123 VM 131 SM 132 FM 211 SM 212 VM 221 ------------
NVS = "s = '111':@vm:'121':@sm:'122':@sm:'123':@vm:'131':@sm:'132':@fm:'211':@sm:'212':@vm:'221'"
case("NV(s, 0), the manual's example", NVS + "\nx = nv(s, 0)", "1V2V3F1V2")
case("NV(s, 1), the manual's example", NVS + "\nx = nv(s, 1)", "1V2S2S2V3S3F1S1V2")
case("NS(s), the manual's example", NVS + "\nx = ns(s)", "1V1S2S3V1S2F1S2V1")
case("NV with no second argument is the same as repeat false", NVS + "\nx = nv(s)", "1V2V3F1V2")
case("NV of a one-value string", "x = nv('abc')", "1")
case("NV of values that are empty still numbers them", "x = nv(@vm:@vm)", "1V2V3")
case("NV of a null string is null", "x = nv('') : '/'", "/")
case("NS of a string with no subvalues gives 1 for every value", "x = ns('a':@vm:'b':@fm:'c')", "1V1F1")

# ---- TRIMWS, MATCHESS, MATCHFIELDS ------------------------------------------------------------------------------------
case("CONTROL: TRIMW", "x = trimw('  a   b ')", "a b")
case("TRIMWS trims every element of the array", "x = trimws('  a   b ':@vm:' c ':@fm:char(9):'d':char(10):char(10):'e')", "a bVcFd e")
case("CONTROL: MATCHES", "if 'A1' matches '1A1N' then x = 'yes' else x = 'no'", "yes")
case("MATCHESS gives 1 or 0 for every element", "x = matchess('A1':@vm:'B2':@vm:'3C':@fm:'D4', '1A1N')", "1V1V0F1")
case("CONTROL: MATCHFIELD", "x = matchfield('C22d', '1A0N0A', 2)", "22")
case("MATCHFIELDS gives the component of every element", "x = matchfields('A1b':@vm:'C22d':@fm:'E333f', '1A0N0A', 2)", "1V22F333")
case("MATCHFIELDS with a component that is not there is null", "x = matchfields('A1b':@vm:'C22d', '1A0N0A', 4) : '/'", "V/")

# ---- CASING and SYSTEM(1086) ------------------------------------------------------------------------------------------
CMP = "if 'ABC' = 'abc' then x = 'match' else x = 'no'"
case("CONTROL: the comparison is case sensitive and SYSTEM(1086) says so", CMP + "\nx = x : '/' : system(1086)", "no/1")
case("CASING OFF makes the comparison insensitive", "casing off\n" + CMP + "\nx = x : '/' : system(1086)", "match/0")
case("CASING ON turns it back", "casing off\ncasing on\n" + CMP + "\nx = x : '/' : system(1086)", "no/1")
case("CASING with an expression: false is off, true is on",
     "casing 0\n" + CMP + "\ny = x\ncasing (2 > 1)\n" + CMP + "\nx = y : '/' : x", "match/no")
case("CASING takes a variable", "c = 0\ncasing c\n" + CMP, "match")
case("CASING OFF reaches INDEX, COUNT, CHANGE and FIELD",
     "casing off\nx = index('ABC', 'b', 1) : '/' : count('aAa', 'a') : '/' : change('Abc', 'a', 'x') : '/' : field('aXbxc', 'x', 2)", "2/3/xbc/b")
case("CONTROL: those four on a case sensitive program",
     "x = index('ABC', 'b', 1) : '/' : count('aAa', 'a') : '/' : change('Abc', 'a', 'x') : '/' : field('aXbxc', 'x', 2)", "0/2/Abc/c")
case("$NOCASE.STRINGS starts the program with SYSTEM(1086) false", "$nocase.strings\n" + CMP + "\nx = x : '/' : system(1086)", "match/0")
case("CASING ON overrides $NOCASE.STRINGS at run time", "$nocase.strings\ncasing on\n" + CMP, "no")
aux("zzq1ca", "subroutine zzq1ca(r)\n   r = system(1086)\nreturn\nend\n")
case("CASING belongs to the program: a called subroutine has its own state",
     "casing off\ncall zzq1ca(r)\nx = r : '/' : system(1086)", "1/0")
# ---- SORT.COMPARE, COMPARES and MERGELIST: functions written in BASIC that the compiler knows by name ---------------------
SC_ITEMS = ("items = 'GC5':@fm:'ND620':@fm:'GC41':@fm:'CD631':@fm:'55':@fm:'3AB':@fm:'GC'\nn = dcount(items, @fm)\n"
            "for i = 1 to n - 1\n   for j = i + 1 to n\n      if sort.compare(items<j>, items<i>, %d) < 0 then\n"
            "         t = items<i> ; items<i> = items<j> ; items<j> = t\n      end\n   next j\nnext i\nx = change(items, @fm, ',')")
case("SORT.COMPARE mode 0 sorts the manual's seven items as the manual shows", SC_ITEMS % 0, "3AB,55,CD631,GC,GC41,GC5,ND620")
case("SORT.COMPARE mode 1 sorts them right justified", SC_ITEMS % 1, "55,GC,3AB,GC5,GC41,CD631,ND620")
case("SORT.COMPARE mode 2 sorts them as a compound sort", SC_ITEMS % 2, "3AB,55,CD631,GC,GC5,GC41,ND620")
case("SORT.COMPARE: left justified, 10 comes before 9; right justified, integers compare as numbers",
     "x = sort.compare('10', '9', 0) : '/' : sort.compare('10', '9', 1) : '/' : sort.compare('9', '10', 1)", "-1/1/-1")
case("SORT.COMPARE mode 1 takes a sign, and treats a number that is not an integer as text",
     "x = sort.compare('-5', '3', 1) : '/' : sort.compare('22.5', '9.99', 1) : '/' : sort.compare('22.5', '9.99', 3)", "-1/-1/1")
case("SORT.COMPARE equal strings, and the strings in the other order",
     "x = sort.compare('abc', 'abc', 0) : '/' : sort.compare('abd', 'abc', 0) : '/' : sort.compare('ab', 'abc', 0)", "0/1/-1")
case("SORT.COMPARE: SRT$NOCASE (64) and the fourth argument make it case blind",
     "x = sort.compare('abc', 'ABC', 0) : '/' : sort.compare('abc', 'ABC', 64) : '/' : sort.compare('abc', 'ABC', 0, 1) : '/' : sort.compare('abc', 'ABC', 0, 0)",
     "1/0/0/1")
case("SORT.COMPARE: SRT$DESCENDING (16) reverses the result",
     "x = sort.compare('a', 'b', 0) : '/' : sort.compare('a', 'b', 16) : '/' : sort.compare('10', '9', 17)", "-1/1/-1")
case("SORT.COMPARE: compound compare takes 28 and 028 as equal, SRT$STRICT (4) does not",
     "x = sort.compare('28', '028', 2) : '/' : sort.compare('28', '028', 4) : '/' : sort.compare('028', '28', 4) : '/' : sort.compare('A28', 'A28', 4)",
     "0/-1/1/0")
case("SORT.COMPARE: compound compare puts a leading number before text and compares the numbers as numbers",
     "x = sort.compare('3AB', 'GC', 2) : '/' : sort.compare('GC5', 'GC41', 2) : '/' : sort.compare('GC5', 'GC41', 0) : '/' : sort.compare('-2A', '1A', 2)",
     "-1/-1/1/-1")
case("CONTROL: COMPARE, the single form", "x = compare('a', 'b') : '/' : compare('9', '10', 'R') : '/' : compare('a', 'A', 'LI')", "-1/-1/0")
case("COMPARES compares the elements in the same places and gives the answers the same shape",
     "x = compares('a':@vm:'c':@fm:'x', 'b':@vm:'b':@fm:'x')", "-1V1F0")
case("COMPARES with a justification, and I for case blind",
     "x = compares('9':@vm:'a', '10':@vm:'A', 'R') : '/' : compares('a':@vm:'b', 'A':@vm:'B', 'LI') : '/' : compares('a', 'A')", "-1V1/0V0/1")
case("COMPARES where the arrays are not the same size compares the missing element as null",
     "x = compares('a':@vm:'b', 'a')", "0V1")
case("COMPARES of subvalues", "x = compares('a':@sm:'z', 'b':@sm:'a')", "-1S1")
ML = "$include syscom keys.h\nl1 = 'a':@fm:'b':@fm:'d':@fm:'f'\nl2 = 'b':@fm:'c':@fm:'d':@fm:'g'\n"
case("MERGELIST ML$INTER, the items in both lists", ML + "x = change(mergelist(l1, l2, ML$INTER), @fm, ',')", "b,d")
case("MERGELIST ML$UNION, the items in either, each once", ML + "x = change(mergelist(l1, l2, ML$UNION), @fm, ',')", "a,b,c,d,f,g")
case("MERGELIST ML$DIFF, the items of the first that are not in the second", ML + "x = change(mergelist(l1, l2, ML$DIFF), @fm, ',')", "a,f")
case("MERGELIST with ML$UNSORTED puts the lists in order first",
     "$include syscom keys.h\nl1 = 'd':@fm:'a':@fm:'f':@fm:'b'\nl2 = 'g':@fm:'b':@fm:'c':@fm:'d'\n"
     "x = change(mergelist(l1, l2, ML$INTER + ML$UNSORTED), @fm, ',') : '|' : change(mergelist(l1, l2, ML$UNION + ML$UNSORTED), @fm, ',')", "b,d|a,b,c,d,f,g")
case("MERGELIST with SRT$RIGHT merges numbers as numbers",
     "$include syscom keys.h\nl1 = '2':@fm:'10':@fm:'30'\nl2 = '10':@fm:'30':@fm:'40'\n"
     "x = change(mergelist(l1, l2, ML$INTER + SRT$RIGHT), @fm, ',') : '|' : change(mergelist(l1, l2, ML$UNION + SRT$RIGHT), @fm, ',')", "10,30|2,10,30,40")
case("MERGELIST with an empty list", "$include syscom keys.h\nx = change(mergelist('', 'a', ML$UNION), @fm, ',') : '|' : mergelist('', 'a', ML$INTER) : '|' : mergelist('a', '', ML$DIFF)",
     "a||a")
case("MERGELIST takes a select list variable", ML + "selectv l1 to sl\nx = change(mergelist(sl, l2, ML$INTER), @fm, ',')", "b,d")
aux("zzq1my", "function zzq1my(a, b, m)\n   return 42\nend\n")
case("A program's own DEFFUN of the name of a function SD knows takes its place", "deffun sort.compare(a, b, m) calling 'zzq1my'\nx = sort.compare('a', 'b', 0)", "42")

# ---- BOOL, IS.NULL, NUMERIC and REUSING (bundle Q-6) --------------------------------------------------------------------
for src, want in [("0", "0"), ("1", "1"), ("''", "0"), ("'abc'", "1"), ("0.0", "0"), ("'0.0'", "0"), ("'-0'", "0"), ("-3", "1"),
                  ("'false'", "1"), ("'0'", "0"), ("'00'", "0"), ("' '", "1"), ("0.001", "1")]:
    case("BOOL(%s) is %s" % (src, want), "x = bool(%s)" % src, want)
case("BOOL makes a Boolean: JTYPE says boolean, JBUILD writes true", "x = jtype(bool(5)) : '/' : jtype(5) : '/' : jtype(bool(''))",
     "boolean/number/boolean")
case("CONTROL: JBOOLEAN calls the text false false, which BOOL does not", "x = jboolean('false') : '/' : bool('false')", "0/1")
case("IS.NULL of JNULL() is true", "x = is.null(jnull())", "1")
case("IS.NULL of the empty string, zero and text is false", "x = is.null('') : '/' : is.null(0) : '/' : is.null('abc')", "0/0/0")
case("IS.NULL of a variable that holds the SQL null, and after it has been given an ordinary null",
     "v = jnull()\nx = is.null(v)\nv = ''\nx = x : '/' : is.null(v)", "1/0")
case("IS.NULL sees a null that came out of a collection", "c = collection()\nc{'a'} = jnull()\nx = is.null(c{'a'}) : '/' : jtype(c{'a'})", "1/null")
case("NUMERIC of a numeric string is the number", "x = numeric('007') : '/' : numeric('1.50') : '/' : numeric(5) : '/' : numeric('') : '/' : numeric('-2')",
     "7/1.5/5/0/-2")
case("NUMERIC is the same as adding zero", "s = '12.50'\nx = (numeric(s) = s + 0) : '/' : numeric(s) * 2", "1/25")
aux("zzq1ru", "subroutine zzq1ru(r, a, b)\n   r = reusing(a) : '/' : reusing(b)\nreturn\nend\n")
case("REUSING says whether an argument was passed with REUSE, and does not clear it",
     "v = 5\nw = 6\ncall zzq1ru(r, reuse(v), w)\nx = r", "1/0")
case("REUSING of a variable that is not an argument works on any variable (no flag: false)", "v = 5\nx = reusing(v)", "0")

# ---- ARG.PRESENT (bundle Q-7) -------------------------------------------------------------------------------------------
aux("zzq1ap", "subroutine zzq1ap(r, a, b, c) var.args\n   r = arg.present(a) : '/' : arg.present(b) : '/' : arg.present(c) : '/' : arg.count()\nreturn\nend\n")
aux("zzq1ad", "subroutine zzq1ad(r, a, b = 7) var.args\n   r = arg.present(b) : '/' : b\nreturn\nend\n")
aux("zzq1af", "function zzq1af(p, q) var.args\n   return arg.present(p) : '/' : arg.present(q) : '/' : arg.count()\nend\n")
case("ARG.PRESENT: only the first argument passed", "call zzq1ap(r, 1)\nx = r", "1/0/0/2")
case("ARG.PRESENT: two of the three passed", "call zzq1ap(r, 1, 2)\nx = r", "1/1/0/3")
case("ARG.PRESENT: all passed", "call zzq1ap(r, 1, 2, 3)\nx = r", "1/1/1/4")
case("ARG.PRESENT is not changed by a default value for the argument that was left out",
     "call zzq1ad(r, 1)\ny = r\ncall zzq1ad(r, 1, 5)\nx = y : '|' : r", "0/7|1/5")
case("ARG.PRESENT in a FUNCTION (the hidden return value is not counted)",
     "deffun zzq1af(p, q) var.args\ny = zzq1af(5)\nx = y : '|' : zzq1af(5, 1)", "1/0/1|1/1/2")
case("ARG.PRESENT of a name that is not an argument is a compile error",
     "@RAW@subroutine zzq1bad(r)\n   x = arg.present(zz)\nreturn\nend\n", None, has=["ZZ is not an argument of this subroutine or function"])
case("ARG.PRESENT in a program that is not a subroutine is a compile error",
     "@RAW@   x = arg.present(zz)\nend\n", None, has=["is not an argument of this subroutine or function"])
case("CASING with nothing after it is a compile error",
     "@RAW@   casing\nend\n", None, lacks=["0 error(s)"])

# ---- RMVD, REVREMOVE, GROUPSTORE, PARSE (the rest of bundle Q-1), TERMINFO.EX, TTYGET and TTYSET (bundle Q-7) ----------------
RM = "s = 'a':@fm:'b':@vm:'c'\n"
case("CONTROL: REMOVE gives each item and the code of the mark after it", RM + "r1 = remove(s, d1)\nr2 = remove(s, d2)\nr3 = remove(s, d3)\n"
     "x = r1 : '/' : d1 : '|' : r2 : '/' : d2 : '|' : r3 : '/' : d3", "a/2|b/3|c/0")
case("RMVD gives the same as REMOVE for field, value and subvalue marks", RM + "r1 = rmvd(s, d1)\nr2 = rmvd(s, d2)\nr3 = rmvd(s, d3)\n"
     "x = r1 : '/' : d1 : '|' : r2 : '/' : d2 : '|' : r3 : '/' : d3", "a/2|b/3|c/0")
case("RMVD takes a subvalue mark as the end of an item (code 4)", "s = 'p':@sm:'q'\nr1 = rmvd(s, d1)\nr2 = rmvd(s, d2)\nx = r1 : '/' : d1 : '|' : r2 : '/' : d2",
     "p/4|q/0")
case("CONTROL: REMOVE ends an item at a text mark (code 5)", "s = 'a':@tm:'b':@fm:'c'\nr1 = remove(s, d1)\nx = r1 : '/' : d1", "a/5")
case("RMVD leaves a text mark in the item: it is data", "s = 'a':@tm:'b':@fm:'c'\nr1 = rmvd(s, d1)\nx = change(r1, @tm, 'T') : '/' : d1", "aTb/2")
case("CONTROL: REMOVE ends an item at an item mark (code 1)", "s = 'a':@im:'b'\nr1 = remove(s, d1)\nx = r1 : '/' : d1", "a/1")
case("RMVD leaves an item mark in the item, to the end of the string", "s = 'a':@im:'b'\nr1 = rmvd(s, d1)\nx = change(r1, @im, 'I') : '/' : d1", "aIb/0")
case("RMVD and REMOVE share the remove pointer", "s = 'a':@fm:'b':@fm:'c'\nr1 = remove(s, d1)\nr2 = rmvd(s, d2)\nr3 = remove(s, d3)\n"
     "x = r1 : '/' : d1 : '|' : r2 : '/' : d2 : '|' : r3 : '/' : d3", "a/2|b/2|c/0")
case("RMVD past the end gives a null string and 0", "s = 'a'\nr1 = rmvd(s, d1)\nr2 = rmvd(s, d2)\nr3 = rmvd(s, d3)\nx = r1 : '/' : d1 : '|' : r2 : '/' : d2 : '|' : r3 : '/' : d3",
     "a/0|/0|/0")
case("Assigning the string again puts the RMVD pointer back to the start", "s = 'a':@fm:'b'\nr1 = rmvd(s, d1)\ns = s\nr2 = rmvd(s, d2)\nx = r1 : '|' : r2", "a|a")
case("RMVD of a number works on its text", "s = 99\nr1 = rmvd(s, d1)\nx = r1 : '/' : d1", "99/0")
case("RMVD of a null string", "s = ''\nr1 = rmvd(s, d1)\nx = r1 : '/' : d1", "/0")

case("REVREMOVE walks a string from the end, giving the mark in front of each item and 0 for the first",
     RM + "setrem len(s) on s\nrevremove i1 from s setting d1\nrevremove i2 from s setting d2\nrevremove i3 from s setting d3\n"
     "x = i1 : '/' : d1 : '|' : i2 : '/' : d2 : '|' : i3 : '/' : d3", "c/3|b/2|a/0")
case("REVREMOVE with a null item in the middle", "s = 'a':@fm:@fm:'c'\nsetrem len(s) on s\nrevremove i1 from s setting d1\nrevremove i2 from s setting d2\n"
     "revremove i3 from s setting d3\nx = i1 : '/' : d1 : '|' : i2 : '/' : d2 : '|' : i3 : '/' : d3", "c/2|/2|a/0")
case("REVREMOVE of a string that starts with a mark ends on the null first item", "s = @fm:'a'\nsetrem len(s) on s\nrevremove i1 from s setting d1\n"
     "revremove i2 from s setting d2\nx = i1 : '/' : d1 : '|' : i2 : '/' : d2", "a/2|/0")
case("REVREMOVE of a string with no mark is the whole string and 0", "s = 'abc'\nsetrem len(s) on s\nrevremove i1 from s setting d1\nx = i1 : '/' : d1", "abc/0")
case("REVREMOVE with the pointer at the start (no SETREM) gives a null string and 0", "s = 'a':@fm:'b'\nrevremove i1 from s setting d1\nx = i1 : '/' : d1", "/0")
case("REVREMOVE from a pointer set part way takes the items before it", "s = 'ab':@fm:'cd':@fm:'ef'\nsetrem 5 on s\nrevremove i1 from s setting d1\nrevremove i2 from s setting d2\n"
     "x = i1 : '/' : d1 : '|' : i2 : '/' : d2", "cd/2|ab/0")
case("REVREMOVE of a string of 3000 items, which is in many chunks, gives them all in reverse order",
     "s = ''\nfor n = 1 to 3000\n   s<-1> = 'item':n\nnext n\nsetrem len(s) on s\ncnt = 0\nbad = 0\nloop\n   revremove it from s setting d\n   cnt += 1\n"
     "   if it # 'item':(3001 - cnt) then bad += 1\nwhile d\nrepeat\nx = cnt : '/' : bad : '/' : it", "3000/0/item1")
case("REVREMOVE of one item that is longer than a chunk keeps all of it", "s = str('x', 20000) : @fm : 'y'\nsetrem len(s) on s\nrevremove i1 from s setting d1\n"
     "revremove i2 from s setting d2\nx = i1 : '/' : d1 : '|' : len(i2) : '/' : d2", "y/2|20000/0")

S5 = "s = '1*2*3*4*5'\n"
case("CONTROL: FIELDSTORE with the manual's first example", "x = fieldstore('1*2*3*4*5', '*', 2, 3, 'A*B')", "1*A*B**5")
case("GROUPSTORE, the manual's first example: fewer substrings than are replaced", S5 + "groupstore 'A*B' in s using 2, 3, '*'\nx = s", "1*A*B**5")
case("GROUPSTORE, as many substrings as are replaced", S5 + "groupstore 'A*B*C' in s using 2, 3, '*'\nx = s", "1*A*B*C*5")
case("GROUPSTORE, more substrings than are replaced: the last is not inserted", S5 + "groupstore 'A*B*C*D' in s using 2, 3, '*'\nx = s", "1*A*B*C*5")
case("GROUPSTORE, n zero: nothing is deleted", S5 + "groupstore 'A*B' in s using 2, 0, '*'\nx = s", "1*A*B*2*3*4*5")
case("GROUPSTORE, n negative: that many are deleted and all of the new data goes in", S5 + "groupstore 'A*B' in s using 2, -3, '*'\nx = s", "1*A*B*5")
case("GROUPSTORE, i below one is taken as one", S5 + "groupstore 'A' in s using 0, 1, '*'\nx = s", "A*2*3*4*5")
case("GROUPSTORE, i beyond the end adds delimiters", "s = '1*2'\ngroupstore 'Z' in s using 5, 1, '*'\nx = s", "1*2***Z")
case("GROUPSTORE with no delimiter uses a field mark", "s = 'a':@fm:'b':@fm:'c'\ngroupstore 'X' in s using 2, 1\nx = s", "aFXFc")
case("GROUPSTORE takes variables for the data, the position, the count and the delimiter", S5 + "r = 'Q'\np = 4\nc = 1\nd = '*'\ngroupstore r in s using p, c, d\nx = s",
     "1*2*3*Q*5")
case("GROUPSTORE changes an element of an array", "dim a(3)\na(2) = '1*2*3'\ngroupstore 'Z' in a(2) using 2, 1, '*'\nx = a(2)", "1*Z*3")
case("GROUPSTORE changes the variable of the caller only (a copy is not changed)", S5 + "t = s\ngroupstore 'A' in s using 1, 1, '*'\nx = s : '|' : t", "A*2*3*4*5|1*2*3*4*5")
case("GROUPSTORE without IN is a compile error", "@RAW@   s = 'a'\n   groupstore 'A' s using 1, 1\nend\n", None, lacks=["0 error(s)"])
case("GROUPSTORE without USING is a compile error", "@RAW@   s = 'a'\n   groupstore 'A' in s 1, 1\nend\n", None, lacks=["0 error(s)"])

case("PARSE, the manual's example: a telephone number", "x = parse('01604-709200', \"0N'-'0N\", '|')", "01604|-|709200")
case("PARSE: 0X takes as few characters as it can, and the pattern 0X2N0X splits ABC123DEF as ABC, 12 and 3DEF",
     "x = parse('ABC123DEF', '0X2N0X', '|')", "ABC|12|3DEF")
case("PARSE: 2-3N takes as many digits as it can: ABC, 123 and DEF", "x = parse('ABC123DEF', '0X2-3N0X', '|')", "ABC|123|DEF")
case("PARSE gives a null string when the string does not match", "x = parse('abc', '3N', '|') : '/'", "/")
case("PARSE with alternatives takes the first that matches", "x = parse('ab12', '3N' : @vm : '2A2N' : @vm : '4X', '|')", "ab|12")
case("PARSE: the delimiter is a field mark if it is null", "x = parse('ab12', '2A2N', '')", "abF12")
case("PARSE uses only the first character of the delimiter", "x = parse('ab12', '2A2N', '+-')", "ab+12")
case("PARSE: the three dots are 0X", "x = parse('ab12cd', '...2N...', '|') : '/' : parse('abc', '...', '|')", "ab|12|cd/abc")
case("PARSE: a tilde inverts, so ~4N matches four characters that are not digits", "x = parse('ABCD', '~4N', '|') : '/' : parse('12C4', '~4N', '|') : '/'", "ABCD//")
case("PARSE: a quoted literal is an element of its own", "x = parse('ab-12', '2A\"-\"2N', '/')", "ab/-/12")
case("PARSE of a null string against patterns that match it", "x = parse('', '0N', '|') : '/' : parse('', '0N0A', '|') : '/' : parse('', '0N\"x\"', '|') : '/'", "/|//")
case("PARSE: either kind of quote makes a literal", "x = parse('a:b', \"1A':'1A\", '|')", "a|:|b")

case("SYSTEM(1088) after MAXIMUM is the position of the greatest: the manual's example gives 2VM1VM1", "s = '61':@vm:'42':@fm:'71':@vm:'57'\nm = maximum(s)\n"
     "x = m : '/' : system(1088)", "71/2V1V1")
case("SYSTEM(1088) after MINIMUM is the position of the least", "s = '61':@vm:'42':@fm:'71':@vm:'57'\nm = minimum(s)\nx = m : '/' : system(1088)", "42/1V2V1")
case("SYSTEM(1088): the first of equal elements, and a subvalue", "s = '5':@fm:'9':@vm:'9':@sm:'9'\nm = maximum(s)\nx = m : '/' : system(1088)", "9/2V1V1")
case("SYSTEM(1088): subvalue numbers count from 1 in each value", "s = 'a':@fm:'1':@vm:'2':@sm:'7':@sm:'3'\nm = maximum(s)\nx = m : '/' : system(1088)", "7/2V2V2")
case("SYSTEM(1088): text and null elements are not counted as the greatest, but are counted in the position",
     "s = 'x':@vm:'':@vm:'4':@vm:'abc':@vm:'6'\nm = maximum(s)\nx = m : '/' : system(1088)", "6/1V5V1")
case("SYSTEM(1088) is null when the array is null, or has no number", "m = maximum('')\nx = system(1088) : '/' : (m = '')\nm = minimum('abc')\nx = x : '|' : system(1088) : '/' : (m = '')", "/1|/1")
case("MAXIMUM and MINIMUM are the same as before: the values", "s = '3':@vm:'-2':@fm:'10':@sm:'x':@vm:'0.5'\nx = maximum(s) : '/' : minimum(s)", "10/-2")
case("CHILD of this session's own number, of 0 and of a number nobody has is false, and of a null string", "x = child(@userno) : child(0) : child(32000) : child('')", "0000")
case("SYSTEM(1062) is 0 until SIGNAL has been raised", "x = system(1062) : system(1062)", "00")
case("SIGNAL of this session's own number is true, SYSTEM(1062) then reads it once and clears it", "x = signal(@userno) : '/' : system(1062) : system(1062)", "1/10")
case("SIGNAL twice is one signal", "x = signal(@userno) : signal(@userno) : '/' : system(1062) : system(1062)", "11/10")
case("SIGNAL of 0, a negative number, a number nobody has and a null string is false and raises nothing",
     "x = signal(0) : signal(-3) : signal(32000) : signal('') : '/' : system(1062)", "0000/0")
OSQ = ("openseq 'zzq1send.txt' to f then null else\n   create f else stop 'no create'\nend\nweofseq f\n")
OSR = ("closeseq f\nopenseq 'zzq1send.txt' to f else stop 'no reopen'\nreadblk b from f, 100 else b = 'none'\ncloseseq f\ndeleteseq 'zzq1send.txt' else null\n"
       "x = x : change(b, char(10), 'N')\n")
case("SEND writes the string and a newline, SEND with a colon writes the string alone", OSQ + "send 'one' to f then null else x = 'e1'\nsend 'two' : to f then null else x = 'e2'\n"
     "send 'three' to f else x = 'e3'\n" + OSR, "oneNtwothreeN")
case("SEND of an expression with colons of its own: only the last colon is the statement's", OSQ + "a = 'p'\nsend a : 'q' : to f then null else null\nsend a : 'r' to f else null\n" + OSR, "pqprN")
case("SEND with no TO is a compile error", "@RAW@   send 'a' f then null\nend\n", None, lacks=["0 error(s)"])
OSB = ("oswrite 'a':@fm:'b':@vm:'c':char(10):'d' to 'zzq1os.bin'\nosread r from 'zzq1os.bin' then ok = 1 else ok = 0\nosdelete 'zzq1os.bin'\n"
       "osread r2 from 'zzq1os.bin' then gone = 0 else gone = 1\n")
case("OSWRITE then OSREAD gives the same bytes: field and value marks and a newline are not changed, and OSDELETE removes the file",
     OSB + "x = ok : '/' : (r = 'a':@fm:'b':@vm:'c':char(10):'d') : '/' : gone : '/' : (r2 = '')", "1/1/1/1")
case("OSREAD of a file that is not there takes ELSE and leaves the variable null",
     "d = 'old'\nosread d from 'zzq1.nonesuch' then x = 'then' else x = 'else'\nx = x : '/' : (d = '')", "else/1")
case("OSWRITE replaces the file and cuts it to the new length", "oswrite 'longer text' to 'zzq1os2.txt'\noswrite 'ab' to 'zzq1os2.txt'\n"
     "osread r from 'zzq1os2.txt' then x = r else x = 'e'\nosdelete 'zzq1os2.txt'", "ab")
case("OSWRITE of a null string makes an empty file that OSREAD reads", "oswrite '' to 'zzq1os3.txt'\n"
     "osread r from 'zzq1os3.txt' then x = 'then/' : len(r) else x = 'else'\nosdelete 'zzq1os3.txt'", "then/0")
case("OSWRITE of text that is more than one block (70000 characters) reads back whole",
     "oswrite str('abcdefghij', 7000) to 'zzq1os5.txt'\nosread r from 'zzq1os5.txt' then x = len(r) : '/' : (r = str('abcdefghij', 7000)) else x = 'e'\n"
     "osdelete 'zzq1os5.txt'", "70000/1")
case("OSDELETE of a file that is not there reports nothing and the program goes on", "osdelete 'zzq1.nonesuch'\nx = 'went on'", "went on")
case("ACCOUNT.PATH of an account that is not there is a null string, and of the account itself is a path ending in its name",
     "a = account.path(@who)\nx = account.path('zzq1.nosuch') : '/' : (a # '') : '/' : (a[1,1] = '/') : '/' : (a = account.path(upcase(@who)))", "/1/1/1")
case("VOCPATH of a VOC file name is its path and STATUS() is 0, and of one that is not there is a null string with a status",
     "p = vocpath('bp')\nst1 = status()\nq = vocpath('zzq1.nosuch')\nst2 = status()\nx = (p # '') : (p[1,1] = '/') : '/' : st1 : '/' : (q = '') : (st2 # 0)", "11/0/11")
case("VOCPATH with DICT in front, and with the second argument true, give the dictionary part",
     "d1 = vocpath('DICT voc')\nd2 = vocpath('voc', @true)\nd3 = vocpath('voc', @false)\nd4 = vocpath('voc')\nx = (d1 # '') : (d1 = d2) : (d3 = d4) : (d1 # d4)", "1111")
case("OSREAD without FROM is a compile error", "@RAW@   osread d 'x' then null\nend\n", None, lacks=["0 error(s)"])
case("OSWRITE without TO is a compile error", "@RAW@   oswrite 'a' 'f'\nend\n", None, lacks=["0 error(s)"])
case("TTYGET gives eleven fields", "t = ttyget()\nx = dcount(t, @fm)", "11")
case("TTYGET: the break and case inversion fields are 0 or 1", "t = ttyget()\nx = (t<1> = 0 or t<1> = 1) : '/' : (t<2> = 0 or t<2> = 1) : '/' : (t<3> > 0)", "1/1/1")
case("TTYSET puts back what TTYGET gave", "t1 = ttyget()\nttyset t1\nt2 = ttyget()\nx = (t1 = t2)", "1")
case("TTYSET changes the modes, and TTYSET of the saved array changes them back",
     "t1 = ttyget()\nt2 = t1\nt2<6> = 1 - t1<6>\nt2<8> = 1 - t1<8>\nt2<3> = 2\nttyset t2\nt3 = ttyget()\nttyset t1\nt4 = ttyget()\n"
     "x = (t3<6> = t2<6>) : (t3<8> = t2<8>) : (t3<3> = 2) : (t3 # t1) : '/' : (t4 = t1)", "1111/1")
case("TTYSET leaves a mode alone when its field is null", "t1 = ttyget()\nttyset ''\nttyset @fm : @fm\nx = (ttyget() = t1)", "1")
case("TTYSET with the fields of the manual only (five of them) sets those", "t1 = ttyget()\nt2 = field(t1, @fm, 1, 5)\nt2<2> = 1 - t1<2>\nttyset t2\nt3 = ttyget()\nx = (t3<2> # t1<2>) : '/' : (t3<6,1> = t1<6,1>)\n"
     "ttyset t1", "1/1")


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
    say("sandbox-func-q1: CANNOT RUN - " + msg)
    sys.exit(2)


def sess(box, *cmds):
    say("    > %d commands" % len(cmds))
    p = subprocess.run([sys.executable, TOOL, box, "sess", os.path.join(box, "user_accounts")] + list(cmds),
                       capture_output=True, text=True, timeout=900)
    out = ANSI.sub("", p.stdout + p.stderr)
    return out.split(":TERM 200,9999", 1)[-1]


def source(i, body):
    # a body that starts with @RAW@ is the whole program, written as given
    if body.startswith("@RAW@"):
        return body[5:]
    # $NOCASE.STRINGS has to come before any executable statement, so it goes above the x = '' line
    lines = [ln for ln in body.split("\n") if ln.lower() == "$nocase.strings"]
    lines.append("   x = ''")
    lines += [("   " + ln) for ln in body.split("\n") if ln.lower() != "$nocase.strings"]
    # the marks of the answer are shown as letters, so a row is one line of plain text
    lines.append("   x = change(change(change(x, @fm, 'F'), @vm, 'V'), @sm, 'S')")
    lines.append("   crt 'C%03d[':x:']'" % i)
    lines.append("end")
    return "\n".join(lines) + "\n"


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) != 1:
        bail("usage: sandbox-func-q1.py <dir> [--build]")
    box = os.path.abspath(args[0])
    sysd = os.path.join(box, "sys")
    say("sandbox-func-q1: sandbox %s" % box)
    if "--build" in sys.argv:
        if os.path.exists(box) and os.listdir(box):
            bail("%s is not empty" % box)
        r = subprocess.run([sys.executable, TOOL, box, "all"], capture_output=True, text=True, errors="replace", timeout=900)
        if "[FAIL]" in r.stdout or r.returncode != 0 or "[PASS] THIRD.COMPILE" not in r.stdout:
            bail("the sandbox build did not pass:\n" + r.stdout[-800:])
        say("sandbox-func-q1: built, bootstrap passed")
    elif not os.path.isfile(os.path.join(sysd, "bin", "sd")):
        bail("%s holds no built sandbox (use --build, or point it at one)" % box)
    subprocess.run([sys.executable, TOOL, box, "start"], capture_output=True, text=True, errors="replace", timeout=120)

    cmds, names = [], []
    for name, text in AUX:
        names.append(name)
        with open(os.path.join(sysd, "bp", name), "w") as f:
            f.write(text)
        cmds += ["BASIC bp %s" % name, "CATALOG bp %s" % name]
    for i, (_label, body, _w, _h, _l) in enumerate(CASES):
        nm = "zzq1%03d" % i
        names.append(nm)
        with open(os.path.join(sysd, "bp", nm), "w") as f:
            f.write(source(i, body))
        cmds += ["BASIC bp %s" % nm, "RUN bp %s" % nm]
    try:
        out = sess(box, *cmds)
        if os.environ.get("SDSUITE_RAW"):
            say(out)
        say("\n--- the functions -------------------------------------------------------------")
        for i, (label, _body, want, has, lacks) in enumerate(CASES):
            m = re.search(r"(?s):BASIC bp zzq1%03d\b(.*?):RUN bp zzq1%03d\b" % (i, i), out)
            seg = m.group(1) if m else ""
            m = re.search(r"(?m)^C%03d\[(.*)\]\s*$" % (i,), out)
            got = m.group(1) if m else None
            ok = (got == want) if want is not None else (got is None)
            ok = ok and all(w in seg for w in has) and not any(w in seg for w in lacks)
            row("%s: wanted %r" % (label, want), ok, "got %r, compiler said %r" % (got, " ".join(seg.split())[:300]))
    finally:
        for nm in names:
            for d in ("bp", "bp.out"):
                pth = os.path.join(sysd, d, nm)
                if os.path.exists(pth):
                    os.remove(pth)

    say("\nsandbox-func-q1: %d passed, %d failed" % (passed, failed))
    sys.exit(0 if failed == 0 else 1)


if __name__ == "__main__":
    main()
