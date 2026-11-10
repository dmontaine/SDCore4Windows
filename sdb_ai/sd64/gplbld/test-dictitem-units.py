#!/usr/bin/env python3
"""test-dictitem-units.py - S.90 stage 1: the dictionary item engine !dict_item, read off the source as text.

  python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/test-dictitem-units.py
  python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/test-dictitem-units.py --selftest

No sudo, no install, no sd.  Exit 0 every check passed, 1 a check failed, 2 it could not run.

START-HISTORY:
31 Oct 26 dm  New with the engine (plan .claude/plan-s90-dict-form.md).
END-HISTORY

WHAT IT HOLDS.  gpl.bp/dict_item is the rules of the dictionary item form with no screen in it: the six types, the rows of each (the limits the owner asked to be checked:
a D item's field number a whole number from 0 to 9999, width 1 to 200, decimals 0 to 9, heading 40, conversion 40 and one oconv knows, association 30 and only for a
multivalued item), the record read into values, the values checked and built back.  It writes nothing, opens nothing and prints nothing; it trims the ENDS of a value only (a
blank inside an expression is the person's); a number leaves as a string so that 0 is never taken for an empty answer; every row is checked BEFORE any record is made and an
error returns before it; a record that changes type starts from the bare type.

***IT READS THE SOURCE AS TEXT.***  That each rule gives the right answer on real values is sandbox-dictitem.py (the engine RUN).  --selftest requires each mutation to match
its text exactly once and to be caught.
"""

import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
GPL = os.path.join(HERE, os.pardir, "sdsys", "gpl.bp")
ENGINE = os.path.join(GPL, "dict_item")


def strip(src):
    """the code without comment lines and trailing ;* comments"""
    out = []
    for ln in src.split("\n"):
        if ln.lstrip().startswith("*"):
            continue
        out.append(re.sub(r"\s*;\*.*$", "", ln))
    return "\n".join(out)


def ordered(text, *parts):
    pos = -1
    for p in parts:
        i = text.find(p, pos + 1)
        if i < 0:
            return False
        pos = i
    return True


