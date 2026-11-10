#!/usr/bin/env python3
#
# test-usspelling-units.py - what SD prints is in US spelling (S.186; the owner, 9 Nov 2026: "Everything SD prints").  No install, no sudo.
#
#   python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/test-usspelling-units.py [--selftest]
#
# START-HISTORY:
# 9 Nov 26 Windows port - from Linux ad4a2cf6 (S.186), the spelling half only (RELEASE_1.1 205).  tool_tktest is skipped until the TUI carries; no other change.
# 9 Nov 26 dm  New (S.186).  The US spelling sweep of 9 Nov changed SD's messages, help, program texts, C strings and the guide; this check keeps a
#              British form from coming back in a new text.  The owner asked for a check that catches "simple failures like spelling" before suites run.
# END-HISTORY
#
# WHAT IT READS.  sdsys/messages/* and sdsys/helptext/* (all of each); the STRING LITERALS of the code lines of sdsys/gpl.bp/* (not comments, so a
# dated history line is left as it was written); the string literals of gplsrc/*.c; the prose of agent-pack/guide/sd-basic-guide.md (not its fenced
# blocks, which are programs, and not a code span of one word, which is a name).
#
# THE RULE (the sweep's).  A British form (catalogue, colour, analyse, initialise, recognise, licence, behaviour, centre, cancelled, honour, labelled,
# dialogue, grey ...) is a fault when it stands as a word.  It is NOT one when it is part of a name: next to a letter, digit, '_', '$', '%', '/' or '\',
# or next to a '.' that has a letter or digit on its other side (analyse.index, option catalogue.local); an ALL-CAPS word is a keyword form.
# Names SD keeps on purpose are listed in KEEP (a BASIC keyword, a terminfo capability, a file name).

import io
import os
import re
import sys
import tokenize

HERE = os.path.dirname(os.path.abspath(__file__))
SD64 = os.path.dirname(HERE)
SDSYS = os.path.join(SD64, "sdsys")

UK = ["catalogues", "catalogued", "cataloguing", "catalogue", "colours", "coloured", "colouring", "colour", "analysed", "analysing", "analyse",
      "behaviours", "behaviour", "centres", "centred", "centring", "centre", "licences", "licence", "unrecognised", "unrecognisable", "recognises",
      "recognised", "recognising", "recognise", "initialisation", "initialises", "initialised", "initialising", "initialise", "cancelled", "cancelling",
      "honours", "honoured", "honouring", "honour", "labelled", "labelling", "modelled", "travelling", "dialogues", "dialogue", "synchronises",
      "synchronised", "synchronise", "authorised", "authorises", "authorise", "minimised", "minimise", "normalised", "normalises", "normalise",
      "customised", "customise", "utilised", "utilise", "optimised", "optimise", "favourite", "favour", "neighbours", "neighbour", "greyed", "grey"]
RX = re.compile(r"(?<![A-Za-z0-9_$%/\\])(?<![A-Za-z0-9]\.)(" + "|".join(UK) + r")(?![A-Za-z0-9_$%/\\])(?!\.[A-Za-z0-9])", re.I)

# Names SD keeps: the BASIC keywords and the syntax colour's word list (sl_syndef), a file name ('licence', config), a settings section that is read back
# (settingsr), the generated error text (errtext.h: its source gplsrc/err.h is read instead), the terminfo capability colourmap (op_tio.c, ti_names.h).
SKIP_FILES = {"sl_syndef", "config", "settingsr", "errtext.h",
              "tool_tktest"}   # Windows: the TUI test page, held with the TUI carries; its literals include command words (tktest colour) and hotkeys
KEEP_WORDS = {"colourmap"}

passed = failed = 0


def row(name, ok, detail=""):
    global passed, failed
    if ok:
        passed += 1
        print("  [PASS] " + name)
    else:
        failed += 1
        print("  [FAIL] " + name + ("   <- " + detail if detail else ""))
    return ok


def hits_in(text):
    return [m.group(1) for m in RX.finditer(text) if not (m.group(1).isupper() and len(m.group(1)) > 1)]


def basic_literals(line):
    """The string literals of a code line of SD BASIC: none on a comment line, nothing after ;*, nothing on a key table row (its action id is a name)."""
    st = line.lstrip()
    if st.startswith("*") or st.startswith("!") or re.match(r"(?i)rem\b", st) or "tk_keys(" in line:
        return []
    out, i, n = [], 0, len(line)
    while i < n:
        ch = line[i]
        if ch == ";" and line[i:i + 2] == ";*":
            break
        if ch in "'\"":
            j = line.find(ch, i + 1)
            if j < 0:
                break
            out.append(line[i + 1:j])
            i = j + 1
            continue
        i += 1
    return out


