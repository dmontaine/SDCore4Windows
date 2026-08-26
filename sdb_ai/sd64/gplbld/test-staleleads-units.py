"""Control test for check-stale-leads.py - does it FAIL when it should?

WHY THIS EXISTS.  check-stale-leads.py exits 0 on the real PROJECT_STATUS.md.
On its own that is indistinguishable from a script that has silently stopped
working: both print a clean run.  This project's instrument rule says a test
that passes because it did nothing must fail, so the only way to trust a clean
run is to have watched the same code report a corrupted one.

It copies PROJECT_STATUS.md to %TEMP%, injects one defect at a time, and
requires a non-zero exit and the expected message.  It touches nothing in the
repository and needs no elevation, no install and no cycle.
"""

import io
import os
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
CHECKER = os.path.join(HERE, "check-stale-leads.py")
DOC = os.path.normpath(os.path.join(HERE, os.pardir, os.pardir, os.pardir,
                                    "PROJECT_STATUS.md"))

TICK = "✅"      # closed
OPEN_M = "⬜"    # open
PART = "◐"      # partly


def run(path):
    env = dict(os.environ)
    env["PYTHONIOENCODING"] = "utf-8"
    p = subprocess.run([sys.executable, CHECKER, path], env=env,
                       capture_output=True, text=True, encoding="utf-8")
    return p.returncode, (p.stdout or "") + (p.stderr or "")


def load():
    with io.open(DOC, encoding="utf-8", newline="") as fh:
        return fh.read()


def write(tmp, text, name):
    p = os.path.join(tmp, name)
    with io.open(p, "w", encoding="utf-8", newline="") as fh:
        fh.write(text)
    return p


results = []


def case(name, text, tmp, want_rc, want_sub):
    p = write(tmp, text, re.sub(r"\W+", "_", name) + ".md")
    rc, out = run(p)
    ok = (rc == want_rc) and (want_sub in out)
    results.append((ok, name, rc, want_rc, want_sub))
    print("  [%s] %-46s rc=%d (want %d)" % ("PASS" if ok else "FAIL",
                                            name, rc, want_rc))
    if not ok:
        print("       looked for: %r" % want_sub)
        for ln in out.splitlines():
            if "DRIFT" in ln or "REFUS" in ln or "disagree" in ln:
                print("       saw: " + ln.strip())
    return ok


def main():
    base = load()
    tmp = tempfile.mkdtemp(prefix="staleleads-")
    print("checker : %s" % CHECKER)
    print("source  : %s  (%d bytes)" % (DOC, len(base)))
    print("scratch : %s" % tmp)
    print("")

    # THE POSITIVE CONTROL FIRST.  If the unmodified file does not pass, every
    # failure below is meaningless - it would just be a broken script.
    print("=== [0] the control: the real file must PASS ===")
    case("unmodified PROJECT_STATUS.md", base, tmp, 0,
         "every row agrees with its entry")

    print("")
    print("=== [1] injected drift must be CAUGHT ===")

    # A finished item never ticked off - the step 14 fault, mechanised.
    t = base.replace("| " + TICK + " | **7.14** |",
                     "| " + OPEN_M + " | **7.14** |", 1)
    assert t != base, "could not find row 7.14 to flip"
    case("done item marked open (the step 14 fault)", t, tmp, 1,
         "FINISHED WORK NEVER TICKED OFF")

    # A row whose ID does not exist.
    t = base.replace("| **7.16** |", "| **7.99** |", 1)
    assert t != base, "could not find row 7.16"
    case("row for an ID with no entry", t, tmp, 1, "has NO ENTRY")

    # An entry with no row - drop a row entirely.
    t = re.sub(r"^\| . \| \*\*7\.17\*\* \|.*\n", "", base, count=1,
               flags=re.M)
    assert t != base, "could not delete row 7.17"
    case("entry with no row in the table", t, tmp, 1, "has NO ROW")

    # PARTLY claims both; an entry with no open claim must be ticked instead.
    t = base.replace("| " + TICK + " | **7.15** |",
                     "| " + PART + " | **7.15** |", 1)
    assert t != base, "could not find row 7.15"
    case("partly-marked item with nothing open", t, tmp, 1,
         "contains nothing still open")

    # The table removed altogether must REFUSE, not report a clean run.
    t = re.sub(r"^\| . \| \*\*[0-9H]\.[0-9a-z]+\*\* \|.*\n", "", base,
               flags=re.M)
    assert t != base, "could not strip the table"
    case("table deleted - must refuse, not pass", t, tmp, 2,
         "no task table rows parsed")

    # REGRESSION, 26 Aug 2026: the LAST step in section 7 has no next entry
    # inside it, so its range ran to the next START HERE item and swallowed
    # section 8's preamble - which contains "Closed and superseded material is
    # in HISTORY".  Step 18 was reported as leading with a closure it does not
    # contain.  Planting a closure word immediately after section 8's heading
    # must NOT flag the last step.
    t = base.replace("## 8. Open questions",
                     "## 8. Open questions\n\nCLOSED DONE VERIFIED - bait.\n", 1)
    assert t != base, "could not find section 8's heading"
    case("closure text after section 8 must not leak back", t, tmp, 0,
         "every row agrees with its entry")

    # Section 7's heading renamed must REFUSE rather than scan everything.
    t = base.replace("## 7. Next steps", "## 7. Things to do", 1)
    assert t != base, "could not rename section 7"
    case("section 7 heading renamed - must refuse", t, tmp, 2,
         "could not bound section 7")

    shutil.rmtree(tmp, ignore_errors=True)

    print("")
    print("=" * 62)
    passed = sum(1 for r in results if r[0])
    print("%d of %d checks passed." % (passed, len(results)))
    if passed != len(results):
        print("test-staleleads-units: FAILED")
        return 1
    print("test-staleleads-units: PASSED - the checker fails when it should,")
    print("  and passes on the real file.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
