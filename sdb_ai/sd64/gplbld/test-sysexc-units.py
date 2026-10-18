#!/usr/bin/env python3
#
# test-sysexc-units.py - the SYS.* exceptions (QM4 Fixes 354, 513) read off the sources: the table that gives an error
# message its exception name, and the order of the steps that make a caught error leave the terminal alone.
#
#   python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/test-sysexc-units.py [--selftest]
#
# No sudo, no install, no sd.  Exit 0 every check held, 1 one did not.  --selftest breaks a copy of the sources in ten
# ways and expects each to be caught by exactly the check that owns it.  It cannot say that any error is thrown or caught:
# that is sandbox-sysexc.py.
#
# START-HISTORY:
# 17 Oct 26 dm  Written with the table in k_error.c.  The table is one line per message and nothing else ties it to the
#               message files or to the names the openQM manual lists: a message number typed wrong names another error's
#               exception, a name typed wrong can never be caught by the handler the application wrote, and neither
#               gives any message.
# END-HISTORY
#
# WHAT IT CHECKS
#   1. the table is not empty, ascending, and no message number twice.
#   2. every message in it exists in sdsys/messages and is a fatal one (a text beginning with ! is a warning and never
#      reaches the throw).
#   3. every name is SYS. and components of capitals, digits and underscores, at most 63 characters, and is a leaf or a
#      group of the openQM manual's list of system generated exceptions.
#   4. k_error(): the decision to throw is taken before the terminal is reset, and the throw comes before the message is
#      written or logged; k_descr_error() names its message before it calls k_error().
#   5. kernel.c: k_run_program() keeps a resume point and gives the outer one back on both ways out; an abort forgets it.
#   6. op_jumps.c: an exception rolls back the transactions begun inside the TRY clause; TRY records the depth;
#      handler tests are by group (exc_covers) in both places that compare names; the system throw ends in the resume.
#   7. messages.c: sysmsg() records the number it was asked for, sysmsg_number_of() answers only for its own buffer.
#   8. pdbg: the no-PDEBUG path throws when something can catch it, before it stops.

import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SD64 = os.path.dirname(HERE)
GPLSRC = os.path.join(SD64, "gplsrc")
PATHS = {
    "k_error": os.path.join(GPLSRC, "k_error.c"),
    "kernel": os.path.join(GPLSRC, "kernel.c"),
    "op_jumps": os.path.join(GPLSRC, "op_jumps.c"),
    "messages": os.path.join(GPLSRC, "messages.c"),
    "pdbg": os.path.join(SD64, "sdsys", "gpl.bp", "pdbg"),
}
MSGDIR = os.path.join(SD64, "sdsys", "messages")

