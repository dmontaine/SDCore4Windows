#!/usr/bin/env python3
#
# sandbox-coll.py - 1.2-0 data collections (openQM "Data Collections").  No install, no sudo.
#
#   python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/sandbox-coll.py <dir> [--build]
#
# <dir> is a sandbox made by sandbox-fromtree.py (needs a `make`d bin/sd).  With --build it is built first from
# THIS tree (it must be empty or absent).  Exit 0 every row passed, 1 a row failed, 2 it could not run.
#
# START-HISTORY:
# 13 Oct 26 dm  Written for the first slice: COLLECTION(), c{path} get / set / DEL, ELEMENT.EXISTS(), ENUMERATE().
# END-HISTORY
#
# THE INSTRUMENT IS THE VALUE A BASIC PROGRAM PRINTED between brackets (marks shown as F V S).  A row whose program
# is meant to stop with a run time error is read from the whole output instead.  Each feature has a CONTROL row on
# the line before it where there is an existing feature to compare it with.

import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.path.join(HERE, "sandbox-fromtree.py")
ANSI = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]")
passed = failed = 0

C = "c = collection()\n   "
OPENF = "open 'zzcf' to f else stop 'no zzcf'\n   "

# (label, BASIC statements one per line leaving the value in x, wanted)   wanted starting with "ERR:" is a text the
# output must hold because the program must stop with a run time error.
CASES = [
    ("CONTROL: a dynamic array field is still read with angle brackets", "a = 'p':@fm:'q'\n   x = a<2>", "q"),
    ("CONTROL: and an ordinary variable still takes a substring", "a = 'hello'\n   x = a[2,3]", "ell"),
    ("COLLECTION() makes a collection that an element can be put in and read from",
     C + "c{'name'} = 'Acme'\n   x = c{'name'}", "Acme"),
    ("a number stays a number", C + "c{'n'} = 5\n   x = c{'n'} + 2", "7"),
    ("a value holding field marks comes back whole",
     C + "c{'v'} = 'a':@fm:'b'\n   x = change(c{'v'}, @fm, 'F')", "aFb"),
    ("setting a name again replaces it", C + "c{'k'} = 'one'\n   c{'k'} = 'two'\n   x = c{'k'}", "two"),
    ("an element that is not there is a null string and STATUS() is ER$NOT.FOUND",
     C + "x = c{'nope'}\n   x = '[':x:'][':status():']'", "[][1004]"),
    ("a name is case sensitive", C + "c{'Name'} = 'upper'\n   x = '[':c{'name'}:']'", "[]"),
    ("ELEMENT.EXISTS() says 1 for a present element", C + "c{'a'} = 1\n   x = element.exists(c, 'a')", "1"),
    ("ELEMENT.EXISTS() says 0 for an absent one", C + "c{'a'} = 1\n   x = element.exists(c, 'b')", "0"),
    ("DEL removes an element", C + "c{'a'} = 1\n   del c{'a'}\n   x = element.exists(c, 'a')", "0"),
    ("DEL of an absent element leaves STATUS() at ER$NOT.FOUND and does nothing else",
     C + "c{'a'} = 1\n   del c{'b'}\n   x = status():'|':element.exists(c, 'a')", "1004|1"),
    ("ENUMERATE() gives the names sorted, left aligned and case sensitive (capitals first)",
     C + "c{'b'} = 1\n   c{'a'} = 1\n   c{'C'} = 1\n   x = change(enumerate(c), @fm, '|')", "C|a|b"),
    ("ENUMERATE() of an empty collection is null", C + "x = '[':enumerate(c):']'", "[]"),
    ("ENUMERATE() lists only the level it is given",
     C + "c{'a/b'} = 1\n   c{'z'} = 1\n   x = change(enumerate(c), @fm, '|')", "a|z"),
    ("{'a','b'}, {'a'}{'b'} and {'a/b'} are the same element",
     C + "c{'a','b'} = 'v'\n   x = c{'a'}{'b'}:'|':c{'a/b'}:'|':c{'a','b'}", "v|v|v"),
    ("the path may be mixed: {'a/b','c'} and {'a'}{'b/c'}",
     C + "c{'a/b','c'} = 'w'\n   x = c{'a'}{'b/c'}:'|':c{'a/b/c'}", "w|w"),
    ("a path made of variables", C + "p = 'a':'/':'b'\n   c{p} = 'q'\n   k = 'a'\n   x = c{k}{'b'}", "q"),
    ("elements missing along the way are made", C + "c{'x/y/z'} = 'deep'\n   x = c{'x'}{'y'}{'z'}", "deep"),
    ("an intermediate level is a collection that can be enumerated",
     C + "c{'x/y/z'} = 'deep'\n   t = c{'x'}\n   x = change(enumerate(t), @fm, '|')", "y"),
    ("DEL of a level removes everything below it",
     C + "c{'x/y/z'} = 'deep'\n   del c{'x'}\n   x = element.exists(c, 'x/y/z'):element.exists(c, 'x')", "00"),
    ("assigning a collection variable makes another reference to the same collection",
     C + "d = c\n   d{'k'} = 'v'\n   x = c{'k'}", "v"),
    ("COLLECTION(c) makes an independent copy",
     C + "c{'k'} = 'one'\n   d = collection(c)\n   d{'k'} = 'two'\n   d{'new'} = 1\n   x = c{'k'}:'|':element.exists(c, 'new')", "one|0"),
    ("a copy is deep: a collection inside is copied too",
     C + "c{'in/k'} = 'one'\n   d = collection(c)\n   d{'in/k'} = 'two'\n   x = c{'in/k'}", "one"),
    ("a collection can be an element of another, and shares",
     C + "d = collection()\n   c{'sub'} = d\n   d{'k'} = 'v'\n   x = c{'sub'}{'k'}", "v"),
    ("a name that is a number is a name in an ordinary collection", C + "c{'7'} = 'seven'\n   c{7} = 'again'\n   x = c{'7'}", "again"),
    ("a value read back from a collection can be changed without changing the collection",
     C + "c{'s'} = 'abc'\n   v = c{'s'}\n   v := 'def'\n   x = c{'s'}", "abc"),
    ("a collection held in a dimensioned array element",
     "dim t(2)\n   t(1) = collection()\n   t(1){'k'} = 'v'\n   x = t(1){'k'}", "v"),
    ("3000 elements go in sorted and come out again (the table grows and shrinks)",
     C + "for i = 1 to 3000\n   c{'k':i} = i\n   next i\n   x = dcount(enumerate(c), @fm)\n"
     "   for i = 1 to 3000 step 2\n   del c{'k':i}\n   next i\n   x := '|':dcount(enumerate(c), @fm):'|':c{'k2998'}:'|':element.exists(c, 'k2999')\n"
     "   for i = 2 to 3000 step 2\n   del c{'k':i}\n   next i\n   x := '|':dcount(enumerate(c), @fm)", "3000|1500|2998|0|0"),
    ("a collection copied again and again, and dropped, leaves the original whole",
     C + "c{'a/b/c'} = 'deep'\n   for i = 1 to 2000\n   d = collection(c)\n   d{'a/b/x'} = i\n   next i\n   x = c{'a/b/c'}:'|':d{'a/b/x'}:'|':element.exists(c, 'a/b/x')", "deep|2000|0"),
    # ---- arrays -----------------------------------------------------------------------------------------------
    ("MAT() makes an empty array that INMAT() counts", C + "c{'a'} = mat()\n   x = inmat(c{'a'})", "0"),
    ("elements go on the end of an array by position", C + "c{'a'} = mat()\n   c{'a',1} = 'x'\n   c{'a',2} = 'y'\n   x = inmat(c{'a'}):'|':c{'a',1}:c{'a',2}", "2|xy"),
    ("a negative position appends", C + "c{'a'} = mat()\n   c{'a',-1} = 'p'\n   c{'a',-1} = 'q'\n   x = inmat(c{'a'}):'|':c{'a',2}", "2|q"),
    ("the {name}{n} form reaches the same element", C + "c{'a'} = mat()\n   c{'a'}{1} = 'x'\n   x = c{'a',1}:c{'a'}{1}:c{'a/1'}", "xxx"),
    ("a position past the end is not found", C + "c{'a'} = mat()\n   c{'a',1} = 'x'\n   x = '[':c{'a',2}:']':status()", "[]1004"),
    ("ENUMERATE() of an array is its positions", C + "c{'a'} = mat()\n   c{'a',1} = 'x'\n   c{'a',2} = 'y'\n   x = change(enumerate(c{'a'}), @fm, '|')", "1|2"),
    ("MAT(matrix) copies a dimensioned matrix",
     "dim t(3)\n   t(1) = 'a'\n   t(2) = 'b'\n   t(3) = 'c'\n" + "   " + C + "c{'k'} = mat(t)\n   x = inmat(c{'k'}):'|':c{'k',1}:c{'k',3}", "3|ac"),
    ("MAT(matrix, max) stops at max elements",
     "dim t(3)\n   t(1) = 'a'\n   t(2) = 'b'\n   t(3) = 'c'\n" + "   " + C + "c{'k'} = mat(t, 2)\n   x = inmat(c{'k'}):'|':c{'k',2}", "2|b"),
    ("MAT(matrix) of two dimensions goes row by row",
     "dim m(2,2)\n   m(1,1) = 1\n   m(1,2) = 2\n   m(2,1) = 3\n   m(2,2) = 4\n" + "   " + C + "c{'k'} = mat(m)\n   x = c{'k',1}:c{'k',2}:c{'k',3}:c{'k',4}", "1234"),
    ("an unassigned matrix element is a null string",
     "dim t(2)\n   t(1) = 'a'\n" + "   " + C + "c{'k'} = mat(t)\n   x = inmat(c{'k'}):'|':c{'k',1}:'[':c{'k',2}:']'", "2|a[]"),
    ("the copy is not the matrix: changing it leaves the matrix alone",
     "dim t(1)\n   t(1) = 'a'\n" + "   " + C + "c{'k'} = mat(t)\n   c{'k',1} = 'b'\n   x = t(1)", "a"),
    ("MAT x = MAT c{path} copies an array into a matrix",
     C + "c{'k'} = mat()\n   c{'k',1} = 'x'\n   c{'k',2} = 'y'\n   dim n(3)\n   mat n = mat c{'k'}\n   x = n(1):n(2)", "xy"),
    ("...and leaves the rest of the matrix as it was",
     C + "c{'k'} = mat()\n   c{'k',1} = 'x'\n   dim n(3)\n   n(3) = 'z'\n   mat n = mat c{'k'}\n   x = n(1):n(3)", "xz"),
    ("...and stops when the matrix is the shorter",
     C + "c{'k'} = mat()\n   c{'k',1} = 'x'\n   c{'k',2} = 'y'\n   c{'k',3} = 'w'\n   dim n(2)\n   mat n = mat c{'k'}\n   x = n(1):n(2)", "xy"),
    ("DEL of an array element renumbers the rest",
     C + "c{'k'} = mat()\n   c{'k',1} = 'a'\n   c{'k',2} = 'b'\n   c{'k',3} = 'c'\n   del c{'k',2}\n   x = inmat(c{'k'}):'|':c{'k',1}:c{'k',2}", "2|ac"),
    ("DEL c{name}{n} does the same",
     C + "c{'k'} = mat()\n   c{'k',1} = 'a'\n   c{'k',2} = 'b'\n   del c{'k'}{1}\n   x = inmat(c{'k'}):'|':c{'k',1}", "1|b"),
    ("INS value AS opens a gap in an array",
     C + "c{'k'} = mat()\n   c{'k',1} = 'a'\n   c{'k',2} = 'c'\n   ins 'b' as c{'k',2}\n   x = inmat(c{'k'}):'|':c{'k',1}:c{'k',2}:c{'k',3}", "3|abc"),
    ("INS at the first position pushes everything up",
     C + "c{'k'} = mat()\n   c{'k',1} = 'b'\n   ins 'a' as c{'k'}{1}\n   x = c{'k',1}:c{'k',2}", "ab"),
    ("INS one past the end, and with a negative position, appends",
     C + "c{'k'} = mat()\n   ins 'a' as c{'k',1}\n   ins 'b' as c{'k',2}\n   ins 'c' as c{'k',-1}\n   x = c{'k',1}:c{'k',2}:c{'k',3}", "abc"),
    ("INS in a collection that is not an array puts the element in", C + "ins 'v' as c{'n'}\n   x = c{'n'}", "v"),
    ("INS MAT() AS puts in an empty array", C + "ins mat() as c{'list'}\n   c{'list',1} = 'x'\n   x = inmat(c{'list'}):'|':c{'list',1}", "1|x"),
    ("INS MAT(matrix) AS puts in a copy of a matrix",
     "dim t(2)\n   t(1) = 'p'\n   t(2) = 'q'\n" + "   " + C + "ins mat(t) as c{'list'}\n   x = inmat(c{'list'}):'|':c{'list',2}", "2|q"),
    ("INMAT() of a variable holding an array", C + "c{'k'} = mat()\n   c{'k',1} = 'x'\n   t = c{'k'}\n   x = inmat(t)", "1"),
    ("INMAT() of an element that is not there is 0", C + "x = inmat(c{'nope'})", "0"),
    ("a collection is an element of an array, and an array of an array",
     C + "c{'g'} = mat()\n   c{'g',1} = mat()\n   c{'g',1,1} = 'deep'\n   c{'g',2} = collection()\n   c{'g',2}{'n'} = 'obj'\n   x = c{'g',1,1}:'|':c{'g',2,'n'}:'|':inmat(c{'g'})", "deep|obj|2"),
    ("COLLECTION(c) copies the arrays inside as well",
     C + "c{'k'} = mat()\n   c{'k',1} = 'one'\n   d = collection(c)\n   d{'k',1} = 'two'\n   d{'k',-1} = 'more'\n   x = c{'k',1}:'|':inmat(c{'k'}):'|':inmat(d{'k'})", "one|1|2"),
    ("an array assigned to a second name is the same array",
     C + "c{'k'} = mat()\n   t = c{'k'}\n   t{1} = 'via t'\n   x = c{'k',1}", "via t"),
    # ---- asterisk paths ---------------------------------------------------------------------------------------
    ("c{'k/*'} gives the elements of an array as values",
     C + "c{'k'} = mat()\n   c{'k',1} = 'a'\n   c{'k',2} = 'b'\n   c{'k',3} = 'c'\n   x = change(c{'k/*'}, @vm, '|')", "a|b|c"),
    ("c{'d/*/p'} gives one value from each element",
     C + "c{'d'} = mat()\n   c{'d',1} = collection()\n   c{'d',1}{'p'} = 'A'\n   c{'d',2} = collection()\n   c{'d',2}{'p'} = 'B'\n   x = change(c{'d/*/p'}, @vm, '|')", "A|B"),
    ("an element without the item leaves its place empty",
     C + "c{'d'} = mat()\n   c{'d',1} = collection()\n   c{'d',1}{'p'} = 'A'\n   c{'d',2} = collection()\n   c{'d',3} = collection()\n   c{'d',3}{'p'} = 'C'\n   x = change(c{'d/*/p'}, @vm, '|')", "A||C"),
    ("two asterisks give subvalues within values",
     C + "c{'d'} = mat()\n   c{'d',1} = collection()\n   c{'d',1}{'s'} = mat()\n   c{'d',1}{'s',1} = '1a'\n   c{'d',1}{'s',2} = '1b'\n"
     "   c{'d',2} = collection()\n   c{'d',2}{'s'} = mat()\n   c{'d',2}{'s',1} = '2a'\n   x = change(change(c{'d/*/s/*'}, @vm, 'V'), @svm, 'S')", "1aS1bV2a"),
    ("an asterisk path through something that is not an array is null", C + "c{'o/p'} = 'v'\n   x = '[':c{'o/*'}:']'", "[]"),
    ("ERR: an asterisk cannot be used to set", C + "c{'a'} = mat()\n   c{'a/*'} = 'x'", "ERR:Invalid data collection element name"),
    ("ERR: three asterisks are too many", C + "x = c{'a/*/*/*'}", "ERR:Invalid data collection element name"),
    ("ERR: elements may not be left undefined in an array", C + "c{'k'} = mat()\n   c{'k',1} = 'a'\n   c{'k',5} = 'e'", "ERR:Invalid data collection element name"),
    ("ERR: INS may not leave a gap either", C + "c{'k'} = mat()\n   ins 'q' as c{'k',9}", "ERR:Invalid data collection element name"),
    ("ERR: MAT x = MAT c{path} of something that is not an array",
     C + "c{'o'} = 'v'\n   dim n(2)\n   mat n = mat c{'o'}", "ERR:not a data collection"),
    ("ERR: MAT x = MAT c{path} of a collection that is not an array",
     C + "c{'o/p'} = 'v'\n   dim n(2)\n   mat n = mat c{'o'}", "ERR:not an array"),
    ("ERR: a name cannot be used as a position in an array",
     C + "c{'k'} = mat()\n   c{'k',1} = 'a'\n   c{'k','abc'} = 'b'", "ERR:Invalid data collection element name"),
    ("ERR: MAT(x) of something that is not a matrix", "t = 5\n   c = collection()\n   c{'k'} = mat(t)", "ERR:imensioned matrix"),
    # ---- JSON: JPARSE() and JBUILD() ------------------------------------------------------------------------
    ("JPARSE() reads an object into a collection and STATUS() is 0",
     "c = jparse('{\"name\":\"Acme\",\"n\":5}')\n   x = c{'name'}:'|':c{'n'} + 1:'|':status()", "Acme|6|0"),
    ("nested objects and arrays are reached by path",
     "c = jparse('{\"a\":{\"b\":[10,20,{\"z\":\"deep\"}]}}')\n   x = c{'a/b/1'}:'|':c{'a/b/3/z'}:'|':inmat(c{'a/b'})", "10|deep|3"),
    ("a JSON array at the top is an array", "c = jparse('[1,\"two\",[3]]')\n   x = inmat(c):'|':c{2}:'|':c{3,1}", "3|two|3"),
    ("true and false read back as 1 and 0, null as a null string",
     "c = jparse('{\"t\":true,\"f\":false,\"n\":null}')\n   x = c{'t'}:'|':c{'f'}:'|':'[':c{'n'}:']'", "1|0|[]"),
    ("numbers: integers, fractions, exponents, big ones",
     "c = jparse('{\"f\":1.5,\"big\":12345678901,\"neg\":-3,\"e\":1e2}')\n   x = c{'f'} * 2:'|':c{'neg'} - 1:'|':c{'e'}:'|':c{'big'}", "3|-4|100|12345678901"),
    ("whitespace, and all five marks, between elements are ignored",
     "c = jparse('{':@fm:' \"a\" ':@vm:':':@svm:' 1 ':@tm:'}')\n   x = c{'a'}:'|':status()", "1|0"),
    ("a later name replaces an earlier one", "c = jparse('{\"a\":1,\"a\":2}')\n   x = c{'a'}:'|':inmat(c)", "2|1"),
    ("single quotes are accepted for names and strings", "c = jparse(\"{'a':'b'}\")\n   x = c{'a'}", "b"),
    ("escapes: quote, backslash, slash, newline, tab",
     "c = jparse('{\"s\":\"q\\\"b\\\\s\\/n\\nt\\t\"}')\n   x = change(change(c{'s'}, char(10), 'N'), char(9), 'T')", "q\"b\\s/nNtT"),
    ("\\u00e9 is the byte E9 and \\u20ac is three bytes of UTF-8",
     "c = jparse('{\"a\":\"\\u00e9\",\"b\":\"\\u20ac\"}')\n   x = seq(c{'a'}):'|':len(c{'a'}):'|':seq(c{'b'}[1,1]):'|':len(c{'b'})", "233|1|226|3"),
    ("a surrogate pair is one four byte character",
     "c = jparse('{\"a\":\"\\ud83d\\ude00\"}')\n   x = len(c{'a'}):'|':seq(c{'a'}[1,1])", "4|240"),
    ("a name without quotes is refused unless JP$UNQUOTED.NAME is set",
     "c = jparse('{a:1}')\n   x = status():'|':'[':c:']'", "1020|[]"),
    ("...and with it set is accepted", "c = jparse('{a:1,b2:2}', 2)\n   x = c{'a'}:c{'b2'}:'|':status()", "12|0"),
    ("JP$NULL reads a null as a null string, not as null",
     "c = jparse('{\"n\":null}', 1)\n   x = jbuild(c)", "{\"n\":\"\"}"),
    ("an error gives a null string, STATUS() 1020 and INMAT() the character position",
     "c = jparse('{\"a\" 1}')\n   x = '[':c:']':status():'|':inmat()", "[]1020|6"),
    ("text after the value is an error, at the first character of it", "c = jparse('{\"a\":1} x')\n   x = status():'|':inmat()", "1020|9"),
    ("a value that is not an object or array is refused", "c = jparse('5')\n   x = status():'|':inmat()", "1020|1"),
    ("an empty string is refused", "c = jparse('')\n   x = status()", "1020"),
    ("a half-finished value is refused", "c = jparse('{\"a\":[1,2')\n   x = status()", "1020"),
    ("a trailing comma is refused", "c = jparse('[1,2,]')\n   x = status()", "1020"),
    ("01 is not a JSON number", "c = jparse('[01]')\n   x = status()", "1020"),
    ("600 levels of nesting are refused, not run into", "c = jparse(str('[', 600):str(']', 600))\n   x = status()", "1020"),
    ("JBUILD() writes a collection compactly, names in order",
     C + "c{'b'} = 2\n   c{'a'} = 'x'\n   x = jbuild(c):'|':status()", "{\"a\":\"x\",\"b\":2}|0"),
    ("arrays and nested collections", C + "c{'l'} = mat()\n   c{'l',1} = 1\n   c{'l',2} = 'two'\n   c{'o/p'} = 3\n   x = jbuild(c)", "{\"l\":[1,\"two\"],\"o\":{\"p\":3}}"),
    ("an array at the top", "c = mat()\n   x = jbuild(c)", "[]"),
    ("quote, backslash and control characters are escaped",
     C + "c{'s'} = 'q\"b\\':char(9):'t':char(10):'n'\n   x = jbuild(c)", "{\"s\":\"q\\\"b\\\\\\tt\\nn\"}"),
    ("marks and 8 bit characters are written as \\u00XX",
     C + "c{'m'} = 'a':@fm:'b':@vm:'c':char(233)\n   x = jbuild(c)", "{\"m\":\"a\\u00feb\\u00fdc\\u00e9\"}"),
    ("...and come back as the same bytes",
     C + "s = 'a':@fm:'b':@vm:'c':@svm:'d':char(233)\n   c{'m'} = s\n   d = jparse(jbuild(c))\n   x = (d{'m'} = s)", "1"),
    ("a float is written so it reads back the same",
     C + "c{'f'} = 0.1 + 0.2\n   d = jparse(jbuild(c))\n   x = (d{'f'} = c{'f'})", "1"),
    ("true, false and null survive a parse and a build",
     "s = '{\"e\":\"\",\"f\":false,\"n\":null,\"t\":true}'\n   x = (jbuild(jparse(s)) = s)", "1"),
    ("a whole document survives a parse and a build",
     "s = '{\"a\":[1,2.5,{\"b\":[true,null,\"x\"]}],\"c\":{\"d\":\"e\"},\"z\":[]}'\n   x = (jbuild(jparse(s)) = s)", "1"),
    ("a string that is a number is quoted unless JB$NUM", C + "c{'n'} = '42'\n   x = jbuild(c):'|':jbuild(c, 4)", "{\"n\":\"42\"}|{\"n\":42}"),
    ("JB$NUM leaves what is not a JSON number in quotes",
     C + "c{'a'} = '007'\n   c{'b'} = '1.5e3'\n   c{'c'} = '+5'\n   c{'d'} = ''\n   x = jbuild(c, 4)", "{\"a\":\"007\",\"b\":1.5e3,\"c\":\"+5\",\"d\":\"\"}"),
    ("JB$NULL writes an empty string as null", C + "c{'e'} = ''\n   x = jbuild(c):'|':jbuild(c, 2)", "{\"e\":\"\"}|{\"e\":null}"),
    ("names in single quotes, or with none", C + "c{'a'} = 'x'\n   x = jbuild(c, 8):'|':jbuild(c, 16)", "{'a':\"x\"}|{a:\"x\"}"),
    ("values in single quotes, or with none", C + "c{'a'} = \"it's\"\n   x = jbuild(c, 32):'|':jbuild(c, 64)", "{\"a\":'it\\'s'}|{\"a\":it's}"),
    ("the modes add: names and values both single quoted", C + "c{'a'} = 'x'\n   x = jbuild(c, 8 + 32)", "{'a':'x'}"),
    ("a file variable has no JSON form: a null string and STATUS() 1019",
     C + "open 'voc' to f else stop 'no voc'\n   c{'f'} = f\n   x = '[':jbuild(c):']':status()", "[]1019"),
    ("...unless JB$INVALID asks for a null", C + "open 'voc' to f else stop 'no voc'\n   c{'f'} = f\n   x = jbuild(c, 1):'|':status()", "{\"f\":null}|0"),
    ("a collection that contains itself cannot be built", C + "c{'me'} = c\n   x = '[':jbuild(c):']':status()", "[]1019"),
    ("the modes have names in keys.h",
     "$include keys.h\n   x = jp$null:'|':jp$unquoted.name:'|':jb$invalid:'|':jb$null:'|':jb$num:'|':jb$squote.name:'|':jb$noquote.name:'|':jb$squote.value:'|':jb$noquote.value", "1|2|1|2|4|8|16|32|64"),
    ("the error codes have names in err.h", "$include err.h\n   x = er$build.error:'|':er$parse.error", "1019|1020"),
    ("ERR: JBUILD() of something that is not a collection", "x = jbuild('abc')", "ERR:not a data collection"),
    # ---- JSON booleans and nulls --------------------------------------------------------------------------------
    ("JBOOLEAN() and JNULL() put true, false and null into a collection",
     C + "c{'t'} = jboolean(1)\n   c{'f'} = jboolean(0)\n   c{'n'} = jnull()\n   x = jbuild(c)", "{\"f\":false,\"n\":null,\"t\":true}"),
    ("a boolean is the number 1 or 0 and a null reads as a null string",
     C + "c{'t'} = jboolean(1)\n   c{'f'} = jboolean(0)\n   c{'n'} = jnull()\n   x = c{'t'} + 0:'|':c{'f'} + 0:'|':'[':c{'n'}:']'", "1|0|[]"),
    ("JBOOLEAN() is true for any other number, text and false for 0, null, 0 and false in any case",
     "x = jboolean(7) + 0:jboolean(0) + 0:jboolean('') + 0:jboolean('0') + 0:jboolean('FaLsE') + 0:jboolean('no') + 0:jboolean('abc') + 0", "1000011"),
    ("JTYPE() names the kind of a value",
     C + "c{'t'} = jboolean(1)\n   c{'n'} = jnull()\n   c{'s'} = 'text'\n   c{'i'} = 5\n   c{'o/p'} = 1\n   c{'a'} = mat()\n"
     "   x = jtype(c{'t'}):'|':jtype(c{'n'}):'|':jtype(c{'s'}):'|':jtype(c{'i'}):'|':jtype(c{'o'}):'|':jtype(c{'a'})", "boolean|null|string|number|collection|array"),
    ("JTYPE() of plain values", "x = jtype(5):'|':jtype(2.5):'|':jtype('5'):'|':jtype(''):'|':jtype(jnull()):'|':jtype(jboolean(1))", "number|number|string|string|null|boolean"),
    ("a boolean in a variable is still a boolean when stored",
     C + "v = jboolean(1)\n   c{'x'} = v\n   w = jnull()\n   c{'y'} = w\n   x = jbuild(c)", "{\"x\":true,\"y\":null}"),
    ("but arithmetic on a boolean gives an ordinary number",
     C + "v = jboolean(1) + 1\n   c{'x'} = v\n   x = jbuild(c):'|':jtype(v)", "{\"x\":2}|number"),
    ("a boolean or null read from a collection keeps its kind through a copy of the collection",
     C + "c{'t'} = jboolean(1)\n   c{'n'} = jnull()\n   d = collection(c)\n   x = jbuild(d)", "{\"n\":null,\"t\":true}"),
    ("and into another collection",
     "c = jparse('{\"t\":true,\"f\":false,\"n\":null}')\n   d = collection()\n   d{'t2'} = c{'t'}\n   d{'f2'} = c{'f'}\n   d{'n2'} = c{'n'}\n   x = jbuild(d)", "{\"f2\":false,\"n2\":null,\"t2\":true}"),
    ("JP$NULL makes a null an ordinary empty string", "c = jparse('{\"n\":null}', 1)\n   x = jtype(c{'n'})", "string"),
    ("and without it a parsed null is a null", "c = jparse('{\"n\":null,\"t\":true}')\n   x = jtype(c{'n'}):'|':jtype(c{'t'})", "null|boolean"),
    ("a null is an empty string to everything else", "x = '[':jnull():']':len(jnull()):(jnull() = '')", "[]01"),
    ("booleans and nulls survive MAT and MAT()",
     C + "c{'a'} = mat()\n   c{'a',1} = jboolean(1)\n   c{'a',2} = jnull()\n   dim n(2)\n   mat n = mat c{'a'}\n   d = collection()\n   d{'b'} = mat(n)\n   x = jbuild(d):'|':jtype(n(1)):'|':jtype(n(2))", "{\"b\":[true,null]}|boolean|null"),
    # ---- += -= *= /= := on an element --------------------------------------------------------------------------
    ("+= on an element that is not there starts from nothing", C + "c{'n'} += 5\n   x = c{'n'}", "5"),
    ("+= -= *= /= on an element",
     C + "c{'n'} = 10\n   c{'n'} += 5\n   x = c{'n'}\n   c{'n'} -= 3\n   x := '|':c{'n'}\n   c{'n'} *= 2\n   x := '|':c{'n'}\n   c{'n'} /= 4\n   x := '|':c{'n'}", "15|12|24|6"),
    (":= on an element joins on the end", C + "c{'s'} := 'ab'\n   c{'s'} := 'cd'\n   x = c{'s'}", "abcd"),
    ("the new value is worked out before it is stored, so the right side can read the element",
     C + "c{'n'} = 4\n   c{'n'} += c{'n'} * 2\n   x = c{'n'}", "12"),
    ("an operator on an array element", C + "c{'a'} = mat()\n   c{'a',1} = 1\n   c{'a',1} += 4\n   c{'a',2} := 'x'\n   x = c{'a',1}:'|':c{'a',2}", "5|x"),
    ("an operator along a path that is not there makes the levels", C + "c{'x/y'} += 1\n   x = c{'x'}{'y'}", "1"),
    ("an operator on a boolean gives an ordinary number", C + "c{'t'} = jboolean(1)\n   c{'t'} += 1\n   x = jbuild(c)", "{\"t\":2}"),
    (":= with a null string leaves the element as it was",
     C + "c{'s'} = 'a'\n   c{'s'} := ''\n   x = c{'s'}", "a"),
    # ---- HU conversion ------------------------------------------------------------------------------------------
    ("OCONV(,'HU') escapes a URL as the openQM page shows it",
     "x = oconv('http://domain.com/hello?a=b', 'HU')", "http%3a%2f%2fdomain.com%2fhello%3fa%3db"),
    ("ICONV(,'HU') undoes it", "x = iconv('http%3a%2f%2fdomain.com%2fhello%3fa%3db', 'HU')", "http://domain.com/hello?a=b"),
    ("letters, digits and - . _ ~ are left alone, a space is %20", "x = oconv('Az09-._~ ', 'HU')", "Az09-._~%20"),
    ("a mark is escaped too", "x = oconv('a':@fm:'b', 'HU')", "a%feb"),
    ("a % that is not followed by two hex digits, and a +, are left as they are",
     "x = iconv('%41%4A+%zz%4', 'HU')", "AJ+%zz%4"),
    ("a null string stays null", "x = '[':oconv('', 'HU'):']':'[':iconv('', 'HU'):']'", "[][]"),
    ("a name made with HU keeps its slashes out of the path",
     C + "k = oconv('a/b', 'HU')\n   c{k} = 'v'\n   x = c{k}:'|':element.exists(c, 'a/b'):'|':enumerate(c):'|':iconv(enumerate(c), 'HU')", "v|0|a%2fb|a/b"),
    ("an unknown conversion after H leaves the data and sets STATUS() 2", "x = oconv('a', 'HUX'):'|':status()", "a|2"),
    # ---- collections and subroutines ----------------------------------------------------------------------------
    ("a collection passed to a subroutine is the caller's own", C + "call zzcsub1(c)\n   x = c{'k'}", "set by sub"),
    ("a subroutine can make a collection and hand it back through an argument", "call zzcsub2(r)\n   x = r{'a'}:'|':jtype(r)", "1|collection"),
    ("calling a subroutine again and again with collections of its own is safe",
     "for i = 1 to 300\n   call zzcsub3(i, t)\n   next i\n   x = t", "300"),
    # ---- data collection files: CREATE.FILE ... COLLECTION -------------------------------------------------------
    ("the COLLECTION flag shows in the file's flags, and an ordinary file has none",
     "$include keys.h\n   open 'zzcf' to f else stop 'no zzcf'\n   open 'zzcn' to g else stop 'no zzcn'\n   x = fileinfo(f, fl$collection):'|':fileinfo(g, fl$collection)", "1|0"),
    ("WRITE takes a collection and READ gives one back",
     OPENF + "c = collection()\n   c{'name'} = 'Acme'\n   c{'n'} = 5\n   c{'a/b'} = 'deep'\n   write c on f, 'r1'\n"
     "   read d from f, 'r1' else stop 'not read'\n   x = d{'name'}:'|':d{'n'} + 1:'|':d{'a/b'}:'|':jtype(d)", "Acme|6|deep|collection"),
    ("what is read is a copy: changing it changes nothing until it is written",
     OPENF + "c = collection()\n   c{'k'} = 'one'\n   write c on f, 'r2'\n   read d from f, 'r2' else stop 'not read'\n   d{'k'} = 'two'\n"
     "   read e from f, 'r2' else stop 'not read'\n   x = e{'k'}", "one"),
    ("the collection written is the collection read, JSON and all",
     OPENF + "c = jparse('{\"l\":[1,2.5,\"x\"],\"o\":{\"t\":true,\"n\":null,\"s\":\"a\\u00e9\"}}')\n   write c on f, 'r3'\n"
     "   read d from f, 'r3' else stop 'not read'\n   x = (jbuild(d) = jbuild(c)):'|':jbuild(d)", "1|{\"l\":[1,2.5,\"x\"],\"o\":{\"n\":null,\"s\":\"a\\u00e9\",\"t\":true}}"),
    ("an array is a record too", OPENF + "c = mat()\n   c{1} = 'p'\n   c{2} = 'q'\n   write c on f, 'r4'\n   read d from f, 'r4' else stop 'not read'\n   x = jtype(d):'|':inmat(d):'|':d{2}", "array|2|q"),
    ("JSON text written to the file is accepted and read back as a collection",
     OPENF + "write '{\"a\":1}' on f, 'r5'\n   read d from f, 'r5' else stop 'not read'\n   x = d{'a'}", "1"),
    ("a record that is not there takes the ELSE", OPENF + "read d from f, 'nope' then x = 'found' else x = 'missing'", "missing"),
    ("READU, change, WRITEU", OPENF + "c = collection()\n   c{'n'} = 5\n   write c on f, 'r6'\n   readu d from f, 'r6' else stop 'not read'\n   d{'n'} += 1\n"
     "   writeu d on f, 'r6'\n   read e from f, 'r6' else stop 'not read'\n   x = e{'n'}", "6"),
    ("DELETE and the record is gone", OPENF + "c = collection()\n   write c on f, 'r7'\n   delete f, 'r7'\n   read d from f, 'r7' then x = 'found' else x = 'gone'", "gone"),
    ("an empty collection is a record", OPENF + "c = collection()\n   write c on f, 'r8'\n   read d from f, 'r8' else stop 'not read'\n   x = jtype(d):'|':inmat(d)", "collection|0"),
    ("a collection read from one file can be written to another",
     OPENF + "c = collection()\n   c{'k'} = 'v'\n   write c on f, 'r9'\n   open 'zzcf2' to f2 else stop 'no zzcf2'\n   read d from f, 'r9' else stop 'not read'\n"
     "   write d on f2, 'copy'\n   read e from f2, 'copy' else stop 'not read'\n   x = e{'k'}", "v"),
    ("a transaction can write and read a collection",
     OPENF + "c = collection()\n   c{'t'} = 'in txn'\n   begin transaction\n   recordlocku f, 'tx1'\n   write c on f, 'tx1'\n   read d from f, 'tx1' else stop 'not read in'\n   commit\n   end transaction\n"
     "   read e from f, 'tx1' else stop 'not read after'\n   x = d{'t'}:'|':e{'t'}", "in txn|in txn"),
    # ---- linked collections: EXPAND ---------------------------------------------------------------------------
    ("EXPAND joins the record a link names onto its parent",
     OPENF + "open 'zzcf2' to g else stop 'no zzcf2'\n   a = collection()\n   a{'city'} = 'Oslo'\n   write a on g, 'addr1'\n"
     "   c = collection()\n   c{'name'} = 'Ann'\n   c{'addr'} = 'zzcf2:addr1'\n   ok = expand(c{'addr'})\n   x = ok:'|':c{'addr'}{'city'}:'|':jtype(c{'addr'}):'|':c{'name'}", "1|Oslo|collection|Ann"),
    ("a link with no file name uses the file variable",
     OPENF + "open 'zzcf2' to g else stop 'no zzcf2'\n   a = collection()\n   a{'city'} = 'Bergen'\n   write a on g, 'addr2'\n"
     "   c = collection()\n   c{'addr'} = ':addr2'\n   ok = expand(c{'addr'}, g)\n   x = ok:'|':c{'addr/city'}", "1|Bergen"),
    ("...and fails without one", OPENF + "c = collection()\n   c{'addr'} = ':addr2'\n   x = expand(c{'addr'}):'|':c{'addr'}", "0|:addr2"),
    ("a record that is not there leaves the link as it was",
     OPENF + "c = collection()\n   c{'addr'} = 'zzcf2:nope'\n   x = expand(c{'addr'}):'|':c{'addr'}", "0|zzcf2:nope"),
    ("a file that is not there", OPENF + "c = collection()\n   c{'addr'} = 'nofilehere:x'\n   x = expand(c{'addr'}):'|':c{'addr'}", "0|nofilehere:x"),
    ("an element that is not there, or is not a link", OPENF + "c = collection()\n   c{'plain'} = 'no colon'\n   x = expand(c{'nope'}):expand(c{'plain'}):'|':c{'plain'}", "00|no colon"),
    ("an element that already is a collection is a success", OPENF + "c = collection()\n   c{'in'} = collection()\n   x = expand(c{'in'})", "1"),
    ("the link may be deep, in a path or an array",
     OPENF + "open 'zzcf2' to g else stop 'no zzcf2'\n   a = collection()\n   a{'v'} = 'one'\n   write a on g, 'addr3'\n   c = collection()\n"
     "   c{'a/b'} = 'zzcf2:addr3'\n   c{'l'} = mat()\n   c{'l',1} = 'zzcf2:addr3'\n   x = expand(c{'a','b'}):expand(c{'l',1}):'|':c{'a/b/v'}:c{'l',1,'v'}", "11|oneone"),
    ("a record can hold links and each is joined in turn",
     OPENF + "open 'zzcf2' to g else stop 'no zzcf2'\n   a = collection()\n   a{'v'} = 'last'\n   write a on g, 'tail'\n   b = collection()\n   b{'next'} = 'zzcf2:tail'\n   write b on g, 'head'\n"
     "   c = collection()\n   c{'h'} = 'zzcf2:head'\n   x = expand(c{'h'}):expand(c{'h/next'}):'|':c{'h/next/v'}", "11|last"),
    ("an id may hold colons: the file name is up to the first one",
     OPENF + "open 'zzcf2' to g else stop 'no zzcf2'\n   a = collection()\n   a{'v'} = 'colon id'\n   write a on g, 'x:y'\n   c = collection()\n   c{'l'} = 'zzcf2:x:y'\n   x = expand(c{'l'}):'|':c{'l/v'}", "1|colon id"),
    ("a link to a record of an ordinary file is not a collection, so it fails",
     OPENF + "open 'zzcn' to g else stop 'no zzcn'\n   write 'just text' on g, 'k'\n   c = collection()\n   c{'l'} = 'zzcn:k'\n   x = expand(c{'l'}):'|':c{'l'}", "0|zzcn:k"),
    ("what was joined on is a copy: changing it leaves the file's record alone",
     OPENF + "open 'zzcf2' to g else stop 'no zzcf2'\n   a = collection()\n   a{'v'} = 'orig'\n   write a on g, 'keep'\n   c = collection()\n   c{'l'} = 'zzcf2:keep'\n   ok = expand(c{'l'})\n   c{'l/v'} = 'changed'\n"
     "   read d from g, 'keep' else stop 'x'\n   x = d{'v'}:'|':c{'l/v'}", "orig|changed"),
    ("ERR: EXPAND wants an element, not a value", OPENF + "c = collection()\n   x = expand(c)", "ERR:Left curly bracket not found"),
    ("ERR: a collection cannot be written to an ordinary file",
     "open 'zzcn' to g else stop 'no zzcn'\n   c = collection()\n   write c on g, 'x'", "ERR:Data cannot be converted to a string"),
    ("ERR: text that is not JSON cannot be written to a collection file", OPENF + "write 'not json' on f, 'bad'", "ERR:writing record"),
    ("ERR: nor can JSON that is only a number", OPENF + "write '5' on f, 'bad'", "ERR:writing record"),
    ("ERR: a collection with something in it that has no JSON form cannot be written",
     OPENF + "c = collection()\n   c{'f'} = f\n   write c on f, 'bad'", "ERR:writing record"),
    ("ERR: MATREAD makes no sense on a collection file", OPENF + "dim m(3)\n   c = collection()\n   write c on f, 'm1'\n   matread m from f, 'm1' else stop 'x'", "ERR:cannot be used on a data collection file"),
    ("ERR: READV of a field of a collection file", OPENF + "c = collection()\n   write c on f, 'v1'\n   readv x from f, 'v1', 1 else stop 'x'", "ERR:"),
    ("ERR: a variable that is not a collection cannot take an element", "n = 5\n   n{'a'} = 1", "ERR:not a data collection"),
    ("ERR: nor can one be read from it", "n = 5\n   x = n{'a'}", "ERR:not a data collection"),
    ("ERR: an element cannot be added below a value that is not a collection",
     C + "c{'a'} = 1\n   c{'a/b'} = 2", "ERR:passes through a value that is not a collection"),
    ("ERR: an empty name is refused", C + "c{''} = 1", "ERR:Invalid data collection element name"),
    ("ERR: so is an empty part of a path", C + "c{'a//b'} = 1", "ERR:Invalid data collection element name"),
    ("ERR: a missing right curly bracket is a compile error", C + "x = c{'a'", "ERR:Right curly bracket"),
]


