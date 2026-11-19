#!/usr/bin/env python3
"""test-svcsdwind-units.py - RELEASE_1.1 341: the SD service counts only ITS OWN sdwind.exe.

    python C:/Users/Don/Projects/SDCore4Windows/sdb_ai/sd64/gplbld/test-svcsdwind-units.py [--selftest]

On 18 Nov 2026 01:31 "sd -start" exited 1 and the service reported RUNNING because the only sdwind.exe on the machine was SD Core
Solo's: sdwind_running() matched the process NAME.  It now counts a process only when its image is the sdwind.exe beside the service
(full path, case-insensitive).  FREE: reads sdsvc.c only.  Exit 0 every check passed, 1 a check failed, 2 it could not run.
  W1  own_sdwind_path() builds the path from GetModuleFileNameA's directory plus SDWIND_EXE
  W2  sdwind_is_ours() opens the process for limited query, reads QueryFullProcessImageNameA and compares it with that path
      (_stricmp), a process it cannot open is not ours
  W3  sdwind_running() asks sdwind_is_ours() for each process with the name, and works out the path once first
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.normpath(os.path.join(HERE, "..", "gplsrc", "sdsvc", "sdsvc.c"))


def fn(src, name):
    m = re.search(r"\n(?:static\s+)?[A-Za-z_][A-Za-z0-9_ \*]*\b%s\s*\([^)]*\)\s*\{" % re.escape(name), src)
    if not m:
        return ""
    i, depth = m.end(), 1
    while i < len(src) and depth:
        depth += {"{": 1, "}": -1}.get(src[i], 0)
        i += 1
    return src[m.start():i]


def checks(src):
    rows = []
    p = fn(src, "own_sdwind_path")
    rows.append(("W1", "own_sdwind_path() is the sdwind.exe beside this program", "GetModuleFileNameA(NULL, own_sdwind, sizeof(own_sdwind))" in p
                 and "strrchr(own_sdwind, '\\\\')" in p and "strcpy(slash + 1, SDWIND_EXE);" in p))
    o = fn(src, "sdwind_is_ours")
    rows.append(("W2", "sdwind_is_ours() compares the process's full image path with that path; a process it cannot open is not ours",
                 "OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid)" in o and "if (h == NULL)\n    return FALSE;" in o
                 and "QueryFullProcessImageNameA(h, 0, img, &len)" in o and "return ok && _stricmp(img, own_sdwind) == 0;" in o))
    r = fn(src, "sdwind_running")
    rows.append(("W3", "sdwind_running() counts a named process only when sdwind_is_ours(), and works the path out first",
                 "_stricmp(pe.szExeFile, SDWIND_EXE) == 0 && sdwind_is_ours(pe.th32ProcessID)" in r
                 and 0 <= r.find("own_sdwind_path();") < r.find("CreateToolhelp32Snapshot")))
    return rows


MUTANTS = [
    ("the name alone counts again", "_stricmp(pe.szExeFile, SDWIND_EXE) == 0 && sdwind_is_ours(pe.th32ProcessID)", "_stricmp(pe.szExeFile, SDWIND_EXE) == 0"),
    ("any image path counts", "return ok && _stricmp(img, own_sdwind) == 0;", "return ok;"),
    ("a process that cannot be opened counts", "  if (h == NULL)\n    return FALSE;\n  ok = Query", "  if (h == NULL)\n    return TRUE;\n  ok = Query"),
    ("the path is another file", "strcpy(slash + 1, SDWIND_EXE);", "strcpy(slash + 1, \"sd.exe\");"),
]


def main():
    try:
        with open(SRC, encoding="latin-1", newline="") as f:
            src = f.read().replace("\r\n", "\n")
    except OSError:
        print("test-svcsdwind-units: CANNOT RUN - no %s" % SRC)
        return 2
    print("test-svcsdwind-units: %s" % SRC)
    rows = checks(src)
    for n, w, ok in rows:
        print("  [%s] %s %s" % ("PASS" if ok else "FAIL", n, w))
    bad = [r for r in rows if not r[2]]
    if "--selftest" in sys.argv:
        if bad:
            print("test-svcsdwind-units: CANNOT SELFTEST - the live file already fails")
            return 1
        missed = 0
        for what, old, new in MUTANTS:
            if old not in src:
                print("  [MUTANT CANNOT APPLY] %s" % what)
                missed += 1
                continue
            red = [r[0] for r in checks(src.replace(old, new, 1)) if not r[2]]
            print("  [%s] %s%s" % ("CAUGHT" if red else "MISSED", what, (" by " + ", ".join(red)) if red else ""))
            missed += 0 if red else 1
        print("test-svcsdwind-units --selftest: %d of %d mutants caught" % (len(MUTANTS) - missed, len(MUTANTS)))
        if missed:
            return 1
    print("test-svcsdwind-units: %d checks, %d failed" % (len(rows), len(bad)))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
