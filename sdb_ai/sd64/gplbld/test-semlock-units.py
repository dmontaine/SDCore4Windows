#!/usr/bin/env python3
"""test-semlock-units.py - a failed semaphore wait ends a process; sd -stop ends what outlives SIGTERM (Windows port of Linux S.177, 9 Nov 26).

  python C:/Users/Don/Projects/SDCore4Windows/sdb_ai/sd64/gplbld/test-semlock-units.py
  python .../test-semlock-units.py --selftest

No elevation, no install, no sd.  Exit 0 all checks passed, 1 a check failed, 2 it could not run.

THE DEFECT (Linux, 8 Nov 2026): sessions spun at 84-92% CPU for hours.  LockSemaphore retried on EVERY error, and a stop left
idle sessions running with SD gone under them.

THE FIX, AS HELD HERE: (1) w32sem_trywait says taken / busy / failed, LockSemaphore retries only on busy and otherwise calls
semaphores_gone, which logs and calls _exit - never exit(), whose handlers may lock; (2) "sd -stop" and "sd -restart" call
stop_sd_ex(TRUE), which after the wait SIGKILLs only a user-table pid (or the daemon's) whose program is in this program's folder
(/proc/<pid>/exename: Linux's /proc/<pid>/maps key does not exist under the MSYS2 runtime), before the segment and semaphores go;
plain stop_sd() - bind_sysseg()'s failure path - is stop_sd_ex(FALSE) and kills nobody.

WHAT THIS IS NOT.  It reads the C source as text.  It cannot say a session really is ended; that is a run against an installed SD.
--selftest mutates the source in memory, touches no file, and requires each mutant to be caught.  It also checks Solo's tree when
that tree is beside this one, and says so.
"""

import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.abspath(os.path.join(HERE, os.pardir, "gplsrc"))
SOLO = os.path.abspath(os.path.join(HERE, os.pardir, os.pardir, os.pardir, os.pardir, "SDCore4WindowsSolo", "sdb_ai", "sd64", "gplsrc"))
FILES = ("sdsem.c", "win32sem.c", "sysseg.c", "sd.c")


def strip_comments(text):
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    return re.sub(r"//[^\n]*", "", text)


def body(code, signature):
    i = code.find(signature)
    if i < 0:
        return None
    j = code.find("{", i)
    depth = 0
    for k in range(j, len(code)):
        if code[k] == "{":
            depth += 1
        elif code[k] == "}":
            depth -= 1
            if depth == 0:
                return code[j + 1:k]
    return None


