#!/usr/bin/env python3
# test-shmmode-units.py - W.11 F1 in its Windows form: the shared segment and the semaphores are not open to every local user, and the
# LocalSystem daemon does not take what it runs from the segment.  FREE CHECK, text only (C comments removed), no install, no elevation, no sd.
#
#   python sdb_ai/sd64/gplbld/test-shmmode-units.py
#   python sdb_ai/sd64/gplbld/test-shmmode-units.py --selftest      (mutants)
#
# 13 Nov 26 Windows port of Linux's test-shmmode-units.py (b1d496df; RELEASE_1.1 249, 254).  Linux holds the modes it passes to shmget() and
# semget() (0660, then the group sdusers by IPC_SET).  HERE THE MODE IS NOT THE WALL: sysseg.c creates the segment with shm_open(..., 0666) and
# the MSYS2 mount is noacl, so the bits mean nothing.  What decides who can open it is the NTFS ACL of the folder /dev/shm is mapped to, which
# the segment's file inherits (measured 18 Sep 2026, HISTORY row 59: sd_shm_* carried sdusers:(RX,W), an ordinary account outside sdusers was
# refused).  So the Windows checks are:
#   W1 stage.py's fstab maps /dev/shm to C:/ProgramData/SD/shm, and the segment's name is a bare /name, so its file lands there
#   W2 sd.iss creates {#DataDir}\shm and gives it no ACL of its own (it inherits the data tree's)
#   W3 the data tree's icacls removes inheritance and grants SYSTEM, Administrators and sdusers only - no Everyone, Users,
#      Authenticated Users or Interactive (by name or SID)
#   W4 the semaphores' descriptor (win32sem.c build_descriptor) is SYSTEM, Administrators and the group, nothing wider, and sdsem.c asks
#      for SD_USERS_GROUP, which is "sdusers"
#   W5 sdwind.c (LocalSystem): no live system(), "sd -cleanup" started with execl, own_sysdir() called before the segment is opened,
#      and sysseg->sysdir read nowhere in code (Linux S3/S4; the configuration-file half is test-sdwindsysdir-units)
# NOT SAID HERE: that an installed segment carries that ACL - an install shows it (icacls C:\ProgramData\SD\shm\sd_shm_*).
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, ".."))
F = {"stage": os.path.join(HERE, "stage.py"), "iss": os.path.join(HERE, "sd.iss"), "sysseg": os.path.join(ROOT, "gplsrc", "sysseg.c"),
     "sddefs": os.path.join(ROOT, "gplsrc", "sddefs.h"), "w32sem": os.path.join(ROOT, "gplsrc", "win32sem.c"),
     "sdsem": os.path.join(ROOT, "gplsrc", "sdsem.c"), "sdwind": os.path.join(ROOT, "gplsrc", "sdwind.c")}
BS = chr(92)
WIDE = ["*S-1-1-0", "*S-1-5-11", "*S-1-5-32-545", "*S-1-5-4", "Everyone", "Users", "Authenticated Users", "INTERACTIVE"]
passed = failed = 0


def row(name, ok, detail=""):
    global passed, failed
    if ok:
        passed += 1
        print("  [PASS] " + name)
    else:
        failed += 1
        print("  [FAIL] " + name + ("   <- " + detail if detail else ""))


def code(s):
    s = re.sub(r"/\*.*?\*/", "", s, flags=re.S)
    return re.sub(r"//[^\n]*", "", s)


def func(src, head):
    m = re.search(re.escape(head) + r"[^;{]*\{.*?\n\}", src, re.S)
    return m.group(0) if m else ""


