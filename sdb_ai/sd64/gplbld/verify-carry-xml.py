#!/usr/bin/env python3
#
# sandbox-xml.py - the query processor's XML keyword (openQM 4, QM4 gap 211).  No install, no sudo.
#
#   python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/sandbox-xml.py <dir> [--build]
#
# <dir> is a sandbox made by sandbox-fromtree.py.  With --build it is built first from THIS tree (it must be empty
# or absent); without it <dir> must already be built.  Exit 0 every row passed, 1 a row failed, 2 it could not run.
#
# START-HISTORY:
# 16 Oct 26 dm  New.  qproc: XML, ELEMENTS, WITH.DTD, DTD.ONLY, WITH.SCHEMA, SCHEMA.ONLY (keywords 227-232 in parser.h and
#               newvoc); an XML report is set up as a delimited one and written by show.xml, xml.start and xml.end.
# END-HISTORY
#
# THE INSTRUMENT.  The commands sent and the lines of output are printed.  The output of a report is cut out of the session
# between the XML declaration and the closing root tag and given to a real XML parser (Python's), so a row is not a pattern on
# text: the document has to be well formed, and what the parser finds is what is judged.  The controls are the same file listed
# without XML (no root tag) and the refusals.  The file holds a name with an ampersand and a city with a "<", so escaping is
# judged by the parser giving the characters back.

import os
import re
import subprocess
import sys
import xml.etree.ElementTree as ET

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.path.join(HERE, "sandbox-fromtree.py")
ANSI = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]")
RUN = "%05d" % (os.getpid() % 100000)
FIL = "zzxm" + RUN
passed = failed = 0


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
    say("sandbox-xml: CANNOT RUN - " + msg)
    sys.exit(2)


def sess(box, *cmds, quiet=False):
    if not quiet:
        say("    > " + " | ".join(cmds))
    p = subprocess.run([sys.executable, TOOL, box, "sess", os.path.join(box, "user_accounts")] + list(cmds),
                       capture_output=True, text=True, errors="replace", timeout=600)
    out = ANSI.sub("", p.stdout + p.stderr)
    return out.split(":TERM 200,9999", 1)[-1]


def write(path, text):
    with open(path, "wb") as f:
        f.write(text.encode("latin-1"))   # a value mark is the byte 253


def reply(out, cmd):
    """What the session printed for the command cmd: from the line after its echo to the next prompt line."""
    part = out.split(":" + cmd, 1)[-1]
    part = part.split("\n", 1)[-1] if part.startswith("\n") else part
    lines = []
    for ln in part.splitlines()[1:] if part.splitlines() and part.splitlines()[0].strip() == "" else part.splitlines():
        if ln.startswith(":"):
            break
        lines.append(ln.rstrip())
    return lines