# Subroutines the cases above call.  Each is written, compiled and catalogued LOCAL before the cases run.
SUBS = {
    "zzcsub1": "   subroutine zzcsub1(c)\n   c{'k'} = 'set by sub'\n   return\nend\n",
    "zzcsub2": "   subroutine zzcsub2(out)\n   out = collection()\n   out{'a'} = 1\n   return\nend\n",
    "zzcsub3": "   subroutine zzcsub3(n, out)\n   local = collection()\n   local{'v'} = n\n   local{'big/deep/er'} = n\n   out = local{'v'}\n   return\nend\n",
}


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
    say("sandbox-coll: CANNOT RUN - " + msg)
    sys.exit(2)


def sess(box, *cmds):
    say("    > %d commands" % len(cmds))
    p = subprocess.run([sys.executable, TOOL, box, "sess", os.path.join(box, "user_accounts")] + list(cmds),
                       capture_output=True, text=True, timeout=900)
    out = ANSI.sub("", p.stdout + p.stderr)
    return out.split(":TERM 200,9999", 1)[-1]


# ---- the query processor on a data collection file ----------------------------------------------------------------
# A file zzcq of three records and a dictionary of E-type items is made, then SD commands are run against it.
# (label, command, [regexes the output must match], [regexes it must not match])
QUERY_SETUP = """   execute 'DELETE.FILE zzcq' capturing j0
   execute 'CREATE.FILE zzcq COLLECTION' capturing j1
   open 'zzcq' to f else stop 'no zzcq'
   open 'DICT zzcq' to d else stop 'no dict'
   open 'DICT zzcn' to dn else stop 'no dict zzcn'
   write jparse('{"name":"Acme","city":"Paris","n":3,"tags":["a","b"],"items":[{"p":"x","q":1},{"p":"y","q":2}]}') on f, 'r1'
   write jparse('{"name":"Beta","city":"Rome","n":10,"tags":["c"],"items":[{"p":"z","q":5}]}') on f, 'r2'
   write jparse('{"name":"Cargo","city":"Paris","n":7,"tags":[],"items":[]}') on f, 'r3'
   write 'E':@fm:'name':@fm:'':@fm:'Name':@fm:'10L':@fm:'S' on d, 'NAME'
   write 'E':@fm:'city':@fm:'':@fm:'City':@fm:'8L':@fm:'S' on d, 'CITY'
   write 'E':@fm:'n':@fm:'':@fm:'N':@fm:'5R':@fm:'S' on d, 'N'
   write 'E':@fm:'tags/*':@fm:'':@fm:'Tags':@fm:'6L':@fm:'M' on d, 'TAGS'
   write 'E':@fm:'items/*/p':@fm:'':@fm:'Prod':@fm:'6L':@fm:'M' on d, 'PRODS'
   write 'D':@fm:'1':@fm:'':@fm:'Dnum':@fm:'6L':@fm:'S' on d, 'DNUM'
   write 'I':@fm:'upcase(NAME)':@fm:'':@fm:'Upper':@fm:'10L':@fm:'S' on d, 'UPNAME'
   write 'I':@fm:'@RECORD{"city"}:"-":NAME':@fm:'':@fm:'CityName':@fm:'14L':@fm:'S' on d, 'CITYNAME'
   write 'I':@fm:'@RECORD{"items",1,"p"}':@fm:'':@fm:'First':@fm:'6L':@fm:'S' on d, 'FIRSTP'
   write 'I':@fm:'TRANS("zzcq", @ID, NAME, "X")':@fm:'':@fm:'ViaTrans':@fm:'10L':@fm:'S' on d, 'VIATRANS'
   write 'E':@fm:'name':@fm:'':@fm:'Name':@fm:'10L':@fm:'S' on dn, 'ENAME'
   crt 'QUERY SETUP DONE'
end
"""

