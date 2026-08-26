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
    #
    # 26 Aug 26 - THIS CASE WAS PASSING WITHOUT MEASURING WHAT IT NAMES, and
    # that is why the leak it was written for survived it.  It asserted rc=0
    # and a PHASE 2 string; the leak is a PHASE 1 flag, and phase 1 does not
    # touch the exit code.  So the bait could leak back, get flagged, and this
    # still reported PASS - which it did, right up until the last section 7
    # entry was edited and the checker cried wolf again in front of a reader.
    #
    # ANCHOR ON THE PHASE 1 COUNT INSTEAD.  "0 entr(ies)" is printed only when
    # nothing was flagged, so the bait leaking back moves it to "1 entr(ies)"
    # and this fails.  Verified by reverting the clamp in check-stale-leads.py
    # and watching this case go red on its own.
    t = base.replace("## 8. Open questions",
                     "## 8. Open questions\n\nCLOSED DONE VERIFIED - bait.\n", 1)
    assert t != base, "could not find section 8's heading"
    case("closure text after section 8 must not leak back", t, tmp, 0,
         "0 entr(ies) LEAD WITH AN OPEN CLAIM")

    # Section 7's heading renamed must REFUSE rather than scan everything.
    t = base.replace("## 7. Next steps", "## 7. Things to do", 1)
    assert t != base, "could not rename section 7"
    case("section 7 heading renamed - must refuse", t, tmp, 2,
         "could not bound section 7")

    # =====================================================================
    # PHASE 3 - the fault it was built for, and the three ways it must NOT
    # fire.  Phase 3 never touches the exit code, so every case here asserts
    # rc=0 and reads the COUNT LINE.  Asserting rc alone would be the fault
    # the section 8 case above was just repaired for.
    # =====================================================================
    # 26 Aug 26 - RE-ANCHORED WHEN PROJECT_STATUS WAS PRUNED FOR THE
    # DOCUMENTATION PHASE.  The old anchor was item 5's line "WHAT IS GENUINELY
    # UNMEASURED, AND IT IS COSMETIC", which H.5 closing WITHDREW - the pages
    # were looked at and written down.  Restoring it to keep this control
    # running would have put a withdrawn claim back in the handoff document,
    # which is the exact fault the checker exists to find.
    #
    # SO THE ANCHOR MOVED AND THE FIXTURE DID NOT CHANGE SHAPE.  It still needs
    # a line INSIDE item 5 that sits AFTER an OBSERVE_PAT line, so substituting
    # a denial into it makes the pair phase 3 must catch.  Item 5 still records
    # "The owner cycled choosing stand-alone" above it, which is what case [e]
    # strips to prove the null-case guard.
    ANCHOR = "> ***WHAT THE PAGES SHOWED IS WRITTEN DOWN, WHICH IS THE STEP THAT WAS MISSED"
    assert ANCHOR in base, "item 5's corrected wording is not where expected"

    # [a] THE REAL ONE, restored verbatim.  This is the sentence item 5
    # carried on 26 Aug 2026, sixty-nine lines below its own record of the
    # owner cycling and CHOOSING stand-alone.  If this does not flag, the
    # phase is decoration.
    t = base.replace(ANCHOR, "> ***UNSEEN: nobody has looked at this page.***", 1)
    assert t != base, "could not restore the UNSEEN claim"
    case("phase 3: the restored UNSEEN claim must be CAUGHT", t, tmp, 0,
         "1 entr(ies) RECORD AN OBSERVATION AND LATER DENY ONE")

    # [b] The banner alone, with no sentence after it - the case DENY_BANNER
    # exists for, since "nobody has looked" would not be there to match.
    t = base.replace(ANCHOR, "> ***UNSEEN:*** and nothing else on the line.", 1)
    case("phase 3: the bare UNSEEN: banner must be CAUGHT", t, tmp, 0,
         "1 entr(ies) RECORD AN OBSERVATION AND LATER DENY ONE")

    # [c] QUOTING a denial is not making one.  This is how the corrected entry
    # actually reads, and an earlier cut of the phase reported it as the very
    # claim it was withdrawing.
    t = base.replace(ANCHOR,
                     '> It used to read *"UNSEEN: nobody has looked at this\n'
                     '> page"*, and that was wrong.', 1)
    case("phase 3: a QUOTED denial must not fire", t, tmp, 0,
         "0 entr(ies) RECORD AN OBSERVATION AND LATER DENY ONE")

    # [d] Past-tense prose is narration, not a live denial.  Both false hits
    # left on the repaired file were this shape.
    t = base.replace(ANCHOR,
                     "> The defect sat unseen for eight days, and is now fixed.", 1)
    case("phase 3: past-tense 'sat unseen' must not fire", t, tmp, 0,
         "0 entr(ies) RECORD AN OBSERVATION AND LATER DENY ONE")

    # [e] THE NULL-CASE GUARD ITSELF.  Strip every observation phrase and the
    # phase can no longer pair anything - it must SAY it measured nothing
    # rather than reporting a clean zero.
    t = base.replace("The owner cycled choosing stand-alone", "It happened", 1)
    t = t.replace(ANCHOR, "> ***UNSEEN: nobody has looked at this page.***", 1)
    case("phase 3: denial with no observation must not fire", t, tmp, 0,
         "0 entr(ies) RECORD AN OBSERVATION AND LATER DENY ONE")

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
