#!/usr/bin/env python3
"""test-sortparse-units.py - the key being inserted into a sort is read as a number ONCE per level, not at every comparison.

  python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/test-sortparse-units.py
  python3 .../test-sortparse-units.py --selftest

No sudo, no install, no sd.  Exit 0 all checks passed, 1 a check failed, 2 it could not run.

WHAT THIS IS AND IS NOT.  It reads gplsrc/op_sort.c as TEXT, comments removed, and says that the shape which keeps the internal sort
as fast as it was is still written: sess_insert_bte() reads the new key with key_as_number() behind a once-per-level bit test, before
the compare, and hands the answer to sort_compare_keys() as k1num, which the right justified modes use instead of reading k1 again.
It cannot say the sort is fast.  That is a timing, and a timing is flaky here: the audit of 16 Oct 26 measured 120,000 numeric keys
(HEAD ac509e4 against the working tree, the same BASIC program in two sandboxes, median of 5): 210 ms before, 263 ms with the new key
read afresh at every comparison, 211 ms with this shape.  --selftest breaks each fact in turn and requires the check to say so.
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, os.pardir, "gplsrc", "op_sort.c")


def strip_comments(s):
    return re.sub(r"/\*.*?\*/", "", s, flags=re.S)


def function_body(src, header):
    """The text of the DEFINITION that starts with `header` (not its prototype): to the closing brace at column 0."""
    i = src.find(header)
    while i >= 0:
        brace, semi = src.find("{", i), src.find(";", i)
        if 0 <= brace and (semi < 0 or brace < semi):
            j = src.find("\n}\n", i)
            return src[i:j + 3] if j > 0 else src[i:]
        i = src.find(header, i + 1)
    return ""


def checks(text):
    src = strip_comments(text)
    res = []

    def ck(name, ok, detail=""):
        res.append((name, bool(ok), detail))

    ins = function_body(src, "Private bool tree_insert(")   # 20 Oct 26: the classic walk moved out of sess_insert_bte() into tree_insert()
    cmp_ = function_body(src, "Private int sort_compare_keys(")
    ck("S0 both functions are there", bool(ins) and bool(cmp_), "insert %d bytes, compare %d bytes" % (len(ins), len(cmp_)))
    guard = ins.find("if (!(num_done &")
    parse = ins.find("key_as_number(new_bte->key[index]")
    call = ins.find("sort_compare_keys(new_bte->key[index]")
    ck("S1 sess_insert_bte reads the new key behind a once-per-level bit test", 0 <= guard < parse, "guard at %d, parse at %d" % (guard, parse))
    ck("S2 ... and before it compares", 0 <= parse < call, "parse at %d, compare at %d" % (parse, call))
    ck("S3 ... and hands the compare the answer, not NULL", re.search(r"sort_compare_keys\(new_bte->key\[index\][^;]*&\(new_num\[index\]\)\)", ins) is not None)
    ck("S4 the compare uses that answer for the right justified modes", "k1num != NULL" in cmp_ and "num1 = k1num->is_num" in cmp_)
    ck("S5 the compare reads k1 itself only when it is given no answer", "num1 = key_as_number(k1, mode" in cmp_)
    return res


def selftest(text):
    base = checks(text)
    bad = [n for n, ok, _ in base if not ok]
    if bad:
        print("selftest: the real file already fails: %s" % bad)
        return False
    mutants = [
        ("insert passes NULL", text.replace("sess->sort_flags[index], sess->legacy_bt, &(new_num[index]));",
                                            "sess->sort_flags[index], sess->legacy_bt, NULL);"), "S3"),
        ("no bit test: the key is read at every comparison", text.replace("if (!(num_done & ((u_int32_t)1 << index))) {", "if (1) {"), "S1"),
        ("the key is read after the compare", text.replace("key_as_number(new_bte->key[index], sess->sort_flags[index] & SRT_MODE_MASK,",
                                                          "key_as_number(bte->key[index], sess->sort_flags[index] & SRT_MODE_MASK,"), "S1"),
        ("the compare ignores the answer", text.replace("if (k1num != NULL) {", "if (0) {"), "S4"),
        ("the compare never reads k1 itself", text.replace("num1 = key_as_number(k1, mode, legacy_bt, &v1);", "num1 = 0;"), "S5"),
    ]
    ok = True
    for name, mutated, want in mutants:
        if mutated == text:
            print("  [FAIL] selftest: %s (the mutation changed nothing)" % name)
            ok = False
            continue
        failed = [n.split()[0] for n, passed, _ in checks(mutated) if not passed]
        caught = want in failed
        print("  [%s] selftest: %s%s" % ("PASS" if caught else "FAIL", name, "" if caught else " (NOT CAUGHT; failed: %s)" % failed))
        ok = ok and caught
    return ok


def main():
    if not os.path.isfile(SRC):
        print("test-sortparse-units: CANNOT RUN - %s missing" % SRC)
        return 2
    with open(SRC, encoding="latin-1") as f:
        text = f.read()
    if "--selftest" in sys.argv:
        return 0 if selftest(text) else 1
    res = checks(text)
    failed = 0
    for name, ok, detail in res:
        print("  [%s] %s%s" % ("PASS" if ok else "FAIL", name, "" if ok else "   <- " + detail))
        failed += 0 if ok else 1
    print("\ntest-sortparse-units: %d passed, %d failed" % (len(res) - failed, failed))
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