def checks(src):
    out = []

    def ck(name, ok, detail=""):
        out.append((name, bool(ok), detail))

    sem = strip_comments(src["sdsem.c"])
    w32 = strip_comments(src["win32sem.c"])
    seg = strip_comments(src["sysseg.c"])
    sdc = strip_comments(src["sd.c"])

    tw = body(w32, "int w32sem_trywait(void* handle)")
    ck("w32sem_trywait() is there", tw is not None)
    if tw is not None:
        ck("WAIT_OBJECT_0 returns 1", re.search(r"WAIT_OBJECT_0\s*\)\s*return\s+1\s*;", tw) is not None)
        ck("only WAIT_TIMEOUT is busy, anything else -1",
           re.search(r"return\s*\(\s*result\s*==\s*WAIT_TIMEOUT\s*\)\s*\?\s*0\s*:\s*-1\s*;", tw) is not None)

    gone = body(sem, "static void semaphores_gone(int semno, unsigned long err)")
    ck("semaphores_gone() is there", gone is not None)
    if gone is not None:
        ck("semaphores_gone() ends with _exit()", re.search(r"\b_exit\s*\(", gone) is not None)
        ck("semaphores_gone() never calls exit()", re.search(r"(?<![_\w])exit\s*\(", gone) is None)
        locking = [w for w in ("LockSemaphore", "StartExclusive", "log_printf", "log_message", "audit_message")
                   if re.search(r"\b%s\s*\(" % w, gone)]
        ck("semaphores_gone() calls nothing that takes a semaphore", not locking, locking)
        ck("semaphores_gone() says why, in syslog", re.search(r"\bsyslog\s*\(", gone) is not None)

    lock = body(sem, "void LockSemaphore(int semno)")
    ck("LockSemaphore() is there", lock is not None)
    if lock is not None:
        ck("the loop runs while the answer is <= 0", re.search(r"while\s*\(\s*\(\s*got\s*=\s*w32sem_trywait\s*\(\s*sd_sem\[semno\]\s*\)\s*\)\s*<=\s*0\s*\)", lock) is not None)
        test = re.search(r"if\s*\(\s*got\s*<\s*0\s*\)\s*semaphores_gone\s*\(", lock)
        ck("a failed wait calls semaphores_gone()", test is not None)
        yld = lock.find("RelinquishTimeslice")
        ck("that test comes before the yield", test is not None and yld > test.start(), yld)

    plain = body(seg, "bool stop_sd()")
    ck("stop_sd() is stop_sd_ex(FALSE) and nothing else",
       plain is not None and re.fullmatch(r"\s*return\s+stop_sd_ex\s*\(\s*FALSE\s*\)\s*;\s*", plain) is not None)
    ex = body(seg, "bool stop_sd_ex(bool kill_survivors)")
    ck("stop_sd_ex() is there", ex is not None)
    if ex is not None:
        calls = [m.start() for m in re.finditer(r"\bend_attached_survivors\s*\(", ex)]
        ck("stop_sd_ex() calls end_attached_survivors() once", len(calls) == 1, len(calls))
        guard = re.search(r"if\s*\(\s*kill_survivors\s*\)\s*\{[^\n]*\n[^\n]*end_attached_survivors\s*\(", ex)
        ck("the call is guarded by kill_survivors", guard is not None)
        unbind = ex.find("unbind_sysseg")
        ck("the survivors are ended before the segment is given up", calls and unbind > calls[0], (calls, unbind))
    end = body(seg, "static bool end_if_sd_process(int pid)")
    ck("end_if_sd_process() is there", end is not None)
    if end is not None:
        ck("it skips itself and pids <= 0", re.search(r"pid\s*<=\s*0\s*\)\s*\|\|\s*\(\s*pid\s*==\s*\(int\)\s*getpid\s*\(\s*\)", end) is not None)
        ck("it compares the two folders, ignoring case", re.search(r"strcasecmp\s*\(\s*mine\s*,\s*theirs\s*\)\s*!=\s*0", end) is not None)
        kills = re.findall(r"\bkill\s*\(([^)]*)\)", end)
        ck("it probes with signal 0 and its only other kill() is SIGKILL", kills == ["pid, 0", "pid, SIGKILL"], kills)
        folder = end.find("strcasecmp")
        sk = end.find("SIGKILL")
        ck("the folder test comes before the SIGKILL", 0 <= folder < sk, (folder, sk))
    pf = body(seg, "static bool program_folder(const char* who, char* folder, size_t size)")
    ck("program_folder() reads /proc/<who>/exename", pf is not None and '"/proc/%s/exename"' in pf)
    bind = body(seg, "bool bind_sysseg(")
    ck("bind_sysseg() does not use the killing form", bind is not None and "stop_sd_ex" not in bind)

    for opt, pat in (("-STOP", r"if\s*\(\s*stop_sd_ex\s*\(\s*TRUE\s*\)\s*\)"), ("-RESTART", r"if\s*\(\s*stop_sd_ex\s*\(\s*TRUE\s*\)\s*&&\s*start_sd")):
        i = sdc.find('stricmp(argv[arg], "%s")' % opt)
        ck("sd %s calls stop_sd_ex(TRUE)" % opt.lower(), i >= 0 and re.search(pat, sdc[i:i + 200]) is not None)
    every = sum(len(re.findall(r"stop_sd_ex\s*\(\s*TRUE\s*\)", strip_comments(t))) for t in src.values())
    ck("stop_sd_ex(TRUE) is called from exactly those two places", every == 2, every)
    return out