def c_literals(src):
    """The string literals of C source outside comments."""
    src = re.sub(r"/\*.*?\*/", " ", src, flags=re.S)
    src = re.sub(r"//[^\n]*", " ", src)
    return re.findall(r'"((?:[^"\\\n]|\\.)*)"', src)


def md_prose(src):
    out, fenced = [], False
    for line in src.splitlines():
        if line.lstrip().startswith("```"):
            fenced = not fenced
            continue
        if fenced:
            continue
        for p in re.split(r"(`[^`]*`)", line):
            if p.startswith("`") and p.endswith("`") and len(p) >= 2 and " " not in p.strip("`").strip():
                continue
            out.append(p)
    return "\n".join(out)


def ps_literals(text):
    """The quoted texts of a PowerShell installer script: both quote styles, nothing on a comment line.  (Windows port, RELEASE_1.1 205.)"""
    out = []
    for line in text.split("\n"):
        st = line.lstrip()
        if st.startswith("#") or st.startswith("<#") or st.startswith("*>"):
            continue
        out.extend(m.group(1) for m in re.finditer(r"'((?:[^']|'')*)'", line))
        out.extend(m.group(1) for m in re.finditer(r'"((?:[^"`]|`.)*)"', line))
    return out


def iss_literals(text):
    """The quoted texts of an Inno Setup script: ( * * ) and { } comments are removed first, then lines starting ; or //."""
    text = re.sub(r"\(\*.*?\*\)", " ", text, flags=re.S)
    text = re.sub(r"\{[^}]*\}", " ", text, flags=re.S)
    out = []
    for line in text.split("\n"):
        st = line.lstrip()
        if st.startswith(";") or st.startswith("//"):
            continue
        if st.count("'") % 2 == 0:
            line = re.sub(r"//.*$", "", line)
        out.extend(m.group(1) for m in re.finditer(r"'((?:[^']|'')*)'", line))
        out.extend(m.group(1) for m in re.finditer(r'"([^"]*)"', line))
    return out


def scan(files):
    """files: {label: (kind, text)} where kind is text, basic, c, md, ps1 or iss.  Returns [(label, line number or '', word, context)]."""
    found = []
    for label, (kind, text) in sorted(files.items()):
        if kind in ("ps1", "iss"):
            for lit in (ps_literals(text) if kind == "ps1" else iss_literals(text)):
                for w in hits_in(lit):
                    found.append((label, "", w, lit[:80]))
        elif kind == "basic":
            for n, line in enumerate(text.split("\n"), 1):
                for lit in basic_literals(line):
                    for w in hits_in(lit):
                        found.append((label, n, w, lit[:80]))
        elif kind == "c":
            for lit in c_literals(text):
                for w in hits_in(lit):
                    if w.lower() not in KEEP_WORDS:
                        found.append((label, "", w, lit[:80]))
        elif kind == "md":
            for w in hits_in(md_prose(text)):
                found.append((label, "", w, ""))
        else:
            for n, line in enumerate(text.split("\n"), 1):
                for w in hits_in(line):
                    found.append((label, n, w, line.strip()[:80]))
    return found


def read_tree():
    files = {}

    def add(path, kind, label):
        with open(path, encoding="latin-1") as f:
            files[label] = (kind, f.read())
    for sub, kind in (("messages", "text"), ("helptext", "text"), ("gpl.bp", "basic")):
        d = os.path.join(SDSYS, sub)
        for nm in sorted(os.listdir(d)):
            p = os.path.join(d, nm)
            if os.path.isfile(p) and nm not in SKIP_FILES:
                add(p, kind, "%s/%s" % (sub, nm))
    g = os.path.join(SD64, "gplsrc")
    for nm in sorted(os.listdir(g)):
        if nm.endswith(".c"):
            add(os.path.join(g, nm), "c", "gplsrc/" + nm)
    guide = os.path.join(SD64, "agent-pack", "guide", "sd-basic-guide.md")
    if os.path.isfile(guide):
        add(guide, "md", "agent-pack/guide/sd-basic-guide.md")
    # Windows port (RELEASE_1.1 205): what the INSTALLER and its scripts print.  Every .ps1 and .iss of gplbld except the suites, probes and test tools,
    # which hold expectations of SD's wording (checked by test-identtwins-units.py and the verifiers' own runs), not text a person reads.
    gb = os.path.join(SD64, "gplbld")
    for nm in sorted(os.listdir(gb)):
        if re.match(r"(verify-|VerifyInstall|test-|probe-|sandbox-|check-free)", nm):
            continue
        if nm.endswith(".ps1") or nm.endswith(".iss"):
            add(os.path.join(gb, nm), "ps1" if nm.endswith(".ps1") else "iss", "gplbld/" + nm)
    return files