QUERIES = [
    ("LIST gives the elements an E-type item names", "LIST zzcq NAME CITY ID.SUP",
     [r"Acme\s+Paris", r"Beta\s+Rome", r"Cargo\s+Paris"], [r"Error|not valid"]),
    ("the record id is the id", "LIST zzcq NAME", [r"(?m)^r1\s+Acme", r"(?m)^r2\s+Beta", r"(?m)^r3\s+Cargo"], []),
    ("WITH selects on an element", 'LIST zzcq NAME WITH CITY = "Paris" ID.SUP', [r"Acme", r"Cargo"], [r"Beta"]),
    ("a number in an element compares as a number", "LIST zzcq NAME WITH N > 5 ID.SUP", [r"Beta", r"Cargo"], [r"Acme"]),
    ("BY.DSND sorts on an element", "SORT zzcq NAME N BY.DSND N ID.SUP", [r"(?s)Beta.*Cargo.*Acme"], []),
    ("BY sorts the other way", "SORT zzcq NAME BY N ID.SUP", [r"(?s)Acme.*Cargo.*Beta"], []),
    ("an asterisk path is a multivalued item", "LIST zzcq TAGS ID.SUP", [r"(?s)a\s+b\s+c"], []),
    ("a path through arrays of collections", "LIST zzcq PRODS ID.SUP", [r"(?s)x\s+y\s+z"], []),
    ("COUNT with a WITH clause", 'COUNT zzcq WITH CITY = "Paris"', [r"2 record\(s\) counted"], []),
    ("SELECT with a WITH clause", 'SELECT zzcq WITH CITY = "Rome"', [r"1 record\(s\) selected"], []),
    ("SEARCH finds text in the JSON of a record", 'SEARCH zzcq FOR "Rome"', [r"1 record\(s\) selected"], []),
    ("SEARCH finds text that is deeper down", 'SEARCH zzcq FOR "z"', [r"1 record\(s\) selected"], []),
    ("CT shows a record as JSON, one element to a line",
     "CT zzcq r1", [r'zzcq r1', r'(?m)^\{$', r'(?m)^  "city": "Paris",$', r'(?m)^  "items": \[$', r'(?m)^    \{$', r'(?m)^      "p": "x",$',
                    r'(?m)^  "tags": \[$', r'(?m)^\}$'], []),
    ("CT of an empty array and collection keeps them on one line", "CT zzcq r3", [r'(?m)^  "items": \[\],$', r'(?m)^  "tags": \[\]$'], []),
    ("an I-type can use an E-type item by name", "LIST zzcq UPNAME ID.SUP", [r"ACME", r"BETA", r"CARGO"], [r"Error|not found"]),
    ("an I-type can take an element of @RECORD with {}", "LIST zzcq CITYNAME ID.SUP", [r"Paris-Acme", r"Rome-Beta", r"Paris-Cargo"], []),
    ("...including a path of names and positions", "LIST zzcq FIRSTP ID.SUP", [r"(?m)^\s*x\s*$", r"(?m)^\s*z\s*$"], []),
    ("TRANS() in an I-type with an E-type item as its third argument", "LIST zzcq VIATRANS ID.SUP", [r"Acme", r"Beta", r"Cargo"], [r"Error|not found"]),
    ("a D-type item with a field number is refused", "LIST zzcq DNUM", [r"refers to a field number, which a data collection file does not have"], []),
    ("an E-type item on an ordinary file is refused", "LIST zzcn ENAME", [r"can only be used with a data collection file"], []),
    ("COPY of a record to another collection file", "COPY FROM zzcq TO zzcq2 r1", [r"1 record\(s\) copied"], []),
]