def run(t):
    st = t["stage"]
    m = re.search(r"FSTAB = \((.*?)\)\n", st, re.S)
    row("W1 stage.py's fstab maps /dev/shm to C:/ProgramData/SD/shm", bool(m) and "'C:/ProgramData/SD/shm /dev/shm ntfs binary 0 0" in m.group(1),
        m.group(1)[-80:] if m else "FSTAB not found")
    nm = re.search(r'#define SD_POSIX_SHM_NAME "([^"]*)"', t["sddefs"])
    row("W1 ...and the segment's name is a bare /name, so shm_open() puts it in that folder", bool(nm) and re.fullmatch(r"/[A-Za-z0-9_]+", nm.group(1)) is not None,
        nm.group(1) if nm else "SD_POSIX_SHM_NAME not found")
    body = func(code(t["sysseg"]), "Private bool create_shared_segment(")
    row("W1 ...create_shared_segment() makes it with shm_open(SD_POSIX_SHM_NAME, O_CREAT", "shm_open(SD_POSIX_SHM_NAME, O_CREAT" in body, body[:120])

    iss = t["iss"]
    row("W2 sd.iss creates {#DataDir}" + BS + "shm", ('Name: "{#DataDir}' + BS + 'shm"') in iss)
    shm_acl = [ln for ln in iss.split("\n") if not ln.lstrip().startswith(";") and BS + "shm" in ln and re.search(r"icacls|/grant|Set-Acl", ln, re.I)]
    row("W2 ...and no line gives it an ACL of its own", not shm_acl, "; ".join(shm_acl)[:200])
    trees = [ln for ln in iss.split("\n") if not ln.lstrip().startswith(";") and '"""{#DataDir}"" /inheritance:r' in ln]
    row("W3 the data tree's icacls is found once", len(trees) == 1, "%d found" % len(trees))
    tree = trees[0] if trees else ""
    grants = re.findall(r'/grant ""([^:"]+):', tree)
    row("W3 ...it removes inheritance and grants SYSTEM, Administrators and sdusers only", grants == ["*S-1-5-18", "*S-1-5-32-544", "sdusers"], repr(grants))
    row("W3 ...and names no wider principal", not any(w in grants for w in WIDE), repr(grants))

    w = code(t["w32sem"])
    sddls = re.findall(r'"(D:[^"]*)"', w)
    row("W4 the semaphores' descriptors are SYSTEM, Administrators and the group",
        sorted(sddls) == sorted(["D:(A;;GA;;;SY)(A;;GA;;;BA)(A;;GA;;;)", "D:(A;;GA;;;SY)(A;;GA;;;BA)(A;;GA;;;%s)", "D:(A;;GA;;;SY)(A;;GA;;;BA)"]), repr(sddls))
    row("W4 ...and none names Everyone, Authenticated Users, Users or Interactive", not any(re.search(r";;;(WD|AU|BU|IU)\)", s) for s in sddls), repr(sddls))
    gr = re.search(r'#define SD_USERS_GROUP "([^"]*)"', t["sddefs"])
    row("W4 ...sdsem.c makes them for SD_USERS_GROUP, which is sdusers",
        "w32sem_create(name, SD_USERS_GROUP, &already)" in code(t["sdsem"]) and bool(gr) and gr.group(1) == "sdusers", gr.group(1) if gr else "")

    d = code(t["sdwind"])
    row("W5 sdwind.c has no live system()", re.search(r"\bsystem\s*\(", d) is None)
    row("W5 ...starts \"sd -cleanup\" with execl", re.search(r'execl\([^;]*"-cleanup"', d) is not None)
    i, j = d.find("if (!own_sysdir())"), d.find("shm_open(SD_POSIX_SHM_NAME")
    row("W5 ...calls own_sysdir() before it opens the segment", 0 <= i < j, "own_sysdir at %d, shm_open at %d" % (i, j))
    row("W5 ...and reads sysseg->sysdir nowhere in code", "sysseg->sysdir" not in d)


def load():
    t = {}
    for k, p in F.items():
        if not os.path.isfile(p):
            print("REFUSING - missing file: " + p)
            sys.exit(2)
        t[k] = open(p, encoding="latin-1").read()
    return t


