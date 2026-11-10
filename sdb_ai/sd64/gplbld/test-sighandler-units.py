#!/usr/bin/env python3
# test-sighandler-units.py - no signal handler of the SD kernel takes a semaphore or logs (S.196, 10 Nov 2026).
#
#   python C:\Users\Don\Projects\SDCore4Windows\sdb_ai\sd64\gplbld\test-sighandler-units.py
#   python C:\Users\Don\Projects\SDCore4Windows\sdb_ai\sd64\gplbld\test-sighandler-units.py --selftest
#
# 9 Nov 26 Windows port - from Linux ff779018 (S.196): the daemon is sdwind.c here, not sdlnxd.c; nothing else changes.
#
# WHY.  signal_handler() (linuxio.c) answered SIGHUP and SIGTERM with log_printf(), which reaches log_message() and
# StartExclusive(ERRLOG_SEM).  On the sdtest VPS (10 Nov 26) an ssh drop delivered SIGHUP while the session was writing
# "Forced logout" to the error log under ERRLOG_SEM: the handler then waited on its own semaphore for ever (69,254
# semtimedop + sched_yield in 3 s, SIGTERM ignored), and every audit line - every login - would have waited behind it.
# The handler now records the signal; log_termination_signal() writes the line from process_events().
#
# FREE CHECK: the C read as text with comments and string literals removed; no build.  It reads the handlers by name and
# cannot follow a call through a pointer, nor more than the one level it names (io_handler -> do_input).
#   H1  signal_handler, winch_handler, io_handler, do_input, sigchld_handler (linuxio.c, kernel.c) and sdwind's
#       signal_handler call nothing that takes a semaphore, logs, prints or allocates (FORBIDDEN below)
#   H2  signal_handler records the signal in term_signal_seen and raises EVT_TERMINATE
#   H3  term_signal_seen is a volatile sig_atomic_t
#   H4  log_termination_signal() clears term_signal_seen BEFORE it logs, and logs "Received termination signal"
#   H5  process_events() calls log_termination_signal() in its EVT_TERMINATE branch, before the branch returns
#   H6  fatal_signal_handler() calls release_owned_semaphores() before anything that logs (W.0, 14 Sep 26)
#   H0  the null case: every function named above was found, with a body
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.normpath(os.path.join(HERE, "..", "gplsrc"))
FILES = ("linuxio.c", "kernel.c", "sdwind.c")
FORBIDDEN = ("log_printf", "log_message", "StartExclusive", "LockSemaphore", "audit_message", "k_error", "tio_printf",
             "printf", "fprintf", "sprintf", "k_alloc", "malloc", "free", "syslog", "dump_status")
HANDLERS = (("linuxio.c", "signal_handler"), ("linuxio.c", "winch_handler"), ("linuxio.c", "io_handler"),
            ("linuxio.c", "do_input"), ("kernel.c", "sigchld_handler"), ("sdwind.c", "signal_handler"))


def strip(s):
    """C comments and string/char literals out (a literal is replaced by "" so a call's shape stays)."""
    out, i, n = [], 0, len(s)
    while i < n:
        if s.startswith("/*", i):
            j = s.find("*/", i + 2)
            i = n if j < 0 else j + 2
        elif s.startswith("//", i):
            j = s.find("\n", i)
            i = n if j < 0 else j
        elif s[i] in "\"'":
            q, j = s[i], i + 1
            while j < n and s[j] != q:
                j += 2 if s[j] == "\\" else 1
            out.append('""')
            i = j + 1
        else:
            out.append(s[i])
            i += 1
    return "".join(out)


def body(code, name):
    """The body of the function DEFINED as name (the definition, not a prototype), or None."""
    for m in re.finditer(r"\b%s\s*\(([^;{]*)\)\s*(?:int\s+\w+\s*;\s*)?\{" % re.escape(name), code):
        line_start = code.rfind("\n", 0, m.start()) + 1
        if re.match(r"\s*(if|while|return|for|switch)\b", code[line_start:m.start()]):
            continue
        i, depth = m.end() - 1, 0
        for j in range(i, len(code)):
            if code[j] == "{":
                depth += 1
            elif code[j] == "}":
                depth -= 1
                if depth == 0:
                    return code[i:j + 1]
    return None


def calls(b, names):
    return [n for n in names if re.search(r"\b%s\s*\(" % re.escape(n), b)]


