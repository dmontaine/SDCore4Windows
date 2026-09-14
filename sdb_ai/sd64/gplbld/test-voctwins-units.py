"""RELEASE_1.1 5 D2 - the shipped data holds no two ids differing only by case.

WHY THIS EXISTS.  The kernel now makes every hashed file case insensitive
(gplsrc/op_dio1.c), so on a FRESH install no VOC or dictionary can hold a pair
of ids that fold together - the second write is the first record.  But the
shipped SOURCE that is loaded into those files is plain text on disk
(sdsys/newvoc, sdsys/voc_template, and the dictionary field lists in
gplbld/FILES_DICTS), where nothing stops two records naming ids that fold to
one.  If a pair were shipped, the install would silently load one and drop the
other - exactly the loss the kernel change prevents at runtime but cannot
prevent in the source.  This is the guard over the source.

It is a data check, so it needs no SD, no install, no elevation and no cycle.
It reads the three trees and reports any collision; a copy with a planted twin
is the mutant control, so a clean run is trustworthy (section 0 instrument
rule: a check that cannot fail proves nothing).

  python gplbld/test-voctwins-units.py

Exit 0 all checks passed, 1 a check failed.
"""

import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SDSYS = os.path.normpath(os.path.join(HERE, os.pardir, "sdsys"))
NEWVOC = os.path.join(SDSYS, "newvoc")
VOCTMPL = os.path.join(SDSYS, "voc_template")
FILES_DICTS = os.path.join(HERE, "FILES_DICTS")

passed = 0
failed = 0


def check(label, ok, detail=""):
    global passed, failed
    if ok:
        passed += 1
        print("  [PASS] " + label)
    else:
        failed += 1
        print("  [FAIL] " + label + ("  " + detail if detail else ""))


def collisions(names):
    """Return a sorted list of (lower, [names...]) for ids that fold together."""
    groups = {}
    for n in names:
        groups.setdefault(n.lower(), []).append(n)
    return sorted((k, v) for k, v in groups.items() if len(v) > 1)


def voc_names(directory):
    """Record ids in a VOC-shaped directory file: one OS file per id."""
    return [e for e in os.listdir(directory)
            if os.path.isfile(os.path.join(directory, e))]


def dict_field_pairs():
    """(dictfile, field) pairs from FILES_DICTS, whose records are named
    '<dictfile>^<field>'.  A twin is two fields of one dict that fold."""
    by_dict = {}
    for e in os.listdir(FILES_DICTS):
        if not os.path.isfile(os.path.join(FILES_DICTS, e)):
            continue
        if "^" not in e:
            continue
        dfile, field = e.split("^", 1)
        by_dict.setdefault(dfile, []).append(field)
    return by_dict


print("test-voctwins-units: the shipped VOC and dictionary source hold no")
print("  two ids differing only by case.")
print("  newvoc  " + NEWVOC)
print("  voc_tpl " + VOCTMPL)
print("  dicts   " + FILES_DICTS)

# --- controls: the reader actually finds a collision when one is present ---
check("CONTROL: collisions() spots a planted fold-twin",
      collisions(["TYPE", "type", "keep"]) == [("type", ["TYPE", "type"])],
      "the detector did not report the obvious pair")
check("CONTROL: collisions() passes a clean set",
      collisions(["a", "B", "c9"]) == [],
      "the detector cried twin on distinct ids")

# --- the real trees ---
nv = voc_names(NEWVOC)
vt = voc_names(VOCTMPL)
check("CONTROL: newvoc has a full VOC (300+ records)", len(nv) >= 300,
      "found %d - is the path right?" % len(nv))
check("CONTROL: voc_template has a full VOC (300+ records)", len(vt) >= 300,
      "found %d" % len(vt))

c = collisions(nv)
check("newvoc: no two ids fold together (%d records)" % len(nv),
      c == [], "twins: " + repr(c))
c = collisions(vt)
check("voc_template: no two ids fold together (%d records)" % len(vt),
      c == [], "twins: " + repr(c))

by_dict = dict_field_pairs()
check("CONTROL: FILES_DICTS parsed into dictionaries (5+)", len(by_dict) >= 5,
      "found %d" % len(by_dict))
bad = []
total_fields = 0
for dfile, fields in sorted(by_dict.items()):
    total_fields += len(fields)
    c = collisions(fields)
    if c:
        bad.append((dfile, c))
check("FILES_DICTS: no dictionary has two fields that fold (%d dicts, %d fields)"
      % (len(by_dict), total_fields),
      bad == [], "twins: " + repr(bad))

# The mutant: a planted twin field in a real dictionary's field list must be
# caught.  Take the first dictionary's first field and add a spelling of it
# that folds to it but is not identical.
some_dict = sorted(by_dict)[0]
f0 = by_dict[some_dict][0]
if f0.upper() != f0:
    twin = f0.upper()
elif f0.lower() != f0:
    twin = f0.lower()
else:
    twin = f0 + "z"          # f0 is caseless (e.g. "@"); pair two new spellings
mfields = list(by_dict[some_dict]) + [twin]
if twin == f0 + "z":
    mfields += [f0 + "Z"]
check("MUTANT: a planted fold-twin field in %s is caught" % some_dict,
      collisions(mfields) != [], "the detector missed the planted twin")

print("")
print("test-voctwins-units: %d passed, %d failed." % (passed, failed))
sys.exit(1 if failed else 0)