# the manual's list ("System Generated Exceptions"), leaves; a group is any proper prefix of a leaf
LEAVES = """
ABORT
EXTCALL.ABORT EXTCALL.INVALID_ARGCT EXTCALL.IO_ERROR EXTCALL.SETUP_ERROR EXTCALL.SIZE_ERROR
FILESYS.CONSTRAINTS FILESYS.CREATION_ERROR FILESYS.INVALID_FILE_TYPE FILESYS.INVALID_PARTNO FILESYS.INVALID_PATHNAME
FILESYS.INVALID_RECORD_ID FILESYS.IO_ERROR FILESYS.LOCK_REQUIRED FILESYS.NOT_DISTRFL FILESYS.OPEN_ERROR
FILESYS.PERMISSIONS.ERROR FILESYS.PERMISSIONS.READ_ONLY FILESYS.TRIGGER.ERROR FILESYS.TRIGGER.INVALID_ARGCT
KERNEL.NO_MEMORY
LOCKS.DEADLOCK LOCKS.LIMIT LOCKS.TASK_LOCK.INVALID
PRINTER.IO_ERROR PRINTER.INVALID_KEY PRINTER.INVALID_OPERATION PRINTER.INVALID_REGION PRINTER.INVALID_UNIT
PROGRAM.DATATYPE.ECS_CHAR PROGRAM.DATATYPE.INVALID PROGRAM.DATATYPE.INVALID_SOCKET PROGRAM.DATATYPE.NOT_COLLECTION
PROGRAM.DATATYPE.NOT_FILE PROGRAM.DATATYPE.NOT_IMAGE PROGRAM.DATATYPE.NOT_MATRIX PROGRAM.DATATYPE.NOT_NUMERIC
PROGRAM.DATATYPE.NOT_OBJECT PROGRAM.DATATYPE.NOT_SEQ_FILE PROGRAM.DATATYPE.NOT_SOCKET PROGRAM.DATATYPE.NOT_SORT
PROGRAM.DATATYPE.NULL_STRING PROGRAM.DATATYPE.UNASSIGNED
PROGRAM.DIV_ZERO PROGRAM.INVALID_ARGCT PROGRAM.INVALID_CALL_NAME PROGRAM.INVALID_DATA_SIZE PROGRAM.INVALID_IN_TXN
PROGRAM.INVALID_ITYPE PROGRAM.INVALID_KEY PROGRAM.INVALID_MATRIX_INDEX PROGRAM.INVALID_MATRIX_SIZE PROGRAM.INVALID_NAME
PROGRAM.INVALID_OBJECT_REFERENCE PROGRAM.IS_CLASS PROGRAM.LIMIT.CALL_DEPTH PROGRAM.LIMIT.NUM_FILES
PROGRAM.LIMIT.GOSUB_DEPTH PROGRAM.LIMIT.MAX_BREAKPOINTS PROGRAM.LOAD_ERROR.READ_ERROR PROGRAM.LOAD_ERROR.VERSION
PROGRAM.NO_PDEBUG PROGRAM.NO_PROPERTY_VALUE PROGRAM.NOT_FOUND PROGRAM.NOT_OBJECT PROGRAM.NOT_TXN PROGRAM.RANGE
PROGRAM.RESIZE_ERROR
SELECT.INVALID_LIST_NO
SHELL.EXECUTION_ERROR
SORT.INVALID_DATA_LENGTH SORT.INVALID_KEY_COUNT SORT.INVALID_KEY_LENGTH SORT.INVALID_OPERATION SORT.IO_ERROR
""".split()


def allowed_names():
    names = set()
    for leaf in LEAVES:
        parts = leaf.split(".")
        for i in range(1, len(parts) + 1):
            names.add("SYS." + ".".join(parts[:i]))
    return names


passed = failed = 0


def row(name, ok, detail=""):
    global passed, failed
    if ok:
        passed += 1
        print("  [PASS] " + name)
    else:
        failed += 1
        print("  [FAIL] " + name + ("   <- " + detail if detail else ""))


def read(path):
    with open(path, encoding="latin-1") as f:
        return f.read()


def func_body(text, header_re):
    """From the line that matches header_re to the next line that is a lone } in column 0; '' if there is none."""
    m = re.search(header_re, text)
    if not m:
        return ""
    end = re.search(r"(?m)^}\s*$", text[m.start():])
    return text[m.start():m.start() + end.end()] if end else text[m.start():]


def parse_table(k_error_text):
    prefixes = dict(re.findall(r'(?m)^#define (SE_[A-Z]+) "([A-Za-z.]+)"', k_error_text))
    m = re.search(r"sys_exc_table\[\] = \{(.*?)\n\};", k_error_text, re.S)
    rows = []
    if m:
        for r in re.finditer(r'\{(\d+),\s*(SE_[A-Z]+)\s+"([A-Z0-9_.]+)"\}', m.group(1)):
            rows.append((int(r.group(1)), prefixes.get(r.group(2), "?" + r.group(2)) + r.group(3)))
    return rows