def checks(src, others):
    rows = []

    def ck(name, ok, detail=""):
        rows.append((name, bool(ok), detail))

    code = strip(src)
    ck("D0 NULL CASE: the reader sees the engine (over 8 KB of code)", len(code) > 8000, repr(len(code)))
    ck("D1a it is $internal, `subroutine dict_item(op, a, b, c, d)`, catalogued as !dict_item",
       code.lstrip().startswith("$internal") and re.search(r"^subroutine dict_item\(op, a, b, c, d\)$", code, re.M) is not None and "$catalog !dict_item" in code, "")
    ck("D1b ...and no other program of gpl.bp takes the catalogue name", not any(re.search(r"^\$catalog\s+!dict_item\b", strip(t), re.M | re.I) for t in others.values()), "")
    bad = re.findall(r"\b(openseq|openpath|open|write|writev|writeu|delete|execute|perform|crt|print|display|input|screen|kernel|chain|call\s+(?!!dict_item))\b", code, re.I)
    ck("D2 it writes nothing, opens nothing, prints nothing, asks no screen and calls nothing", not bad, repr(bad[:5]))
    ck("D3 the types are exactly D E I L PH X, one case each in rows.for",
       "TYPES = 'D' : @fm : 'E' : @fm : 'I' : @fm : 'L' : @fm : 'PH' : @fm : 'X'" in code
       and all(("case ty = '%s'" % t) in code for t in ("D", "E", "I", "L", "PH", "X"))
       and len(re.findall(r"^      case ty = '", code[code.find("\nrows.for:"):code.find("\nrows.tail:")], re.M)) == 6, "")
    ck("D4 the limits of the owner's example: loc 0 to 9999, width 1 to 200, decimals 0 to 9, heading 40, conversion 40, association 30, expression 300",
       all(s in code for s in ("'loc' : @vm : 'Field #' : @vm : 'num' : @vm : 0 : @vm : 9999 : @vm : 0", "'width' : @vm : 'Width' : @vm : 'num' : @vm : 1 : @vm : 200 : @vm : 1",
                               "'dec' : @vm : 'Decimals' : @vm : 'num' : @vm : 0 : @vm : 9 : @vm : 1", "'head' : @vm : 'Column Heading' : @vm : 'text' : @vm : '' : @vm : 40 : @vm : 1",
                               "'conv' : @vm : 'Conversion Cd' : @vm : 'conv' : @vm : '' : @vm : 40 : @vm : 1", "'assoc' : @vm : 'Association' : @vm : 'word' : @vm : '' : @vm : 30 : @vm : 1",
                               "'expr' : @vm : 'Expression' : @vm : 'expr' : @vm : '' : @vm : 300 : @vm : 0")), "")
    ck("D4b the owner's labels (31 Oct 26): Column Heading and Conversion Cd for D, E and I; Element Path, Id Expression and File Expression for the rows that were Path, Id expression and File expression",
       all(s in code for s in ("'path' : @vm : 'Element Path'", "'idexpr' : @vm : 'Id Expression'", "'fexpr' : @vm : 'File Expression'")), "")
    ck("D4c Len & Just: fmtshow makes ONE text from width, justification and decimals (30 L, 12 R 2) and fmtsplit reads it back through the rows' own rules (width 1 to 200, one of L R T C, decimals 0 to 9); neither writes anything",
       ordered(code, "case op.l = 'fmtshow'", "gosub do.fmtshow", "case op.l = 'fmtsplit'", "gosub do.fmtsplit")
       and ordered(code, "do.fmtshow:", "b = a{'width'} : ' ' : a{'just'}", "if a{'dec'} # '' then b := ' ' : a{'dec'}", "do.fmtsplit:", "tv.kind = 'num' ; tv.lo = 1 ; tv.hi = 200 ;", "tv.kind = 'just'",
               "tv.kind = 'num' ; tv.lo = 0 ; tv.hi = 9 ;", "b{'width'} = fx.w", "b{'just'} = fx.j", "b{'dec'} = fx.d"), "")
    ck("D5 the association row depends on sm = M, and build leaves it out otherwise",
       "'assoc' : @vm : 'Association'" in code and ": @vm : 'sm' : @vm : 'M'" in code
       and ordered(code, "if rw<rp, 7> # '' then", "if upcase(trim(a{rw<rp, 7>})) # rw<rp, 8> then skip = 1", "if skip then", "tv.val = ''", "tv.opt = 1")
       and "and upcase(trim(a{" not in code, "")
    ck("D6 the field number is a whole number: only digits, at most five characters, and the answer is a string",
       ordered(code, "case tv.kind = 'num'", "tv.ok = (len(tv.val) <= 5)", "index('0123456789'", "tv.val = (tv.val + 0) : ''", "tv.val + 0 >= tv.lo and tv.val + 0 <= tv.hi"), "")
    ck("D7 only the ends of a value are trimmed (a blank inside an expression is kept)", "tv.val = trimb(trimf(tv.val))" in code and "trim(tv.val)" not in code.replace("trimb(trimf(tv.val))", ""), "")
    ck("D8 a conversion is one oconv knows (status 2 is no), except the user conversions that begin with U",
       ordered(code, "case tv.kind = 'conv'", "upcase(tv.val[1, 1]) # 'U'", "void oconv('1', tv.val)", "if status() = 2 then tv.err"), "")
    ck("D9 an L item's expressions are one expression: no semicolon",
       "(tv.key = 'idexpr' or tv.key = 'fexpr') and index(tv.val, ';', 1) > 0" in code, "")
    ck("D10 build checks every row first and returns on the first error BEFORE it makes the record; the record is assembled after",
       ordered(code, "do.build:", "gosub test.value", "d = key : @fm : rw<rp, 2>", "return", "oty = upcase(old<1>[1, 2])", "rec = old") and code.count("rec = old") == 1, "")
    ck("D11 a record that changes type starts from the bare type (the compile stamp and object code would not fit), and one that keeps its type keeps what is not shown",
       "if oty # ty then rec = ty" in code and ordered(code, "rec = old", "if oty # ty then rec = ty"), "")
    ck("D12 an empty value is written only where the record already has the field (no trailing empty fields)",
       ordered(code, "set.field:", "if fv # '' or fn <= dcount(rec, @fm) then rec<fn> = fv"), "")
    ck("D13 a width without a justification, and the reverse, are refused by name",
       ordered(code, "if vals{'width'} # '' or vals{'just'} # '' or vals{'dec'} # '' then", "if vals{'width'} = '' then", "d = 'width'", "return", "if vals{'just'} = '' then", "d = 'just'"), "")
    ck("D14 parse sets every key before it reads the record, and says 'type' for a type the form does not know, 'format' for a format it cannot split",
       ordered(code, "do.parse:", "allkeys = ", "b{allkeys<kp>} = ''", "d = 'format'") and "d = 'type'" in code, "")
    return rows


def load():
    with open(ENGINE, encoding="latin-1") as f:
        src = f.read()
    others = {}
    for n in sorted(os.listdir(GPL)):
        p = os.path.join(GPL, n)
        if n != "dict_item" and os.path.isfile(p):
            with open(p, encoding="latin-1") as f:
                others[n] = f.read()
    return src, others


def report(rows):
    bad = 0
    for name, ok, detail in rows:
        bad += 0 if ok else 1
        print("  [%s] %s%s" % ("PASS" if ok else "FAIL", name, "" if ok else "   <- " + detail))
    return bad