MUTANTS = [
    ("fstab maps /dev/shm elsewhere", "stage", "'C:/ProgramData/SD/shm /dev/shm", "'C:/Users/Public/shm /dev/shm"),
    ("the segment's name is a path", "sddefs", '"/sd_shm_53435701"', '"/tmp/sd_shm_53435701"'),
    ("the segment is not made with shm_open", "sysseg", "shm_open(SD_POSIX_SHM_NAME, O_CREAT | O_RDWR, 0666)", "open(\"/tmp/seg\", O_CREAT | O_RDWR, 0666)"),
    ("the shm folder is not created", "iss", 'Name: "{#DataDir}' + BS + 'shm"; Flags: uninsneveruninstall', 'Name: "{#DataDir}' + BS + 'shmx"; Flags: uninsneveruninstall'),
    ("the shm folder is given Users", "iss", 'Name: "{#DataDir}' + BS + 'shm"; Flags: uninsneveruninstall',
     'Name: "{#DataDir}' + BS + 'shm"; Flags: uninsneveruninstall\nFilename: "{sys}' + BS + 'icacls.exe"; Parameters: """{#DataDir}' + BS + 'shm"" /grant ""*S-1-5-32-545:(OI)(CI)M"""'),
    ("the data tree keeps inheritance", "iss", '"""{#DataDir}"" /inheritance:r', '"""{#DataDir}"" /inheritance:e'),
    ("the data tree grants Users", "iss", '/grant ""sdusers:(OI)(CI)M"""', '/grant ""sdusers:(OI)(CI)M"" /grant ""*S-1-5-32-545:(OI)(CI)M"""'),
    ("the data tree grants Everyone in sdusers' place", "iss", '/grant ""sdusers:(OI)(CI)M"""', '/grant ""Everyone:(OI)(CI)M"""'),
    ("the semaphores are given Everyone", "w32sem", '"D:(A;;GA;;;SY)(A;;GA;;;BA)(A;;GA;;;%s)"', '"D:(A;;GA;;;SY)(A;;GA;;;BA)(A;;GA;;;WD)(A;;GA;;;%s)"'),
    ("the fallback semaphores are given Authenticated Users", "w32sem", 'strcpy(sddl, "D:(A;;GA;;;SY)(A;;GA;;;BA)")', 'strcpy(sddl, "D:(A;;GA;;;SY)(A;;GA;;;BA)(A;;GA;;;AU)")'),
    ("the semaphores are made for no group", "sdsem", "w32sem_create(name, SD_USERS_GROUP, &already)", "w32sem_create(name, NULL, &already)"),
    ("sdwind runs a shell again", "sdwind", 'execl(cmd, "sd", "-cleanup", (char*)NULL);', 'system(cmd);'),
    ("sdwind opens the segment before it knows its directory", "sdwind", "  if (!own_sysdir()) {",
     "  (void)shm_open(SD_POSIX_SHM_NAME, O_RDWR, 0666);\n  if (!own_sysdir()) {"),
    ("sdwind reads the segment's sysdir", "sdwind", 'execl(cmd, "sd", "-cleanup", (char*)NULL);', 'execl(cmd, "sd", "-cleanup", (char*)sysseg->sysdir, (char*)NULL);'),
]


def selftest():
    global passed, failed
    base = load()
    holes = 0
    print("--- self-test: each mutation must match its text once and turn the run red ---")
    for name, key, old, new in MUTANTS:
        n = base[key].count(old)
        if n != 1:
            print("  [FAIL] %s: the text to mutate matches %d times in %s, not once" % (name, n, key))
            holes += 1
            continue
        t = dict(base)
        t[key] = base[key].replace(old, new, 1)
        passed = failed = 0
        saved, sys.stdout = sys.stdout, open(os.devnull, "w")
        try:
            run(t)
        finally:
            sys.stdout.close()
            sys.stdout = saved
        print("  [%s] %s" % ("pass" if failed else "FAIL", name + ("" if failed else ": NOT CAUGHT")))
        holes += 0 if failed else 1
    print("self-test: %d mutants, %d not caught" % (len(MUTANTS), holes))
    return holes


def main():
    global passed, failed
    print("test-shmmode-units: " + " ".join(F[k] for k in sorted(F)))
    run(load())
    print("%d passed, %d failed" % (passed, failed))
    if passed < 15:
        print("REFUSING - %d checks passed, 15 expected: the run did not measure what it claims" % passed)
        return 1
    rc = 1 if failed else 0
    if "--selftest" in sys.argv[1:] and rc == 0:
        rc = 1 if selftest() else 0
    return rc


if __name__ == "__main__":
    sys.exit(main())
