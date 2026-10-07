"""SET.BACKUP.DIRECTORY and the saved backup directory: every piece is there and wired.

WHY THIS EXISTS.  Owner's ruling, 1 Oct 2026: a command SET.BACKUP.DIRECTORY saves the
backup directory in the config file, and BACKUP.ACCOUNT / RESTORE.ACCOUNT use it, asking
for it - and saving the answer as if the command had been run - when there is none.
The feature is eight small pieces in four languages, and what fails when one is missing
is silent or far away:

  - the C parser must accept BACKUPDIR=, or SD does not START on a file carrying it;
  - a message number that no file backs prints nothing useful in the middle of a backup;
  - an installer that does not ship sd-backupdir.ps1 leaves SET.BACKUP.DIRECTORY failing on
    a real install while every unit test is green;
  - a question asked AFTER the login hold is taken leaves the hold standing on a refusal;
  - the VOC record is what makes the verb exist, and which layer holds it differs by product.

It is a source check: no SD, no install, no elevation.  The mutants run on synthetic text.

  python gplbld/test-bakdir-units.py

Exit 0 all checks passed, 1 a check failed, 2 the tree is not there to read.
"""

import os
import re
import sys

# THIS PRODUCT.  The full product's copy names its own message number and VOC layers.
PRODUCT = "SD Core for Windows"
OS_MESSAGE = 12010                      # the per-OS helper's own message (Solo's copy: 12042)
VOC_LAYERS = ("voc_template",)           # its verbs are SDSYS's; Solo's copy also has newvoc

HERE = os.path.dirname(os.path.abspath(__file__))
TREE = os.path.normpath(os.path.join(HERE, ".."))
SDSYS = os.path.join(TREE, "sdsys")
GPL = os.path.join(SDSYS, "gpl.bp")

SHARED_MESSAGES = list(range(13040, 13047))   # 13046 is Linux's: a relative path is refused

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


def read(path):
    if not os.path.isfile(path):
        return None
    with open(path, "rb") as f:
        return f.read().decode("latin-1").replace("\r\n", "\n")


def code_only(t):
    return "\n".join(l for l in t.split("\n") if not l.startswith("*"))


def config_problems(t):
    if not re.search(r'strncmp\(rec,\s*"BACKUPDIR=",\s*10\)\s*==\s*0', t):
        return ["config.c does not accept BACKUPDIR= - SD would not start on a file carrying it"]
    if "BACKUPDIR value is longer than" not in t:
        return ["config.c does not bound the BACKUPDIR value"]
    return []


def order_problems(name, t):
    """The question is asked BEFORE the login hold is taken."""
    c = code_only(t)
    a = c.find("acc_bakdir('USE'")
    h = c.find("acc_hold(ACCBAK$SET")
    if a < 0:
        return ["%s never asks !acc_bakdir for the directory" % name]
    if h < 0:
        return ["%s no longer takes the login hold (this test cannot judge the order)" % name]
    if a > h:
        return ["%s asks for the directory AFTER taking the login hold, so a refusal leaves it standing" % name]
    return []


def refs_problems(name, t, have):
    """Every sysmsg number a file names has a message file."""
    bad = []
    for m in sorted(set(int(x) for x in re.findall(r"sysmsg\((\d{4,5})", code_only(t)))):
        if m not in have:
            bad.append("%s names message %d, which has no file" % (name, m))
    return bad


def gcat_problems(t):
    """A Solo backup skips the global-catalogue matching - and assigns gcat.ids first.

    1 Oct 2026: the owner's first Solo backup printed "...@SDSYS/global.bp.out could not be read",
    because gcat.match walked a token-path VOC pointer.  The skip is the fix, and the assignment is
    what keeps the skip from aborting the verb: gcat.match reads gcat.ids, and a variable nothing
    has assigned aborts the program at run time, which no compiler warns about."""
    c = code_only(t)
    g = c.find("gosub gcat.load")
    if g < 0:
        return ["backupa no longer calls gcat.load, so this test cannot judge it"]
    line_start = c.rfind("\n", 0, g) + 1
    call_line = c[line_start:c.find("\n", g)]
    if "field(product, '-', 2) # 'solo'" not in call_line:
        return ["backupa runs the global-catalogue matching for a Solo product"]
    assign = re.search(r"gcat\.ids\s*=\s*''", c[:line_start])
    if not assign:
        return ["gcat.ids is not assigned before the skip, so a Solo backup would abort reading it"]
    return []


def stage_problems(t):
    if not re.search(r"'sd-backupdir\.ps1'", t):
        return ["stage.py does not ship sd-backupdir.ps1"]
    return []


def manifest_problems(t):
    m = re.search(r"^parse\.manifest:\n(.*?)\n", t, re.S | re.M)
    if not m or m.group(1).strip().split(";")[0].strip() != "mtext = convert(char(13), '', mtext)":
        return ["parse.manifest does not drop the CRs first (Linux measured a CRLF manifest refused)"]
    return []


print("test-bakdir-units: %s" % PRODUCT)
print("test-bakdir-units: reading " + TREE)
cfg = read(os.path.join(TREE, "gplsrc", "config.c"))
stage = read(os.path.join(TREE, "gplbld", "stage.py"))
files = {n: read(os.path.join(GPL, n)) for n in ("setbakdir", "acc_bakdir", "acc_os_bakdir", "backupa", "restorea")}
if cfg is None or stage is None or any(v is None for v in files.values()):
    missing = [n for n, v in files.items() if v is None]
    print("test-bakdir-units: not found: %s - nothing measured." % ", ".join(missing + ([] if cfg else ["config.c"]) + ([] if stage else ["stage.py"])))
    sys.exit(2)