def checks(src, msg_exists, msg_fatal):
    res = []
    rows = parse_table(src["k_error"])
    nums = [n for n, _ in rows]
    res.append(("1. the table has rows, in ascending order of message number, none twice",
                len(rows) >= 100 and nums == sorted(nums) and len(set(nums)) == len(nums),
                "%d rows; first out of order or repeated: %s" % (len(rows), next((b for a, b in zip(nums, nums[1:]) if a >= b), "-"))))
    missing = [n for n in nums if not msg_exists(n)]
    warn = [n for n in nums if msg_exists(n) and not msg_fatal(n)]
    res.append(("2. every message in the table exists and is fatal (not a '!' warning)", not missing and not warn,
                "no message file: %s; begins with !: %s" % (missing, warn)))
    ok_names = allowed_names()
    bad = [(n, nm) for n, nm in rows if nm not in ok_names or len(nm) > 63 or not re.fullmatch(r"SYS(\.[A-Z0-9_]+)+", nm)]
    res.append(("3. every name is on the manual's list of system exceptions (a leaf or a group), at most 63 characters", not bad, "%s" % bad[:6]))

    ke = src["k_error"]
    kb = func_body(ke, r"(?m)^void k_error\(char\* message, \.\.\.\) \{")
    i_can = kb.find("exc_sys_can_catch(sys_exc)")
    i_rlt = kb.find('sdtgetstr("rlt")')
    i_throw = kb.find("exc_sys_throw(sys_exc, s)")
    i_write = kb.find("tio_write(s);\n  tio_write(\"\\n\");\n\n  log_message(s)")   # the message of an error that goes on (the one before it is the no-object logout)
    i_log = kb.find("log_message(s)")
    res.append(("4a. k_error() decides on the throw before it resets the terminal",
                0 <= i_can < i_rlt, "can_catch at %d, terminal reset at %d" % (i_can, i_rlt)))
    res.append(("4b. ...and throws before it writes or logs the message",
                0 <= i_throw < i_write and i_throw < i_log, "throw at %d, write at %d, log at %d" % (i_throw, i_write, i_log)))
    db = func_body(ke, r"(?m)^\s*void k_descr_error\(int16_t msg_no, DESCRIPTOR\* descr\) \{")
    res.append(("4c. k_descr_error() names its message before it calls k_error()",
                0 <= db.find("descr_msg_no = msg_no") < db.find("k_error(message"), "k_descr_error: %s" % db[:80].replace("\n", " ")))

    kn = src["kernel"]
    rb = func_body(kn, r"(?m)^void k_run_program\(\)")
    res.append(("5a. k_run_program() keeps its resume point after counting the recursion and before the dispatch loop",
                0 <= rb.find("recursion_depth++") < rb.find("resume_env = &resume") < rb.find("setjmp(resume)") < rb.find("dispatch[*(op_pc"),
                "positions in k_run_program: %s" % [rb.find(s) for s in ("recursion_depth++", "resume_env = &resume", "setjmp(resume)", "dispatch[*(op_pc")]))
    res.append(("5b. ...and gives the outer one back at the early return and at exit_run_program",
                rb.count("resume_env = outer_resume;") == 2 and rb.find("resume_env = outer_resume;") < rb.find("return;") < rb.rfind("resume_env = outer_resume;"),
                "%d restores" % rb.count("resume_env = outer_resume;")))
    kb2 = func_body(kn, r"(?m)^void kernel\(\) \{")
    res.append(("5c. an abort (the setjmp(k_exit) block) forgets the resume point",
                "resume_env = NULL;" in kb2[kb2.find("setjmp(k_exit)"):] if "setjmp(k_exit)" in kb2 else False, "kernel(): no setjmp(k_exit) or no resume_env = NULL"))

    oj = src["op_jumps"]
    er = func_body(oj, r"(?m)^Private void exc_raise\(bool rethrow\) \{")
    res.append(("6a. exc_raise() rolls back the transactions begun inside the TRY clause, after the program levels are given up",
                0 <= er.find("k_return();") < er.find("txn_rollback_to(f.txn_depth)"), "exc_raise: %s" % er[:60].replace("\n", " ")))
    res.append(("6b. TRY records the transaction depth in its frame", "f->txn_depth = txn_depth;" in func_body(oj, r"(?m)^void op_try\(\) \{"),
                "op_try has no f->txn_depth = txn_depth;"))
    res.append(("6c. both name comparisons, the table search and the clause match, go through exc_covers()",
                "exc_covers(" in func_body(oj, r"(?m)^Private bool exc_table_find\([^;{]*\{") and "exc_covers(" in func_body(oj, r"(?m)^Private void exc_op_match\(\) \{"),
                "one of exc_table_find, exc_op_match does not call exc_covers"))
    st = func_body(oj, r"(?m)^void exc_sys_throw\(")
    res.append(("6d. exc_sys_throw() asks whether it can be caught first, raises, and ends by going back to the dispatch loop",
                0 <= st.find("exc_sys_can_catch(name)") < st.find("exc_raise(FALSE)") < st.find("k_resume_exception()"), "exc_sys_throw: %s" % st[:60].replace("\n", " ")))

    ms = src["messages"]
    sb = func_body(ms, r"(?m)^char\* sysmsg\(int msg_no\) \{")
    res.append(("7. sysmsg() records its number before it reads anything, and sysmsg_number_of() answers only for the message buffer",
                0 <= sb.find("last_msg_no = msg_no;") < sb.find("msg_file == -1") and "p == message" in func_body(ms, r"(?m)^int sysmsg_number_of\("),
                "sysmsg: %d, %d" % (sb.find("last_msg_no = msg_no;"), sb.find("msg_file == -1"))))

    pd = src["pdbg"]
    cd = pd[pd.find("cannot.debug:"):] if "cannot.debug:" in pd else ""
    res.append(("8. pdbg's cannot.debug throws SYS.PROGRAM.NO_PDEBUG when caught() says something can catch it, before it stops",
                0 <= cd.find("caught('SYS.PROGRAM.NO_PDEBUG'") < cd.find("throw 'SYS.PROGRAM.NO_PDEBUG'") < cd.find("stop sysmsg(6727)"),
                "cannot.debug: %s" % cd[:80].replace("\n", " ")))
    return res