def run_queries(box, sysd, names):
    say("\n--- the query processor on a collection file -------------------------------------")
    setup = os.path.join(sysd, "bp", "zzcoqs")
    names.append("zzcoqs")
    with open(setup, "w") as f:
        f.write(QUERY_SETUP)
    out = sess(box, "DELETE.FILE zzcq", "DELETE.FILE zzcq2", "DELETE.FILE zzcn", "CREATE.FILE zzcq2 COLLECTION", "CREATE.FILE zzcn",
               "BASIC bp zzcoqs", "RUN bp zzcoqs")
    row("setup: the query file and its dictionary were made", "QUERY SETUP DONE" in out, out[-400:])
    if "QUERY SETUP DONE" not in out:
        return
    # TRANS() from a BASIC program, naming a dictionary item
    tr = os.path.join(sysd, "bp", "zzcoqt")
    names.append("zzcoqt")
    with open(tr, "w") as f:
        f.write("   x = trans('zzcq', 'r2', 'NAME', 'X'):'|':trans('zzcq', 'r1', 'TAGS', 'X'):'|':trans('zzcq', 'r1', 'NOSUCH', 'X'):'|':"
                "trans('zzcq', 'r3', 'N', 'X') + 0:'|':trans('zzcq', 'nope', 'NAME', 'X'):'|':trans('zzcq', 'r1', 'DNUM', 'X'):'|':"
                "(len(trans('zzcq', 'r1', -1, 'X')) > 20)\n"
                "   crt 'TR[':change(x, @sm, '~'):']'\nend\n")   # TRANS lowers marks, so the list's value marks come as subvalue marks
    text = sess(box, "BASIC bp zzcoqt", "RUN bp zzcoqt")
    m = re.search(r"(?m)^TR\[(.*)\]\s*$", text)
    # DNUM is a D-type item for field 1, which a collection record does not have: null.  Field -1 is the whole record,
    # which for a collection is its JSON text.
    row("TRANS() from a program takes an E-type item by name, a path with * as a list, and an unknown name as null",
        bool(m) and m.group(1) == "Beta|a~b||7|||1", "got %r  %s" % (m.group(1) if m else None, text[-300:]))
    # Indices on E-type items
    # A file of its own, with lower case ids as everywhere in SD.  Until 11 Oct 26 dh_write.c and dh_del.c gave the
    # index code the id upper-cased, which broke every index (sandbox-akcase.py), so these rows used ids that
    # upper casing leaves alone; they are the ordinary ones now.
    xs = os.path.join(sysd, "bp", "zzcoxs")
    names.append("zzcoxs")
    with open(xs, "w") as f:
        f.write("   execute 'DELETE.FILE zzcx' capturing j0\n   execute 'CREATE.FILE zzcx COLLECTION' capturing j1\n"
                "   open 'zzcx' to f else stop 'no zzcx'\n   open 'DICT zzcx' to d else stop 'no dict'\n"
                "   write 'E':@fm:'city':@fm:'':@fm:'City':@fm:'8L':@fm:'S' on d, 'CITY'\n"
                "   write 'E':@fm:'tags/*':@fm:'':@fm:'Tags':@fm:'6L':@fm:'M' on d, 'TAGS'\n"
                "   write 'D':@fm:'1':@fm:'':@fm:'Dnum':@fm:'6L':@fm:'S' on d, 'DNUM'\n"
                "   write jparse('{\"city\":\"Paris\",\"tags\":[\"a\",\"b\"]}') on f, 'r1'\n"
                "   write jparse('{\"city\":\"Rome\",\"tags\":[\"c\"]}') on f, 'r2'\n"
                "   write jparse('{\"city\":\"Paris\",\"tags\":[]}') on f, 'r3'\nend\n")
    out = sess(box, "BASIC bp zzcoxs", "RUN bp zzcoxs", "CREATE.INDEX zzcx CITY", "CREATE.INDEX zzcx TAGS", "BUILD.INDEX zzcx CITY",
               "BUILD.INDEX zzcx TAGS", "LIST.INDEX zzcx")
    row("indices on two E-type items (one with an asterisk path) are made and built",
        re.search(r"CITY", out) is not None and re.search(r"TAGS", out) is not None and not re.search(r"(?i)internal error|is not a|inappropriate|can only be used|Compilation error", out), out[-500:])
    ix = os.path.join(sysd, "bp", "zzcoqi")
    names.append("zzcoqi")
    with open(ix, "w") as f:
        f.write("   open 'zzcx' to f else stop 'no zzcx'\n"
                "   selectindex 'CITY', 'Paris' from f to 5\n   readlist p from 5 else p = ''\n"
                "   selectindex 'TAGS', 'b' from f to 6\n   readlist t from 6 else t = ''\n"
                "   selectindex 'TAGS', 'c' from f to 7\n   readlist u from 7 else u = ''\n"
                "   x = change(p, @fm, ',') : '|' : change(t, @fm, ',') : '|' : change(u, @fm, ',')\n"
                "   * a new record, a changed one and a deleted one: the index follows each\n"
                "   write jparse('{\"city\":\"Paris\",\"tags\":[\"b\"]}') on f, 'r4'\n"
                "   c = jparse('{\"city\":\"Rome\",\"tags\":[\"a\",\"b\"]}')\n   write c on f, 'r1'\n"
                "   delete f, 'r3'\n"
                "   selectindex 'CITY', 'Paris' from f to 5\n   readlist p from 5 else p = ''\n"
                "   selectindex 'CITY', 'Rome' from f to 6\n   readlist q from 6 else q = ''\n"
                "   selectindex 'TAGS', 'b' from f to 7\n   readlist t from 7 else t = ''\n"
                "   y = change(p, @fm, ',') : '|' : change(q, @fm, ',') : '|' : change(t, @fm, ',')\n"
                "   crt 'IX1[' : x : ']'\n   crt 'IX2[' : y : ']'\nend\n")
    text = sess(box, "BASIC bp zzcoqi", "RUN bp zzcoqi")
    m1 = re.search(r"(?m)^IX1\[(.*)\]\s*$", text)
    m2 = re.search(r"(?m)^IX2\[(.*)\]\s*$", text)
    row("SELECTINDEX on an E-type index gives the records that have the value (a path with * gives each element)",
        bool(m1) and m1.group(1) == "r1,r3|r1|r2", "got %r  %s" % (m1.group(1) if m1 else None, text[-400:]))
    row("the index follows a new record, a change and a delete",
        bool(m2) and m2.group(1) == "r4|r1,r2|r1,r4", "got %r  %s" % (m2.group(1) if m2 else None, text[-400:]))
    # The query processor takes a WITH clause by the index: DEBUGGING prints how far into the selection elements the
    # clause that no index can take starts (non.ak.selection.index, 1 when no clause is taken by an index).  The control
    # is the same command after the index is deleted.  The OPTION and the command go in one session, the LIST last
    # (a LIST with a pager eats the line after it).
    text = sess(box, "OPTION $QUERY.DEBUG", 'LIST zzcx WITH CITY = "Paris" DEBUGGING')
    m = re.search(r"non\.ak\.selection\.index = (\d+)", text)
    say("    with the index:    non.ak.selection.index = %s" % (m.group(1) if m else "not printed"))
    row("a WITH clause on an E-type item with an index is taken by the index (non.ak.selection.index is not 1)",
        bool(m) and m.group(1) != "1", "got %r  %s" % (m.group(1) if m else None, text[-400:]))
    sess(box, "DELETE.INDEX zzcx CITY")
    text = sess(box, "OPTION $QUERY.DEBUG", 'LIST zzcx WITH CITY = "Paris" DEBUGGING')
    m = re.search(r"non\.ak\.selection\.index = (\d+)", text)
    say("    without the index: non.ak.selection.index = %s" % (m.group(1) if m else "not printed"))
    row("CONTROL: the same clause with the index deleted is not (non.ak.selection.index is 1)",
        bool(m) and m.group(1) == "1", "got %r  %s" % (m.group(1) if m else None, text[-400:]))
    text = sess(box, "CREATE.INDEX zzcx DNUM")
    row("an index on a D-type item with a field number is refused on a collection file",
        re.search(r"refers to a field number, which a data collection file does not have", text) is not None, text[-300:])
    text = sess(box, "CREATE.INDEX zzcn ENAME")
    row("an index on an E-type item is refused on an ordinary file",
        re.search(r"can only be used with a data collection file", text) is not None, text[-300:])
    for label, cmd, must, mustnot in QUERIES:
        text = sess(box, cmd)
        ok = all(re.search(rx, text) for rx in must) and not any(re.search(rx, text) for rx in mustnot)
        row(label, ok, "wanted %r, not %r; output: %s" % (must, mustnot, text[-600:]))
    sess(box, "DELETE.FILE zzcq", "DELETE.FILE zzcq2", "DELETE.FILE zzcn", "DELETE.FILE zzcx")


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) != 1:
        bail("usage: sandbox-coll.py <dir> [--build]")
    box = os.path.abspath(args[0])
    sysd = os.path.join(box, "sys")
    say("sandbox-coll: sandbox %s" % box)
    if "--build" in sys.argv:
        if os.path.exists(box) and os.listdir(box):
            bail("%s is not empty" % box)
        r = subprocess.run([sys.executable, TOOL, box, "all"], capture_output=True, text=True, errors="replace", timeout=900)
        if "[FAIL]" in r.stdout or r.returncode != 0 or "[PASS] THIRD.COMPILE" not in r.stdout:
            bail("the sandbox build did not pass:\n" + r.stdout[-800:])
        say("sandbox-coll: built, bootstrap passed")
    elif not os.path.isfile(os.path.join(sysd, "bin", "sd")):
        bail("%s holds no built sandbox (use --build, or point it at one)" % box)
    subprocess.run([sys.executable, TOOL, box, "start"], capture_output=True, text=True, errors="replace", timeout=120)

    # Files the cases use: two collection files and an ordinary one.  Made fresh, removed at the end.
    FILES = ["zzcf COLLECTION", "zzcf2 COLLECTION", "zzcn"]
    cmds, names = ["DELETE.FILE %s" % fl.split()[0] for fl in FILES], []
    cmds += ["CREATE.FILE %s" % fl for fl in FILES]
    for sub, src in SUBS.items():
        names.append(sub)
        with open(os.path.join(sysd, "bp", sub), "w") as f:
            f.write(src)
        cmds += ["BASIC bp %s" % sub, "CATALOG bp %s LOCAL" % sub]
    for i, (_, body, _w) in enumerate(CASES):
        nm = "zzco%02d" % i
        names.append(nm)
        with open(os.path.join(sysd, "bp", nm), "w") as f:
            f.write("   x = ''\n   " + "".join("%s\n   " % ln for ln in body.split("\n")) + "crt 'C%02d[':x:']'\nend\n" % i)
        cmds += ["BASIC bp %s" % nm, "RUN bp %s" % nm]
    cmds += ["DELETE.CATALOG %s LOCAL" % sub for sub in SUBS]
    cmds += ["DELETE.FILE %s" % fl.split()[0] for fl in FILES]
    try:
        out = sess(box, *cmds)
        try:
            with open(os.path.join(box, "coll.last.out"), "w") as f:   # for finding out why a row failed
                f.write(out)
        except OSError:
            pass
        say("\n--- collections -------------------------------------------------------------")
        starts = {}
        for m in re.finditer(r"(?m)^:BASIC bp zzco(\d{2,})\s*$", out):
            starts[int(m.group(1))] = m.start()
        for i, (label, _body, want) in enumerate(CASES):
            if i not in starts:
                row(label, False, "its compile was never seen in the output")
                continue
            later = [s for k, s in starts.items() if s > starts[i]]
            seg = out[starts[i]:(min(later) if later else len(out))]
            if want.startswith("ERR:"):
                text = want[4:]
                row("%s: wanted the text %r" % (label, text), text in seg and not re.search(r"(?m)^C%02d\[" % i, seg),
                    "output: %s" % seg[-300:])
            else:
                m = re.search(r"(?m)^C%02d\[(.*)\]\s*$" % i, seg)
                got = m.group(1) if m else None
                row("%s: wanted %r" % (label, want), got == want, "got %r  %s" % (got, seg[-200:]) if not m else "got %r" % got)
        run_queries(box, sysd, names)
    finally:
        for nm in names:
            for d in ("bp", "bp.out"):
                pth = os.path.join(sysd, d, nm)
                if os.path.exists(pth):
                    os.remove(pth)

    say("\nsandbox-coll: %d passed, %d failed" % (passed, failed))
    sys.exit(0 if failed == 0 else 1)


if __name__ == "__main__":
    main()