def mutants(src):
    def mut(name, fname, old, new):
        m = dict(src)
        m[fname] = src[fname].replace(old, new, 1)
        return (name, m, m[fname] != src[fname])
    return [
        mut("a failed wait counted as busy (the old spin)", "win32sem.c", "(result == WAIT_TIMEOUT) ? 0 : -1", "0"),
        mut("the failure test taken out of the loop", "sdsem.c", "    if (got < 0)\n      semaphores_gone(semno, w32sem_last_error());\n", ""),
        mut("exit() instead of _exit()", "sdsem.c", "  _exit(3);", "  exit(3);"),
        mut("semaphores_gone() logs through log_printf (it locks)", "sdsem.c", '  syslog(LOG_ERR, "%s", msg);', '  log_printf("%s", msg);'),
        mut("plain stop_sd() kills", "sysseg.c", "return stop_sd_ex(FALSE);", "return stop_sd_ex(TRUE);"),
        mut("the kill_survivors guard dropped", "sysseg.c", "if (kill_survivors) {", "if (TRUE) {"),
        mut("a pid killed without the folder test", "sysseg.c", "(strcasecmp(mine, theirs) != 0))", "FALSE)"),
        mut("the folder compared case-sensitively", "sysseg.c", "strcasecmp(mine, theirs)", "strcmp(mine, theirs)"),
        mut("SIGTERM again instead of SIGKILL", "sysseg.c", "if (kill(pid, SIGKILL))", "if (kill(pid, SIGTERM))"),
        mut("the process's own pid not skipped", "sysseg.c", "(pid == (int)getpid()) || ", ""),
        mut("sd -stop back to plain stop_sd()", "sd.c", "if (stop_sd_ex(TRUE)) {", "if (stop_sd()) {"),
        mut("sd -restart back to plain stop_sd()", "sd.c", "if (stop_sd_ex(TRUE) && start_sd", "if (stop_sd() && start_sd"),
    ]


def load(root):
    src = {}
    for f in FILES:
        p = os.path.join(root, f)
        if not os.path.isfile(p):
            return None, p
        with open(p, encoding="latin-1", newline="") as fh:
            src[f] = fh.read()
    return src, None


def report(label, root, src):
    print("sources : %s (%s) [%s]" % (root, ", ".join(FILES), label))
    res = checks(src)
    fails = 0
    for name, ok, detail in res:
        print("  [%s] %s%s" % ("PASS" if ok else "FAIL", name, "" if ok or detail == "" else "  (" + str(detail) + ")"))
        fails += 0 if ok else 1
    return len(res), fails


def main():
    src, missing = load(SRC)
    if src is None:
        print("test-semlock-units: CANNOT RUN - no %s" % missing)
        return 2
    if "--selftest" in sys.argv:
        base = checks(src)
        if not all(ok for _, ok, _ in base):
            print("selftest: CANNOT RUN - the unmutated source already fails:")
            for n, ok, d in base:
                if not ok:
                    print("  FAIL %s (%s)" % (n, d))
            return 2
        bad = 0
        ms = mutants(src)
        for name, msrc, applied in ms:
            if not applied:
                print("  [NOT APPLIED] %s" % name)
                bad += 1
                continue
            caught = [n for n, ok, _ in checks(msrc) if not ok]
            print("  [%s] %s%s" % ("caught" if caught else "MISSED", name, "  (%d check(s) failed)" % len(caught) if caught else ""))
            bad += 0 if caught else 1
        print("test-semlock-units --selftest: %d mutant(s), %d not caught" % (len(ms), bad))
        return 1 if bad else 0
    total, fails = report("Core", SRC, src)
    solo, _ = load(SOLO)
    if solo is None:
        print("Solo's tree is not beside this one: Solo NOT checked")
    else:
        t, f = report("Solo", SOLO, solo)
        total += t
        fails += f
    if total < 20:
        print("test-semlock-units: only %d checks ran - a function was not found" % total)
        return 2
    print("test-semlock-units: %d checks, %d failed" % (total, fails))
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