def check(raw):
    code = {f: strip(raw[f]) for f in FILES}
    res = {}
    found = {}
    for f, fn in HANDLERS:
        found[(f, fn)] = body(code[f], fn)
    ev = body(code["kernel.c"], "process_events")
    lt = body(code["linuxio.c"], "log_termination_signal")
    fa = body(code["kernel.c"], "fatal_signal_handler")
    missing = [fn for (f, fn), b in found.items() if b is None] + [n for n, b in (("process_events", ev), ("log_termination_signal", lt),
                                                                                    ("fatal_signal_handler", fa)) if b is None]
    res["H0"] = (not missing, "not found: %s" % ", ".join(missing))
    bad = []
    for (f, fn), b in found.items():
        if b is not None:
            hit = calls(b, FORBIDDEN)
            if hit:
                bad.append("%s:%s calls %s" % (f, fn, ", ".join(hit)))
    res["H1"] = (not bad and not missing, "; ".join(bad))
    sh = found[("linuxio.c", "signal_handler")] or ""
    res["H2"] = (re.search(r"\bterm_signal_seen\s*=\s*signum\s*;", sh) is not None and "EVT_TERMINATE" in sh, sh[:200])
    res["H3"] = (re.search(r"volatile\s+sig_atomic_t\s+term_signal_seen\b", code["linuxio.c"]) is not None, "")
    lt = lt or ""
    clr = lt.find("term_signal_seen = 0")
    lg = lt.find("log_printf")
    res["H4"] = (clr >= 0 and lg > clr and "Received termination signal" in raw["linuxio.c"], lt[:200])
    ev = ev or ""
    m = re.search(r"if\s*\(\s*events\s*&\s*EVT_TERMINATE\s*\)\s*\{([^}]*)\}", ev)
    br = m.group(1) if m else ""
    res["H5"] = ("log_termination_signal()" in br and br.find("log_termination_signal()") < br.find("return"), br[:200])
    fa = fa or ""
    rel = fa.find("release_owned_semaphores()")
    first_log = min([p for p in (fa.find(n) for n in ("log_printf", "log_message", "printf")) if p >= 0] or [10 ** 9])
    res["H6"] = (0 <= rel < first_log, fa[:200])
    return res


NAMES = {
    "H0": "every handler and helper this check names was found, with a body (the null case)",
    "H1": "no signal handler (nor do_input, which SIGIO's handler calls) takes a semaphore, logs, prints or allocates",
    "H2": "signal_handler records the signal in term_signal_seen and raises EVT_TERMINATE",
    "H3": "term_signal_seen is a volatile sig_atomic_t",
    "H4": "log_termination_signal clears term_signal_seen before it logs 'Received termination signal'",
    "H5": "process_events calls log_termination_signal in its EVT_TERMINATE branch, before the branch returns",
    "H6": "fatal_signal_handler releases this process's semaphores before anything that logs",
}


def read():
    return {f: open(os.path.join(SRC, f), encoding="latin-1").read() for f in FILES}


def run(raw, quiet=False):
    res = check(raw)
    failed = [k for k, (ok, _) in res.items() if not ok]
    if not quiet:
        for k in sorted(res):
            ok, why = res[k]
            print("  [%s] %s %s%s" % ("PASS" if ok else "FAIL", k, NAMES[k], "" if ok else "   <- " + why))
    return failed


def sub(f, old, new):
    def m(raw):
        if raw[f].count(old) != 1:
            raise ValueError("%s: the text to change is in %d places" % (f, raw[f].count(old)))
        r = dict(raw)
        r[f] = raw[f].replace(old, new)
        return r
    return m


MUTANTS = [
    ("the handler logs again", "H1", sub("linuxio.c", "      term_signal_seen = signum;\n", "      log_printf(\"Received termination signal %d\\n\", signum);\n")),
    ("the handler takes a semaphore", "H1", sub("linuxio.c", "      term_signal_seen = signum;\n", "      term_signal_seen = signum;\n      StartExclusive(ERRLOG_SEM, 1);\n")),
    ("the handler forgets the signal", "H2", sub("linuxio.c", "      term_signal_seen = signum;\n", "      ;\n")),
    ("not volatile", "H3", sub("linuxio.c", "Private volatile sig_atomic_t term_signal_seen", "Private sig_atomic_t term_signal_seen")),
    ("logged before cleared", "H4", sub("linuxio.c", "    term_signal_seen = 0;\n    log_printf(\"Received termination signal %d\\n\", signum);",
                                        "    log_printf(\"Received termination signal %d\\n\", signum);\n    term_signal_seen = 0;")),
    ("process_events does not log it", "H5", sub("kernel.c", "    log_termination_signal(); /* 10 Nov 26 S.196", "    ; /* 10 Nov 26 S.196")),
    ("the fatal handler logs first", "H6", sub("kernel.c", "  release_owned_semaphores();\n  set_old_tty_modes();\n  log_printf(\"Fault type",
                                                "  set_old_tty_modes();\n  log_printf(\"Fault type")),
    ("the winch handler logs", "H1", sub("linuxio.c", "  (void)sig;\n  if (read_window_size())", "  (void)sig;\n  log_printf(\"winch\\n\");\n  if (read_window_size())")),
    ("the handler is renamed away (null case)", "H0", sub("linuxio.c", "void signal_handler(signum) int signum;", "void sig_handler_x(signum) int signum;")),
]


def selftest(raw):
    base = run(raw, quiet=True)
    if base:
        print("selftest: the unchanged tree fails %s; run the plain check first" % base)
        return 1
    holes = 0
    for name, want, mut in MUTANTS:
        try:
            failed = run(mut(raw), quiet=True)
        except ValueError as exc:
            print("  [FAIL] selftest: %s  <- %s" % (name, exc))
            holes += 1
            continue
        hit = want in failed
        holes += not hit
        print("  [%s] selftest: %s is caught by %s (failed: %s)" % ("PASS" if hit else "FAIL", name, want, " ".join(failed) or "none"))
    print("selftest: %d mutants, %d not caught" % (len(MUTANTS), holes))
    return 1 if holes else 0


def main(argv):
    raw = read()
    print("test-sighandler-units: reading %s in %s" % (", ".join(FILES), SRC))
    if "--selftest" in argv:
        return selftest(raw)
    failed = run(raw)
    print("test-sighandler-units: %d passed, %d failed" % (len(NAMES) - len(failed), len(failed)))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
