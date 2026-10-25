#!/usr/bin/env python3
"""test-vocnames-units.py - the shipped VOC records and BASIC programs name things in lower case.

WHY (PAL-1 stage 3a/3b, 7 Oct 2026).  Program, call and catalogue names are lower case in SD (stage 3a), and
the owner's standard is that nothing SD ships spells a name two ways.  Two kinds of shipped text still could:

  1. the VOC record of a verb (sdsys/newvoc, sdsys/voc_template): line 3 of a CA record names the
     catalogued program that runs it.  It was $ALIAS; it is $alias.
  2. a $include line in an SD BASIC program (sdsys/gpl.bp): it was `$include KEYS.H`; it is `keys.h`, the
     name of the file on disk.  On ext4 the other spelling is only found through the program's own fold.

It reads files; no SD, no install, no sudo.  The control is a copy of a record with a capital planted, which
this check must refuse.  Exit 0 all rows passed, 1 a row failed, 2 it could not run.

  python3 gplbld/test-vocnames-units.py
"""

import os
import re
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
SDSYS = os.path.normpath(os.path.join(HERE, os.pardir, "sdsys"))
LAYERS = [os.path.join(SDSYS, "newvoc"), os.path.join(SDSYS, "voc_template")]
GPLBP = os.path.join(SDSYS, "gpl.bp")
passed = failed = 0


def row(name, ok, detail=""):
    global passed, failed
    if ok:
        passed += 1
        print("  [PASS] " + name)
    else:
        failed += 1
        print("  [FAIL] " + name + ("   <- " + detail if detail else ""))


def text(p):
    with open(p, "rb") as f:
        return f.read().replace(b"\r\n", b"\n").decode("latin-1")


def ca_names(lines):
    """The program names a VOC record's CA type line names: every line after a line that is exactly CA and
    starts with '$' or '!' (the one-field shape is verb, 'CA', '$name'; COUNT and a few have more fields)."""
    out = []
    for i, ln in enumerate(lines):
        if ln.strip() == "CA" and i + 1 < len(lines) and lines[i + 1][:1] in ("$", "!"):
            out.append(lines[i + 1].strip())
    return out


def bad_voc_names(directory):
    bad = []
    for n in sorted(os.listdir(directory)):
        p = os.path.join(directory, n)
        if os.path.isfile(p):
            for nm in ca_names(text(p).split("\n")):
                if nm != nm.lower():
                    bad.append("%s/%s: %s" % (os.path.basename(directory), n, nm))
    return bad


INCLUDE = re.compile(r"^\s*\$include\s+(\S+)", re.I | re.M)


def bad_includes():
    bad = []
    for n in sorted(os.listdir(GPLBP)):
        p = os.path.join(GPLBP, n)
        if os.path.isfile(p):
            for m in INCLUDE.finditer(text(p)):
                if m.group(1) != m.group(1).lower():
                    bad.append("%s: $include %s" % (n, m.group(1)))
    return bad


def main():
    for d in LAYERS + [GPLBP]:
        if not os.path.isdir(d):
            print("test-vocnames-units: CANNOT RUN - %s is missing" % d)
            return 2
    n_ca = sum(len(ca_names(text(os.path.join(d, n)).split("\n"))) for d in LAYERS for n in os.listdir(d)
               if os.path.isfile(os.path.join(d, n)))
    row("CONTROL: the two VOC layers hold 150 or more catalogued verbs", n_ca >= 150, "found %d" % n_ca)
    with tempfile.TemporaryDirectory() as td:
        with open(os.path.join(td, "planted"), "w") as f:
            f.write("Verb\nCA\n$ALIAS\n")
        with open(os.path.join(td, "clean"), "w") as f:
            f.write("Verb\nCA\n$alias\n")
        planted = bad_voc_names(td)
    row("CONTROL: the detector refuses a planted capital and passes a clean record",
        len(planted) == 1 and planted[0].endswith("planted: $ALIAS"), repr(planted))
    for d in LAYERS:
        bad = bad_voc_names(d)
        row("%s: no verb names its program with a capital letter" % os.path.basename(d), not bad, "; ".join(bad[:6]))
    n_inc = sum(len(INCLUDE.findall(text(os.path.join(GPLBP, n)))) for n in os.listdir(GPLBP) if os.path.isfile(os.path.join(GPLBP, n)))
    row("CONTROL: gpl.bp holds 500 or more $include lines", n_inc >= 500, "found %d" % n_inc)
    bad = bad_includes()
    row("gpl.bp: every $include names its file in lower case", not bad, "; ".join(bad[:6]))
    print("test-vocnames-units: %d passed, %d failed" % (passed, failed))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
