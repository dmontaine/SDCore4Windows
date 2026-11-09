#!/usr/bin/env python3
#
# test-identtwins-units.py - no script of gplbld uses a British word and its US twin as the SAME KIND OF NAME (RELEASE_1.1 205).  No install.
#
#   python test-identtwins-units.py [--selftest]
#
# START-HISTORY:
# 9 Nov 26 New.  The US spelling sweep of 9 Nov renamed `catalogued = []` to `cataloged` in verify-carry-try.py but left `catalogued.append(nm)`
#                (the word sat next to a dot, which test-usspelling-units.py treats as a name).  py_compile cannot see it: the suite ran its 21
#                rows and then died on a NameError, on the owner's machine.  This guard looks for the shape of the fault, in every gplbld script.
# END-HISTORY
#
# THE RULE.  In one file, `catalogued` and `cataloged` must not BOTH be a name: a Python NAME token (code, not a string or a comment), or a
# PowerShell $variable (not on a comment line; case does not matter there).  One spelling, used everywhere, is fine whichever it is; two
# spellings of one word in one file are a rename done in some places and not others, and they are never right.
# It does not say a name is spelled the American way: a script may keep a British name on purpose (a verb name, a file name, a variable of an
# old script).  It says the file agrees with itself.
#
# THE LIST of word pairs is test-usspelling-units.py's own (its UK list), each with the form the sweep used.

import io
import os
import re
import sys
import tokenize
import importlib.util

HERE = os.path.dirname(os.path.abspath(__file__))

US = {
    "catalogues": "catalogs", "catalogued": "cataloged", "cataloguing": "cataloging", "catalogue": "catalog",
    "colours": "colors", "coloured": "colored", "colouring": "coloring", "colour": "color",
    "analysed": "analyzed", "analysing": "analyzing", "analyse": "analyze",
    "behaviours": "behaviors", "behaviour": "behavior",
    "centres": "centers", "centred": "centered", "centring": "centering", "centre": "center",
    "licences": "licenses", "licence": "license",
    "unrecognised": "unrecognized", "unrecognisable": "unrecognizable",
    "recognises": "recognizes", "recognised": "recognized", "recognising": "recognizing", "recognise": "recognize",
    "initialisation": "initialization", "initialises": "initializes", "initialised": "initialized",
    "initialising": "initializing", "initialise": "initialize",
    "cancelled": "canceled", "cancelling": "canceling",
    "honours": "honors", "honoured": "honored", "honouring": "honoring", "honour": "honor",
    "labelled": "labeled", "labelling": "labeling", "modelled": "modeled", "travelling": "traveling",
    "dialogues": "dialogs", "dialogue": "dialog",
    "synchronises": "synchronizes", "synchronised": "synchronized", "synchronise": "synchronize",
    "authorised": "authorized", "authorises": "authorizes", "authorise": "authorize",
    "minimised": "minimized", "minimise": "minimize",
    "normalised": "normalized", "normalises": "normalizes", "normalise": "normalize",
    "customised": "customized", "customise": "customize", "utilised": "utilized", "utilise": "utilize",
    "optimised": "optimized", "optimise": "optimize",
    "favourite": "favorite", "favour": "favor", "neighbours": "neighbors", "neighbour": "neighbor",
    "greyed": "grayed", "grey": "gray",
}

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


def py_names(text):
    out = set()
    try:
        for tok in tokenize.generate_tokens(io.StringIO(text).readline):
            if tok.type == tokenize.NAME:
                out.add(tok.string)
    except (tokenize.TokenError, IndentationError, SyntaxError):
        pass
    return out


def ps_vars(text):
    out = set()
    for line in text.split("\n"):
        if line.lstrip().startswith("#"):
            continue
        for m in re.finditer(r"\$([A-Za-z_][A-Za-z0-9_]*)", line):
            out.add(m.group(1).lower())
    return out


def twins(label, text):
    """The (british, american) pairs that are both names in this file."""
    names = py_names(text) if label.endswith(".py") else ps_vars(text)
    return [(uk, us) for uk, us in US.items() if uk in names and us in names]


def read_tree():
    files = {}
    for nm in sorted(os.listdir(HERE)):
        if re.search(r"\.(py|ps1)$", nm) and os.path.isfile(os.path.join(HERE, nm)):
            with open(os.path.join(HERE, nm), "rb") as f:
                files[nm] = f.read().decode("latin-1")
    return files


def judge(files, quiet=False):
    bad = [(nm, uk, us) for nm, t in files.items() for uk, us in twins(nm, t)]
    if not quiet:
        row("T0 the scripts were read (not a run on nothing): %d" % len(files), len(files) > 100, repr(len(files)))
        # The word list must be the check's own: every word of test-usspelling-units.py has a twin here.
        spec = importlib.util.spec_from_file_location("usp", os.path.join(HERE, "test-usspelling-units.py"))
        have = os.path.isfile(os.path.join(HERE, "test-usspelling-units.py"))
        missing = []
        if have:
            usp = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(usp)
            missing = [w for w in usp.UK if w not in US]
        row("T1 every word of test-usspelling-units.py has a twin in this guard", have and not missing, ", ".join(missing) or "test-usspelling-units.py is missing")
        row("T2 no script has a word and its twin as the same kind of name", not bad,
            "; ".join("%s: %s and %s" % b for b in bad[:8]) + (" ... and %d more" % (len(bad) - 8) if len(bad) > 8 else ""))
    return bad


def selftest():
    files = read_tree()
    cases = [
        ("a python file with 'catalogued = []' and 'cataloged.append(x)'",
         ("zz1.py", "catalogued = []\ncataloged.append(1)\n"), True),
        ("a python file that uses the old name everywhere (the 9 Nov bug, mirrored)",
         ("zz2.py", "catalogued = []\ncatalogued.append(1)\n"), False),
        ("a powershell file with $catalogued and $Cataloged",
         ("zz3.ps1", "$catalogued = @()\n$Cataloged += 1\n"), True),
        ("CONTROL: a python file with the word in a string and a comment only",
         ("zz4.py", "x = 'catalogued'  # cataloged\nprint(x)\n"), False),
        ("CONTROL: a powershell file with the word in a comment line only",
         ("zz5.ps1", "# $catalogued is gone\n$cataloged = 1\n"), False),
        ("CONTROL: a python file with the american name only",
         ("zz6.py", "cataloged = []\ncataloged.append(1)\n"), False),
    ]
    missed = 0
    for name, (label, text), want in cases:
        f = dict(files)
        f[label] = text
        got = any(b[0] == label for b in judge(f, quiet=True))
        ok = (got == want)
        print("  [%s] selftest: %s %s" % ("pass" if ok else "MISS", name, "is caught" if want else "is not taken for a fault"))
        missed += 0 if ok else 1
    print("selftest: %d cases, %d missed" % (len(cases), missed))
    return 1 if missed else 0


def main():
    print("test-identtwins-units: the scripts under %s" % HERE)
    if "--selftest" in sys.argv:
        return selftest()
    judge(read_tree())
    print("test-identtwins-units: %d passed, %d failed" % (passed, failed))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
