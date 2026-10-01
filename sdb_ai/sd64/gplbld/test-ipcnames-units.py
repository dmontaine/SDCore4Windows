"""This product's IPC keys are its own, and the object NAMES carry them.

WHY THIS EXISTS.  Owner, 2 Oct 2026 (Linux session): each of the four SD Core
products gets its own shared-memory and semaphore key so they can run side by
side, and none may reuse the 0x716d family OpenQM, ScarletDME and upstream SD
use.  The family was agreed with SD Core for Linux:

    Linux 0x53434C01/02   Linux Solo 0x53434C11/12
    Windows 0x53435701/02   Windows Solo 0x53435711/12

ON WINDOWS THE KEYS DO NOT SEPARATE ANYTHING BY THEMSELVES.  Nothing calls
shmget() or semget(); the segment is a POSIX shm_open() name and the semaphores
are Win32 "Global\\" names (gplsrc/sddefs.h), and each name had the old key's
digits written into it.  The instruction as sent named only the two defines -
right for Linux - and following it here would have left every Windows product
on the old names, still colliding, with the keys looking correct.  So this
checks the NAMES against the keys, which is the part that would have been missed.

It is a source check: no SD, no install, no elevation.  The mutants run on
synthetic text, never on the file.

  python gplbld/test-ipcnames-units.py

Exit 0 all checks passed, 1 a check failed, 2 sddefs.h is not there to read.
"""

import os
import re
import sys

# THIS PRODUCT.  The Solo tree's copy of this file names 0x53435711/12.
PRODUCT = "SD Core for Windows"
WANT_SHM = 0x53435701
WANT_SEM = 0x53435702

OTHER_PRODUCTS = {
    "SD Core for Linux": (0x53434C01, 0x53434C02),
    "SD Core for Linux Solo": (0x53434C11, 0x53434C12),
    "SD Core for Windows": (0x53435701, 0x53435702),
    "SD Core Solo for Windows": (0x53435711, 0x53435712),
}

HERE = os.path.dirname(os.path.abspath(__file__))
SDDEFS = os.path.join(HERE, "..", "gplsrc", "sddefs.h")

failures = 0
passes = 0


def check(label, ok, detail=""):
    global failures, passes
    if ok:
        passes += 1
        print("  [PASS] " + label)
    else:
        failures += 1
        print("  [FAIL] " + label + ("  " + detail if detail else ""))


def read_defines(text):
    """The live #defines this test is about, as {name: value text}."""
    out = {}
    for name in ("SD_SHM_KEY", "SD_SEM_KEY", "SD_POSIX_SHM_NAME", "SD_WIN32_SEM_FMT"):
        m = re.search(r"^#define\s+" + name + r"\s+(\S+)", text, re.MULTILINE)
        out[name] = m.group(1) if m else None
    return out


def problems(d, want_shm, want_sem):
    """Everything wrong with a set of defines, as a list of strings."""
    bad = []
    for k in ("SD_SHM_KEY", "SD_SEM_KEY", "SD_POSIX_SHM_NAME", "SD_WIN32_SEM_FMT"):
        if d.get(k) is None:
            bad.append("%s not defined" % k)
    if bad:
        return bad
    shm = int(d["SD_SHM_KEY"], 16)
    sem = int(d["SD_SEM_KEY"], 16)
    if shm != want_shm:
        bad.append("SD_SHM_KEY is 0x%08x, want 0x%08x" % (shm, want_shm))
    if sem != want_sem:
        bad.append("SD_SEM_KEY is 0x%08x, want 0x%08x" % (sem, want_sem))
    if ("%08x" % shm) not in d["SD_POSIX_SHM_NAME"].lower():
        bad.append("SD_POSIX_SHM_NAME %s does not carry SD_SHM_KEY's digits" % d["SD_POSIX_SHM_NAME"])
    if ("%08x" % sem) not in d["SD_WIN32_SEM_FMT"].lower():
        bad.append("SD_WIN32_SEM_FMT %s does not carry SD_SEM_KEY's digits" % d["SD_WIN32_SEM_FMT"])
    for k in ("SD_POSIX_SHM_NAME", "SD_WIN32_SEM_FMT"):
        if "716d" in d[k].lower():
            bad.append("%s is still in upstream's 0x716d family: %s" % (k, d[k]))
    return bad


print("test-ipcnames-units: %s, want shm 0x%08x sem 0x%08x" % (PRODUCT, WANT_SHM, WANT_SEM))
print("test-ipcnames-units: reading " + os.path.normpath(SDDEFS))
if not os.path.isfile(SDDEFS):
    print("test-ipcnames-units: sddefs.h not found - nothing measured.")
    sys.exit(2)
with open(SDDEFS, "rb") as f:
    text = f.read().decode("ascii", "replace")

live = read_defines(text)
for k, v in live.items():
    print("    %-18s %s" % (k, v))

check("CONTROL: all four live defines were found", all(v is not None for v in live.values()))
check("CONTROL: the product table has four distinct key pairs",
      len(set(OTHER_PRODUCTS.values())) == 4 and OTHER_PRODUCTS[PRODUCT] == (WANT_SHM, WANT_SEM))
p = problems(live, WANT_SHM, WANT_SEM)
check("the keys are this product's and both object names carry them", p == [], "; ".join(p))
for other, (oshm, osem) in OTHER_PRODUCTS.items():
    if other == PRODUCT:
        continue
    check("no live name is %s's" % other,
          ("%08x" % oshm) not in (live["SD_POSIX_SHM_NAME"] or "").lower()
          and ("%08x" % osem) not in (live["SD_WIN32_SEM_FMT"] or "").lower())

# MUTANTS, on synthetic text.  The first is the change exactly as instructed for
# Linux: the two defines moved and the names left alone.
old = ('#define SD_SHM_KEY 0x%08x\n#define SD_SEM_KEY 0x%08x\n'
       '#define SD_POSIX_SHM_NAME "/sd_shm_716d0301"\n'
       '#define SD_WIN32_SEM_FMT  "Global\\\\sd_sem_716d0302_%%d"\n') % (WANT_SHM, WANT_SEM)
check("MUTANT: keys changed but names left on 0x716d is caught", problems(read_defines(old), WANT_SHM, WANT_SEM) != [])
swapped = ('#define SD_SHM_KEY 0x%08x\n#define SD_SEM_KEY 0x%08x\n'
           '#define SD_POSIX_SHM_NAME "/sd_shm_%08x"\n'
           '#define SD_WIN32_SEM_FMT  "Global\\\\sd_sem_%08x_%%d"\n') % (WANT_SHM, WANT_SEM, WANT_SEM, WANT_SHM)
check("MUTANT: the two names swapped is caught", problems(read_defines(swapped), WANT_SHM, WANT_SEM) != [])
good = ('#define SD_SHM_KEY 0x%08x\n#define SD_SEM_KEY 0x%08x\n'
        '#define SD_POSIX_SHM_NAME "/sd_shm_%08x"\n'
        '#define SD_WIN32_SEM_FMT  "Global\\\\sd_sem_%08x_%%d"\n') % (WANT_SHM, WANT_SEM, WANT_SHM, WANT_SEM)
check("CONTROL: a correct synthetic set passes", problems(read_defines(good), WANT_SHM, WANT_SEM) == [])

print("")
if passes == 0:
    print("test-ipcnames-units: VOID - no check ran.")
    sys.exit(2)
if failures:
    print("test-ipcnames-units: %d passed, %d failed." % (passes, failures))
    sys.exit(1)
print("test-ipcnames-units: %d passed, 0 failed." % passes)
sys.exit(0)