def run(src, label_ok=True):
    def exists(n):
        return os.path.isfile(os.path.join(MSGDIR, str(n)))

    def fatal(n):
        try:
            return not read(os.path.join(MSGDIR, str(n))).startswith("!")
        except OSError:
            return False
    return checks(src, exists, fatal)


def selftest(src):
    ke = src["k_error"]
    ok_all = True
    first_row = re.search(r"(?m)^    \{1002, [^\n]*\n", ke)
    muts = [
        ("a message number twice", "k_error", ke.replace("    {1003, ", "    {1002, ", 1), "1."),
        ("a message that has no file", "k_error", ke.replace("    {1003, ", "    {99999, ", 1), "2."),
        ("a warning ('!') message in the table", "k_error", ke.replace("    {1003, ", "    {1109, ", 1), "2."),
        ("a name misspelt", "k_error", ke.replace('SE_PROGRAM "DIV_ZERO"', 'SE_PROGRAM "DIVZERO"'), "3."),
        ("the terminal reset before the decision", "k_error",
         ke.replace("  fatal = (*message != '!');\n", "  tio_write(sdtgetstr(\"rlt\"));\n  fatal = (*message != '!');\n", 1), "4a."),
        ("a handler search not by group in the clause match", "op_jumps",
         src["op_jumps"].replace("found = exc_covers(p, (int)strlen(p), exc_name);", "found = (strcasecmp(p, exc_name) == 0);"), "6c."),
        ("k_descr_error not naming its message", "k_error", ke.replace("  descr_msg_no = msg_no; /* message is a copy", "  /* message is a copy"), "4c."),
        ("the early return not restoring the outer resume point", "kernel",
         src["kernel"].replace("            resume_env = outer_resume;\n            return;", "            return;"), "5b."),
        ("exc_raise not rolling back transactions", "op_jumps", src["op_jumps"].replace("txn_rollback_to(f.txn_depth);", "(void)0;"), "6a."),
        ("pdbg not throwing", "pdbg", src["pdbg"].replace("throw 'SYS.PROGRAM.NO_PDEBUG'", "null ;* 'SYS.PROGRAM.NO_PDEBUG'"), "8."),
    ]
    for label, key, text, want in muts:
        if text == src[key]:
            row("selftest: %s" % label, False, "the mutation changed nothing")
            ok_all = False
            continue
        s2 = dict(src)
        s2[key] = text
        fails = [name.split(" ")[0] for name, ok, _ in run(s2) if not ok]
        got = want in fails
        row("selftest: %s is caught by check %s" % (label, want), got, "failed checks: %s" % fails)
        ok_all = ok_all and got
    return ok_all


def main():
    print("test-sysexc-units: %s" % PATHS["k_error"])
    src = {k: read(p) for k, p in PATHS.items()}
    for name, ok, detail in run(src):
        row(name, ok, detail)
    if "--selftest" in sys.argv:
        selftest(src)
    print("\ntest-sysexc-units: %d passed, %d failed" % (passed, failed))
    sys.exit(0 if failed == 0 else 1)


if __name__ == "__main__":
    main()