have = set(int(n) for n in os.listdir(os.path.join(SDSYS, "messages")) if n.isdigit())

check("CONTROL: every program this test reads was found and has code", all(len(code_only(v)) > 100 for v in files.values()))
for n in SHARED_MESSAGES + [OS_MESSAGE]:
    p = os.path.join(SDSYS, "messages", str(n))
    t = read(p)
    check("message %d exists and has text" % n, t is not None and len(t.strip()) > 5)
for n in ("setbakdir", "acc_bakdir", "acc_os_bakdir", "backupa", "restorea"):
    bad = refs_problems(n, files[n], have)
    check("every message %s names has a file" % n, bad == [], "; ".join(bad))

check("the scripts exist", os.path.isfile(os.path.join(TREE, "gplbld", "sd-backupdir.ps1")))
p = stage_problems(stage)
check("stage.py ships sd-backupdir.ps1", p == [], "; ".join(p))
p = config_problems(cfg)
check("config.c accepts and bounds BACKUPDIR", p == [], "; ".join(p))
for layer in VOC_LAYERS:
    t = read(os.path.join(SDSYS, layer, "set.backup.directory"))
    # 7 Oct 26 - the VOC record's catalogue name is lower case now (the standard, and what the
    # catalogue holds since RELEASE_1.1 5 stage 3a), so the comparison ignores case.
    check("%s/set.backup.directory points at the catalogued verb" % layer, t is not None and t.strip().split("\n")[-1].strip().lower() == "$setbakdir")
if "newvoc" not in VOC_LAYERS:
    check("the verb is NOT in newvoc (that is every account's VOC; this is an administrator verb here)",
          not os.path.isfile(os.path.join(SDSYS, "newvoc", "set.backup.directory")))
check("the verb's catalogue name matches its VOC record", "$catalog $setbakdir" in files["setbakdir"].lower())
check("the shared helper is catalogued as !acc_bakdir and the per-OS one as !acc_os_bakdir",
      "$catalog !acc_bakdir" in files["acc_bakdir"] and "$catalog !acc_os_bakdir" in files["acc_os_bakdir"])
check("the per-OS helper refuses a relative path with the shared message 13046", "err = 13046" in code_only(files["acc_os_bakdir"]))
check("the per-OS helper runs the script it ships", "/sd-backupdir.ps1" in code_only(files["acc_os_bakdir"]))
for n in ("backupa", "restorea"):
    p = order_problems(n, files[n])
    check("%s asks for the directory before it takes the login hold" % n, p == [], "; ".join(p))
p = manifest_problems(files["restorea"])
check("restorea's parse.manifest drops CR first", p == [], "; ".join(p))
check("restorea asks only for a BARE archive name and refuses (never prompts) under NO.QUERY",
      "acc_bakdir('USE', not(no.query)" in code_only(files["restorea"]))
check("backupa still has a syntax message for a missing name list (TO is optional, names are not)",
      "stop sysmsg(13006)" in code_only(files["backupa"]))

p = gcat_problems(files["backupa"])
check("backupa skips the global-catalogue matching for a Solo product and assigns gcat.ids first", p == [], "; ".join(p))

# MUTANTS on synthetic text.
check("MUTANT: running the matching for every product (the 1 Oct 2026 warning) is caught",
      gcat_problems("   gcat.ids = ''\n   gosub gcat.load\n") != [])
check("MUTANT: the skip WITHOUT the earlier assignment (it would abort at run time) is caught",
      gcat_problems("   if field(product, '-', 2) # 'solo' then gosub gcat.load\n") != [])
check("CONTROL: the skip with the assignment first passes",
      gcat_problems("   gcat.ids = '' ; gcat.times = ''\n   if field(product, '-', 2) # 'solo' then gosub gcat.load\n") == [])
check("MUTANT: a config.c without the BACKUPDIR branch is caught",
      config_problems('else if (strncmp(rec, "SDSYS=", 6) == 0) {}') != [])
check("MUTANT: asking AFTER the hold is caught",
      order_problems("x", "   call !acc_hold(ACCBAK$SET, others, err)\n   call !acc_bakdir('USE', @true, dest, err)\n") != [])
check("CONTROL: asking before the hold passes",
      order_problems("x", "   call !acc_bakdir('USE', @true, dest, err)\n   call !acc_hold(ACCBAK$SET, others, err)\n") == [])
check("MUTANT: a message number with no file is caught", refs_problems("x", "   stop sysmsg(13999)\n", {13040}) != [])
check("MUTANT: a stage.py without the script is caught", stage_problems("'sd-account-archive.ps1',") != [])
check("MUTANT: parse.manifest without the CR line is caught", manifest_problems("parse.manifest:\n   bad = ''\n") != [])
check("CONTROL: parse.manifest with the CR line passes",
      manifest_problems("parse.manifest:\n   mtext = convert(char(13), '', mtext)   ;* x\n   bad = ''\n") == [])

print("")
if passes == 0:
    print("test-bakdir-units: VOID - no check ran.")
    sys.exit(2)
if failures:
    print("test-bakdir-units: %d passed, %d failed." % (passes, failures))
    sys.exit(1)
print("test-bakdir-units: %d passed, 0 failed." % passes)
sys.exit(0)