def document(lines, start=0):
    """The XML document in lines: from the declaration at or after start to the closing root tag."""
    for i in range(start, len(lines)):
        if lines[i].startswith("<?xml"):
            for j in range(i, len(lines)):
                if lines[j].strip() == "</ROOT>":
                    return "\n".join(lines[i:j + 1])
    return None


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) != 1:
        bail("usage: sandbox-xml.py <dir> [--build]")
    box = os.path.abspath(args[0])
    sysd = os.path.join(box, "sys")
    bp = os.path.join(sysd, "bp")
    say("sandbox-xml: sandbox %s" % box)
    if "--build" in sys.argv:
        if os.path.exists(box) and os.listdir(box):
            bail("%s is not empty" % box)
        r = subprocess.run([sys.executable, TOOL, box, "all"], capture_output=True, text=True, errors="replace", timeout=900)
        if "[FAIL]" in r.stdout or r.returncode != 0 or "[PASS] THIRD.COMPILE" not in r.stdout:
            bail("the sandbox build did not pass:\n" + r.stdout[-800:])
        say("sandbox-xml: built, bootstrap passed")
    elif not os.path.isfile(os.path.join(sysd, "bin", "sd")):
        bail("%s holds no built sandbox (use --build, or point it at one)" % box)
    subprocess.run([sys.executable, TOOL, box, "start"], capture_output=True, text=True, errors="replace", timeout=120)

    VM = "\xfd"
    recs = [("r1", ["Ann & Co", "A<B", "1" + VM + "2", "1.50" + VM + "2.00", "x" + VM + "y"]),
            ("r2", ["Bob", "", "5", "3.25", ""])]
    # (field number, heading, format, S or M, association)
    items = [(1, "name", "10L", "S", ""), (2, "city", "10L", "S", ""), (3, "qty", "5R", "M", "lines"),
             (4, "price", "8R", "M", "lines"), (5, "note", "5L", "M", "")]
    made = []
    for rid, flds in recs:
        write(os.path.join(bp, "zzxr" + RUN + rid), "\n".join(flds) + "\n")
        made.append("zzxr" + RUN + rid)
    for n, nm, fmt, sm, assoc in items:
        write(os.path.join(bp, "zzxd%s%d" % (RUN, n)), "D\n%d\n\n%s\n%s\n%s\n%s\n" % (n, nm, fmt, sm, assoc))
        made.append("zzxd%s%d" % (RUN, n))
    cmds = ["DELETE.FILE DICT %s" % FIL, "DELETE.FILE %s" % FIL, "CREATE.FILE %s" % FIL]
    for rid, _ in recs:
        cmds.append("COPY FROM BP TO %s zzxr%s%s,%s" % (FIL, RUN, rid, rid))
    for n, nm, fmt, sm, assoc in items:
        cmds.append("COPY FROM BP TO DICT %s zzxd%s%d,%s" % (FIL, RUN, n, nm))

    try:
        say("\n--- setup ---------------------------------------------------------------------")
        out = sess(box, *cmds, quiet=True)
        copied = len(re.findall(r"(?m)^1 record\(s\) copied\.", out))
        row("setup: two records and five dictionary items were copied", copied == len(recs) + len(items), "copied %d" % copied)

        base = "LIST %s name city qty price note ID.SUP" % FIL
        c_plain = base
        c_xml = base + " XML"
        c_el = base + " XML ELEMENTS"
        c_dtd = base + " XML WITH.DTD"
        c_dtdo = base + " XML DTD.ONLY"
        c_sch = base + " XML WITH.SCHEMA"
        c_scho = base + " XML SCHEMA.ONLY"
        c_det = base + " DET.SUP XML"
        c_bad1 = base + " ELEMENTS"
        c_bad2 = base + " BREAK.ON city XML"
        c_bad3 = base + " TOTAL qty XML"
        out = sess(box, c_plain, c_xml, c_el, c_dtd, c_dtdo, c_sch, c_scho, c_det, c_bad1, c_bad2, c_bad3)

        say("\n--- the report as XML ---------------------------------------------------------")
        plain = reply(out, c_plain)
        row("CONTROL: without XML the report is the ordinary one (no root tag, no declaration)",
            plain and "<ROOT>" not in "\n".join(plain) and "<?xml" not in "\n".join(plain) and "Ann & Co" in "\n".join(plain), "\n".join(plain)[:300])

        lines = reply(out, c_xml)
        for ln in lines:
            say("      | " + ln)
        row("the output starts with the XML declaration and the root tag", len(lines) > 2 and lines[0] == '<?xml version="1.0" encoding="UTF-8"?>' and lines[1] == "<ROOT>", repr(lines[:3]))
        doc = document(lines)
        try:
            root = ET.fromstring(doc.encode("utf-8")) if doc else None
        except ET.ParseError as e:
            root = None
            say("      parse error: %s" % e)
        row("the document is well formed XML (a real parser reads it)", root is not None, str(doc)[:300])
        recs_x = root.findall(FIL) if root is not None else []
        row("one element per record, named for the file", len(recs_x) == 2, repr([c.tag for c in root] if root is not None else None))
        row("nothing but the records is in the root element (no 'record(s) listed' line in the document)",
            root is not None and not (root.text or "").strip() and all(not (c.tail or "").strip() for c in root) and "record(s)" not in "\n".join(lines), "\n".join(lines)[-200:])
        r1 = recs_x[0] if recs_x else None
        row("single valued fields are attributes, and the characters XML reserves come back from the parser as they were",
            r1 is not None and r1.get("name") == "Ann & Co" and r1.get("city") == "A<B", repr(r1.attrib if r1 is not None else None))
        rows1 = r1.findall("lines") if r1 is not None else []
        row("an association is one tag for each row, named for the association, a value in each attribute",
            [x.attrib for x in rows1] == [{"qty": "1", "price": "1.50"}, {"qty": "2", "price": "2.00"}], repr([x.attrib for x in rows1]))
        notes = r1.findall("note_MV") if r1 is not None else []
        row("a multivalued field in no association is one tag for each value, named for the field with _MV",
            [x.attrib for x in notes] == [{"note": "x"}, {"note": "y"}], repr([x.attrib for x in notes]))
        r2 = recs_x[1] if len(recs_x) > 1 else None
        row("a field with no value is left out: Bob has no city, no note", r2 is not None and r2.get("name") == "Bob" and "city" not in r2.attrib and not r2.findall("note_MV"), repr(r2.attrib if r2 is not None else None))
        row("...and his one association row is there", r2 is not None and [x.attrib for x in r2.findall("lines")] == [{"qty": "5", "price": "3.25"}], repr(r2 is not None and [x.attrib for x in r2.findall("lines")]))

        say("\n--- ELEMENTS ---------------------------------------------------------------------")
        lines = reply(out, c_el)
        for ln in lines:
            say("      | " + ln)
        doc = document(lines)
        try:
            root = ET.fromstring(doc.encode("utf-8")) if doc else None
        except ET.ParseError as e:
            root = None
            say("      parse error: %s" % e)
        row("the ELEMENTS document is well formed XML", root is not None, str(doc)[:300])
        r1 = root.find(FIL) if root is not None else None
        row("each single valued field is an element of its own",
            r1 is not None and r1.findtext("name") == "Ann & Co" and r1.findtext("city") == "A<B", repr([(c.tag, c.text) for c in r1] if r1 is not None else None))
        rows1 = r1.findall("lines") if r1 is not None else []
        row("an association row is an element that holds one element for each field",
            [{c.tag: c.text for c in x} for x in rows1] == [{"qty": "1", "price": "1.50"}, {"qty": "2", "price": "2.00"}], repr([{c.tag: c.text for c in x} for x in rows1]))
        row("a multivalued field in no association is an element for each value, named with _MV",
            [x.text for x in (r1.findall("note_MV") if r1 is not None else [])] == ["x", "y"], "")

        say("\n--- DTD and schema ---------------------------------------------------------------")
        lines = reply(out, c_dtd)
        text = "\n".join(lines)
        row("WITH.DTD: a DOCTYPE for ROOT with the declarations, then the data", "<!DOCTYPE ROOT [" in text and "<!ELEMENT ROOT (%s*)>" % FIL in text and "<!ATTLIST %s name CDATA #IMPLIED city CDATA #IMPLIED>" % FIL in text and "<ROOT>" in text, text[:600])
        try:
            ET.fromstring(document(lines).encode("utf-8"))
            ok = True
        except (ET.ParseError, AttributeError):
            ok = False
        row("...and the parser accepts the document with its DTD", ok, text[:300])
        lines = reply(out, c_dtdo)
        text = "\n".join(lines)
        row("DTD.ONLY: the declarations and no data", "<!ELEMENT ROOT" in text and "<ROOT>" not in text and "Ann" not in text and "<?xml" not in text, text[:500])
        lines = reply(out, c_sch)
        text = "\n".join(lines)
        row("WITH.SCHEMA: a schema, then the data", "<xs:schema" in text and "</xs:schema>" in text and "<ROOT>" in text and "Ann &amp; Co" in text, text[:300])
        lines = reply(out, c_scho)
        text = "\n".join(lines)
        try:
            sch = ET.fromstring(text.encode("utf-8")) if text.startswith("<?xml") else None
        except ET.ParseError as e:
            sch = None
            say("      parse error: %s" % e)
        names = [e.get("name") for e in sch.iter("{http://www.w3.org/2001/XMLSchema}element")] if sch is not None else []
        row("SCHEMA.ONLY: a well formed schema that names the elements, and no data",
            sch is not None and "ROOT" in names and FIL in names and "lines" in names and "note_MV" in names and "Ann" not in text, repr(names))

        text = "\n".join(reply(out, c_det))
        row("DET.SUP is ignored in an XML report: the records are there", "<ROOT>" in text and text.count("<%s " % FIL) == 2, text[:300])

        say("\n--- what is refused ----------------------------------------------------------------")
        text = "\n".join(reply(out, c_bad1))
        row("ELEMENTS without XML is refused", "need the xml keyword" in text and "<ROOT>" not in text, text[:300])
        text = "\n".join(reply(out, c_bad2))
        row("a breakpoint in an XML report is refused", "cannot have breakpoints" in text and "<ROOT>" not in text, text[:300])
        text = "\n".join(reply(out, c_bad3))
        row("a total in an XML report is refused", "cannot have breakpoints" in text and "<ROOT>" not in text, text[:300])
    finally:
        say("\n--- cleanup ---------------------------------------------------------------")
        sess(box, "DELETE.FILE DICT %s" % FIL, "DELETE.FILE %s" % FIL, quiet=True)
        for n in made:
            p = os.path.join(bp, n)
            if os.path.exists(p):
                os.remove(p)

    say("")
    say("sandbox-xml: %d passed, %d failed" % (passed, failed))
    if passed + failed == 0:
        bail("no row ran - a broken test, not a pass")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
