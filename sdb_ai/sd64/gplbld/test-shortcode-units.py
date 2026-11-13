#!/usr/bin/env python3
"""test-shortcode-units.py - bind_sysseg() gives the SHORT_CODE semaphore back on every exit (gplsrc/sysseg.c; RELEASE_1.1 276).

  python sdb_ai/sd64/gplbld/test-shortcode-units.py
  python sdb_ai/sd64/gplbld/test-shortcode-units.py --selftest

WHY.  On 13 Nov 2026 one sd.exe that could not see SD's segment ("SD has not been started.") left SHORT_CODE taken, and every
later session spun in LockSemaphore: a Windows semaphore is not given back when its holder ends (Linux's System V one is,
SEM_UNDO).  bind_sysseg() now keeps a flag, short_code_held, and exit_bind_sysseg gives the semaphore back when it is set.

WHAT IT READS (comments removed, so a rule kept only in a comment does not count):
  S1  short_code_held starts FALSE and is set TRUE on the line after LockSemaphore(SHORT_CODE)
  S2  every UnlockSemaphore(SHORT_CODE) in bind_sysseg is followed by short_code_held = FALSE (no double release)
  S3  exit_bind_sysseg gives SHORT_CODE back when short_code_held, BEFORE stop_sd() (which may close the semaphores)
  S4  no plain `return` lies between the lock and the last unlock except after an unlock (it would skip S3)
  S5  CONTROL: the "SD has not been started." exit goes to exit_bind_sysseg, so S3 covers it
It does not run SD: the semaphore's behaviour was measured on the live host (count 0 of 1, released once, session ended).
Exit 0 every check held, 1 one failed, 2 the function was not found.  --selftest applies mutants (each must match once).
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(os.path.dirname(HERE), "gplsrc", "sysseg.c")


def strip_c(s):
    s = re.sub(r"/\*.*?\*/", lambda m: "\n" * m.group(0).count("\n"), s, flags=re.S)
    return re.sub(r"//[^\n]*", "", s)


def body(text):
    i = text.find("bool bind_sysseg(")
    if i < 0:
        return None
    j = text.find("\n}\n", i)
    return text[i:j] if j > 0 else None


def checks(text):
    b = body(strip_c(text))
    if b is None:
        return None
    out = []
    lines = [l.strip() for l in b.split("\n")]
    out.append(("S1 short_code_held starts FALSE and is set TRUE right after LockSemaphore(SHORT_CODE)",
                "bool short_code_held = FALSE;" in b and
                re.search(r"LockSemaphore\(SHORT_CODE\);\s*short_code_held = TRUE;", b) is not None))
    unl = [(m.start(), m.end()) for m in re.finditer(r"UnlockSemaphore\(SHORT_CODE\);", b)]
    plain = [s for s, e in unl if not b[e:e + 80].lstrip().startswith("short_code_held = FALSE;")
             and not b[max(0, s - 60):s].rstrip().endswith("if (short_code_held)")]
    out.append(("S2 every UnlockSemaphore(SHORT_CODE) outside the exit is followed by short_code_held = FALSE (%d unlocks)" % len(unl),
                len(unl) >= 3 and not plain))
    ex = b[b.find("exit_bind_sysseg:"):] if "exit_bind_sysseg:" in b else ""
    out.append(("S3 exit_bind_sysseg gives SHORT_CODE back when held, before stop_sd()",
                re.search(r"if \(short_code_held\)\s*UnlockSemaphore\(SHORT_CODE\);", ex) is not None
                and 0 <= ex.find("short_code_held") < ex.find("stop_sd()")))
    lock = b.find("LockSemaphore(SHORT_CODE);")
    last = b.rfind("short_code_held = FALSE;")
    span = b[lock:last]
    first_unlock = span.find("UnlockSemaphore(SHORT_CODE);")
    bad_ret = [m.start() for m in re.finditer(r"\breturn\b", span) if m.start() < first_unlock or
               ("else" not in span[first_unlock:m.start()] and span.find("if (!create)", first_unlock) < m.start())]
    out.append(("S4 no return between the lock and the last unlock while the semaphore is held", lock >= 0 and not bad_ret))
    m = re.search(r'strcpy\(errmsg, "SD has not been started\."\);\s*goto exit_bind_sysseg;', b)
    out.append(("S5 CONTROL: the 'SD has not been started.' exit goes to exit_bind_sysseg", m is not None))
    return out


MUTANTS = [
    ("the exit no longer gives the semaphore back", "  if (short_code_held)\n    UnlockSemaphore(SHORT_CODE);\n\n  if (!status)", "  if (!status)"),
    ("the flag is not set after the lock", "  LockSemaphore(SHORT_CODE);\n  short_code_held = TRUE;", "  LockSemaphore(SHORT_CODE);"),
    ("the attach path's unlock does not clear the flag (a double release)",
     "    UnlockSemaphore(SHORT_CODE);\n    short_code_held = FALSE;", "    UnlockSemaphore(SHORT_CODE);"),
    ("the not-started exit returns directly", 'strcpy(errmsg, "SD has not been started.");\n    goto exit_bind_sysseg;',
     'strcpy(errmsg, "SD has not been started.");\n    return FALSE;'),
]


def run(text, quiet=False):
    res = checks(text)
    if res is None:
        return None
    bad = 0
    for name, ok in res:
        bad += 0 if ok else 1
        if not quiet:
            print("  [%s] %s" % ("PASS" if ok else "FAIL", name))
    return bad


def main():
    print("test-shortcode-units: source %s" % SRC)
    text = open(SRC, encoding="latin-1", newline="").read()
    bad = run(text)
    if bad is None:
        print("NO TREE: bind_sysseg() not found")
        return 2
    print("%d checks failed" % bad)
    if bad:
        return 1
    if "--selftest" in sys.argv[1:]:
        holes = 0
        for name, old, new in MUTANTS:
            n = text.count(old)
            if n != 1:
                print("  [FAIL] %s: the text to mutate matches %d times" % (name, n))
                holes += 1
                continue
            r = run(text.replace(old, new, 1), quiet=True)
            caught = r is None or r > 0
            print("  [%s] %s%s" % ("pass" if caught else "FAIL", name, "" if caught else ": NOT CAUGHT"))
            holes += 0 if caught else 1
        print("self-test: %d mutants, %d not caught" % (len(MUTANTS), holes))
        return 1 if holes else 0
    return 0


if __name__ == "__main__":
    sys.exit(main())