# (name, old, new): each must match the engine's text once and be caught
MUTANTS = [
    ("it writes a record", "      case op.l = 'types'\n         b = TYPES", "      case op.l = 'types'\n         write b to df, 'x'\n         b = TYPES"),
    ("Len & Just takes a width of 201", "tv.key = 'width' ; tv.kind = 'num' ; tv.lo = 1 ; tv.hi = 200 ; tv.opt = 0 ; tv.val = fx.w", "tv.key = 'width' ; tv.kind = 'num' ; tv.lo = 1 ; tv.hi = 2000 ; tv.opt = 0 ; tv.val = fx.w"),
    ("Len & Just takes ten decimals", "tv.key = 'dec' ; tv.kind = 'num' ; tv.lo = 0 ; tv.hi = 9 ; tv.opt = 1 ; tv.val = fx.d", "tv.key = 'dec' ; tv.kind = 'num' ; tv.lo = 0 ; tv.hi = 99 ; tv.opt = 1 ; tv.val = fx.d"),
    ("Len & Just forgets the decimals", "      if a{'dec'} # '' then b := ' ' : a{'dec'}", "      if 0 then b := ' ' : a{'dec'}"),
    ("the column heading is called Heading again", "'head' : @vm : 'Column Heading'", "'head' : @vm : 'Heading'"),
    ("it prints", "   TYPES = 'D' : @fm", "   crt 'hello'\n   TYPES = 'D' : @fm"),
    ("a type is missing", "TYPES = 'D' : @fm : 'E' : @fm : 'I' : @fm : 'L' : @fm : 'PH' : @fm : 'X'", "TYPES = 'D' : @fm : 'E' : @fm : 'I' : @fm : 'L' : @fm : 'PH'"),
    ("the field number may be 10000", "'num' : @vm : 0 : @vm : 9999 : @vm : 0", "'num' : @vm : 0 : @vm : 10000 : @vm : 0"),
    ("the width may be 0", "'num' : @vm : 1 : @vm : 200 : @vm : 1", "'num' : @vm : 0 : @vm : 200 : @vm : 1"),
    ("the heading may be 80 long", "'text' : @vm : '' : @vm : 40 : @vm : 1", "'text' : @vm : '' : @vm : 80 : @vm : 1"),
    ("the association does not depend on sm", ": @vm : 30 : @vm : 1 : @vm : 'sm' : @vm : 'M'", ": @vm : 30 : @vm : 1"),
    ("a number stays a number", "tv.val = (tv.val + 0) : ''", "tv.val = tv.val + 0"),
    ("a value is trimmed all through", "tv.val = trimb(trimf(tv.val))", "tv.val = trim(tv.val)"),
    ("a conversion is not asked of oconv", "               void oconv('1', tv.val)\n               if status() = 2 then tv.err = 'SD does not know this conversion'", "               null"),
    ("a semicolon is allowed in a link", "(tv.key = 'idexpr' or tv.key = 'fexpr') and index(tv.val, ';', 1) > 0", "(tv.key = 'idexpr' or tv.key = 'fexpr') and index(tv.val, '~', 1) > 0"),
    ("the record is made before the rows are checked", "   old = b\n   ty = upcase(trim(a{'type'}))", "   old = b\n   rec = old\n   ty = upcase(trim(a{'type'}))"),
    ("a new type keeps the old record", "   if oty # ty then rec = ty ", "   if oty # 'zz' then rec = rec "),
    ("trailing empty fields are made", "   if fv # '' or fn <= dcount(rec, @fm) then rec<fn> = fv", "   rec<fn> = fv"),
    ("width without justification is allowed", "         if vals{'just'} = '' then\n            d = 'just'", "         if 0 then\n            d = 'just'"),
    ("parse does not set the keys", "      b{allkeys<kp>} = ''", "      null"),
]


def selftest():
    src, others = load()
    if any(not ok for _, ok, _ in checks(src, others)):
        print("REFUSING - the unmutated source already fails", file=sys.stderr)
        return 2
    holes = 0
    print("--- self-test: each mutation must be CAUGHT and match its text once ---")
    for name, old, new in MUTANTS:
        n = src.count(old)
        if n != 1:
            print("  [FAIL] %s: the text matches %d times, not once" % (name, n))
            holes += 1
            continue
        caught = [x.split(" ")[0] for x, ok, _ in checks(src.replace(old, new), others) if not ok]
        print("  [%s] %s%s" % ("pass" if caught else "FAIL", name, ": caught by " + ", ".join(caught[:3]) if caught else ": NOT CAUGHT"))
        holes += 0 if caught else 1
    o2 = dict(others)
    o2["zz_clash"] = "$internal\nsubroutine zz_clash\n$catalog !dict_item\nend\n"
    caught = [x.split(" ")[0] for x, ok, _ in checks(src, o2) if not ok]
    print("  [%s] another program takes the catalogue name%s" % ("pass" if caught else "FAIL", ": caught by " + ", ".join(caught) if caught else ": NOT CAUGHT"))
    holes += 0 if caught else 1
    total = len(MUTANTS) + 1
    print("\n%d of %d mutants caught, %d missed" % (total - holes, total, holes))
    return 1 if holes else 0


def main():
    if not os.path.isfile(ENGINE):
        print("test-dictitem-units: CANNOT RUN - not readable: %s" % ENGINE, file=sys.stderr)
        return 2
    if "--selftest" in sys.argv[1:]:
        return selftest()
    src, others = load()
    rows = checks(src, others)
    bad = report(rows)
    print("\nNOT MEASURED HERE: that any rule gives the right answer on a real value.  That is sandbox-dictitem.py.")
    print("test-dictitem-units: %d checks, %d failed" % (len(rows), bad))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