def judge(files, quiet=False):
    found = scan(files)
    kinds = {}
    for label, (kind, _t) in files.items():
        kinds[kind] = kinds.get(kind, 0) + 1
    ok0 = (kinds.get("text", 0) > 1000 and kinds.get("basic", 0) > 300 and kinds.get("c", 0) > 20
           and kinds.get("ps1", 0) > 10 and kinds.get("iss", 0) >= 1)
    if not quiet:
        row("U0 the texts were read (not a run on nothing): %s" % ", ".join("%d %s" % (v, k) for k, v in sorted(kinds.items())), ok0, repr(kinds))
        row("U1 no British spelling in what SD prints: messages, help, program texts, C strings, the guide's prose, the installer scripts' texts", not found,
            "; ".join("%s:%s %s (%s)" % f for f in found[:12]) + (" ... and %d more" % (len(found) - 12) if len(found) > 12 else ""))
    return ok0, found


def selftest():
    files = read_tree()
    missed = 0
    cases = [
        ("a message says catalogue", ("messages/99999", ("text", "%1 added to the catalogue")), True),
        ("a program text says colour", ("gpl.bp/zzz", ("basic", "   msg = 'no colour here'\n")), True),
        ("a C string says Unrecognised", ("gplsrc/zz.c", ("c", 'printf("Unrecognised thing");')), True),
        ("a word that ends a sentence (catalogue.)", ("messages/99998", ("text", "Program is in the catalogue.")), True),
        ("CONTROL: a comment line of a program", ("gpl.bp/zzy", ("basic", "* the catalogue of colours\n")), False),
        ("CONTROL: a name with a dot (analyse.index, catalogue.local)", ("messages/99997", ("text", "see analyse.index and option catalogue.local")), False),
        ("CONTROL: a keyword in capitals", ("messages/99996", ("text", "CATALOGUE is not a verb")), False),
        ("CONTROL: a key table row's action id", ("gpl.bp/zzx", ("basic", "   call $tk_keys('add', keys, 'a', 'analyze', 'analyse', '', 1)\n")), False),
        ("CONTROL: the terminfo capability colourmap", ("gplsrc/zy.c", ("c", 'x = sdtgetstr("colourmap");')), False),
        ("an installer script says catalogue in a PowerShell string", ("gplbld/zz1.ps1", ("ps1", "Ok 'the program catalogue is present'\n")), True),
        ("an installer script says colour in a double quoted string", ("gplbld/zz2.ps1", ("ps1", 'Write-Host "the colour of $x"\n')), True),
        ("an Inno Setup [Code] string says licence", ("gplbld/zz3.iss", ("iss", "  Result := 'Accept the licence?';\n")), True),
        ("an Inno Setup [Tasks] description says catalogue", ("gplbld/zz4.iss", ("iss", 'Name: "x"; Description: "Load the catalogue"\n')), True),
        ("CONTROL: a PowerShell comment line", ("gplbld/zz5.ps1", ("ps1", "# the catalogue of colours\n$x = 1\n")), False),
        ("CONTROL: an Inno Setup brace comment", ("gplbld/zz6.iss", ("iss", "  { the catalogue is not printed }\n  x := 1;\n")), False),
        ("CONTROL: a file name in a string (licence\\ is a name)", ("gplbld/zz7.ps1", ("ps1", "$p = 'C:\\\\SD\\\\licence\\\\gpl.txt'\n")), False),
    ]
    for name, (label, fk), want in cases:
        f = dict(files)
        f[label] = fk
        _ok, found = judge(f, quiet=True)
        got = any(h[0] == label for h in found)
        ok = (got == want)
        print("  [%s] selftest: %s %s" % ("pass" if ok else "MISS", name, "is caught" if want else "is not taken for a fault"))
        missed += 0 if ok else 1
    print("selftest: %d cases, %d missed" % (len(cases), missed))
    return 1 if missed else 0


def main():
    print("test-usspelling-units: what SD prints, under %s" % SD64)
    if "--selftest" in sys.argv:
        return selftest()
    judge(read_tree())
    print("test-usspelling-units: %d passed, %d failed" % (passed, failed))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
