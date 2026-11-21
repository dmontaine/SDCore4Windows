#!/usr/bin/env python3
"""test-pwflush-units.py - RELEASE_1.1 372: no PowerShell script of gplbld reads a password (Read-Host ... -AsSecureString) without first
throwing away the keys typed ahead.

WHY (VM sit12, 21 Nov 2026).  A password prompt showed about 15 stars already in it: the keys typed before the prompt appeared were taken as the
start of the password.  The owner: "the system needs to be checked for other instances so that the buffer is never pasted into a password prompt".
SD's own prompts (INPUT ... HIDDEN, 48 statements) all go through gpl.bp/_input and are fixed there (Linux S.297, carried when it lands).  The
PowerShell prompts are Windows-only: each calls $Host.UI.RawUI.FlushInputBuffer() inside try/catch (a host that has no console refuses it) in
the three lines before the read.

THE RULE: every code line (comments dropped) that has Read-Host and -AsSecureString has FlushInputBuffer on one of the 3 code lines before it, or
on the same line.  THE NULL CASE IS REFUSED: a directory with no such read is exit 2, not a pass.  --selftest removes each flush in memory, one
read at a time, and each removal must turn the guard red (the live files are not written; their SHA-256 is printed before and after).

  python gplbld/test-pwflush-units.py            exit 0 all reads flushed, 1 a read is not, 2 it could not run (no reads found)
  python gplbld/test-pwflush-units.py --selftest
"""
import glob
import hashlib
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
READ = re.compile(r"Read-Host\b.*-AsSecureString|-AsSecureString\b.*Read-Host\b|Read-Host\s+-AsSecureString", re.I)
FLUSH = re.compile(r"FlushInputBuffer\s*\(")


def code_lines(text):
    """(number, line) for every line that is not a whole-line comment; a trailing '# ...' is cut."""
    out = []
    # a <# ... #> block comment is dropped, its newlines kept so the line numbers still match the file
    text = re.sub(r"<#.*?#>", lambda m: "\n" * m.group(0).count("\n"), text.replace("\r\n", "\n"), flags=re.S)
    for i, ln in enumerate(text.split("\n"), 1):
        if ln.strip().startswith("#"):
            continue
        out.append((i, re.sub(r"\s#\s.*$", "", ln)))
    return out


def reads(text):
    """[(line number, flushed?)] for every password read in the text."""
    code = code_lines(text)
    found = []
    for k, (n, ln) in enumerate(code):
        if READ.search(ln):
            window = [l for _, l in code[max(0, k - 3):k + 1]]
            found.append((n, any(FLUSH.search(w) for w in window)))
    return found


def scripts():
    return sorted(glob.glob(os.path.join(HERE, "*.ps1")))


def read(p):
    with open(p, "rb") as f:
        return f.read().decode("utf-8", errors="replace")


def sha(p):
    return hashlib.sha256(open(p, "rb").read()).hexdigest()[:12]


def check():
    total, bad = 0, []
    for p in scripts():
        for n, ok in reads(read(p)):
            total += 1
            if not ok:
                bad.append("%s:%d" % (os.path.basename(p), n))
    return total, bad


def main():
    total, bad = check()
    print("test-pwflush-units: %s" % HERE)
    print("  password reads found: %d" % total)
    if total == 0:
        print("  NO READS: nothing to check - refused, not passed")
        return 2
    for b in bad:
        print("  [FAIL] no FlushInputBuffer before the read at " + b)
    if not bad:
        print("  [PASS] every Read-Host -AsSecureString has a FlushInputBuffer before it (%d reads)" % total)
    print("test-pwflush-units: %d reads, %d not flushed" % (total, len(bad)))
    return 1 if bad else 0


def selftest():
    files = scripts()
    before = {p: sha(p) for p in files}
    print("live files, SHA-256 before: %d scripts, first %s" % (len(files), before[files[0]] if files else "-"))
    total, bad = check()
    ok = total > 0 and not bad
    print("  [%s] control: the unbroken text passes (%d reads, %d unflushed)" % ("PASS" if ok else "FAIL", total, len(bad)))
    caught = missed = 0
    for p in files:
        text = read(p)
        rs = reads(text)
        for idx, (n, _) in enumerate(rs):
            lines = text.replace("\r\n", "\n").split("\n")
            # remove every flush within the 3 code lines before the idx-th read (and on its own line), keeping the line count
            for j in range(max(0, n - 7), n):
                lines[j] = FLUSH.sub("Noop(", lines[j])
            broken = "\n".join(lines)
            after = reads(broken)
            red = any(not ok for m, ok in after if m == n)
            tag = "%s:%d" % (os.path.basename(p), n)
            if red:
                caught += 1
                print("  [pass] flush removed before %s: caught" % tag)
            else:
                missed += 1
                print("  [FAIL] flush removed before %s: NOT caught" % tag)
    after_sha = {p: sha(p) for p in files}
    same = before == after_sha
    print("live files unchanged: %s" % same)
    print("%d of %d mutants caught, %d missed" % (caught, caught + missed, missed))
    return 0 if (ok and missed == 0 and caught > 0 and same) else 1


if __name__ == "__main__":
    sys.exit(selftest() if "--selftest" in sys.argv[1:] else main())
