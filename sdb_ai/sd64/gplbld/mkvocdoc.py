#
# mkvocdoc.py - build the X-type VOC records CONFIG displays, from the two
# text files that ship in the data tree.
#
#   python mkvocdoc.py <sdsys-dir>          write the records
#   python mkvocdoc.py <sdsys-dir> --check  verify they match, write nothing
#
# WHY THERE ARE TWO COPIES AT ALL, AND WHY THAT IS NOT DRIFT WAITING TO HAPPEN.
# Owner, 26 Aug 2026: the text CONFIG shows should be INTERNAL to SD rather
# than a file it reaches out to.  So the display source is a VOC record.  But
# the plain file has to keep shipping as well, and for a reason that has
# nothing to do with convenience: SD is GPL-3, sdsys/licence is the only
# copy of the licence in the distribution, and sd.iss has no LicenseFile - so
# deleting it would leave a GPL program shipping no readable licence to anyone
# who has not started SD.  Three other things read it too: stage.py's ship
# list, test-upgradeiss-units.py's DECLARED_FILES, and verify-upgrade.ps1.
#
# THE FILE IS THE SOURCE AND THE RECORD IS GENERATED, so the two cannot
# disagree - and --check makes that assertable rather than remembered.
#
# WHY voc_template AND NOT newvoc.  voc_template is "the administrative
# superset; becomes SDSYS's own VOC" (stage.py's SDSYS_SHIP note); newvoc is
# what CREATEA copies into every account it makes.  A record placed here and
# NOT named in TIER.ADD.ADMINISTRATOR reaches SDSYS only.  The licence is
# 44 KB - in newvoc it would be copied into every account's VOC, and again by
# every UPDATE.ACCOUNT, for text nobody reads twice.
#
import os
import sys

SDSYS = sys.argv[1]
CHECK = '--check' in sys.argv[2:]

# file in the data tree  ->  VOC record in voc_template
PAIRS = [
    ('licence', '$licence'),
    ('contrib', '$contrib'),
]


def build(text):
    """An X-type VOC record: type in field 1, the text in the fields after it.

    A directory-file record stores a field mark as a newline, so the lines of
    the file ARE the fields of the record and nothing has to be escaped."""
    lines = text.split('\n')
    while lines and lines[-1] == '':
        lines.pop()
    return '\n'.join(['X'] + lines) + '\n'


bad = 0
for src_name, rec_name in PAIRS:
    src = os.path.join(SDSYS, src_name)
    dst = os.path.join(SDSYS, 'voc_template', rec_name)

    if not os.path.isfile(src):
        sys.exit('mkvocdoc: %s is missing - it is the source for %s'
                 % (src, rec_name))

    with open(src, 'r', encoding='latin-1', newline='') as f:
        text = f.read()
    if not text.strip():
        sys.exit('mkvocdoc: %s is empty - refusing to write an empty record'
                 % src)

    rec = build(text)

    if CHECK:
        have = ''
        if os.path.isfile(dst):
            with open(dst, 'r', encoding='latin-1', newline='') as f:
                have = f.read()
        if have == rec:
            print('  %-10s -> %-10s  matches  (%d fields, %d bytes)'
                  % (src_name, rec_name, rec.count('\n'), len(rec)))
        else:
            print('  %-10s -> %-10s  DIFFERS  - run mkvocdoc.py without '
                  '--check' % (src_name, rec_name))
            bad += 1
        continue

    # newline='' both ways: these files are LF and Windows text mode would
    # rewrite every line of the GPL as CRLF.
    with open(dst, 'w', encoding='latin-1', newline='') as f:
        f.write(rec)
    print('  %-10s -> %-10s  written  (%d fields, %d bytes)'
          % (src_name, rec_name, rec.count('\n'), len(rec)))

print('mkvocdoc: %s  %s' % (os.path.abspath(SDSYS),
                            'checked' if CHECK else 'written'))
sys.exit(1 if bad else 0)
