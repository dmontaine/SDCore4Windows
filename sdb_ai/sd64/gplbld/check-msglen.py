# check_msg_len.py - does a message fit k_error()'s buffer once sysmsg() has
# expanded it?  messages.c turns a literal backslash-n into LF followed by CR
# (two characters), and k_error writes at offset n after a "%08X: " prefix, so
# the room is sizeof(s) - n.
#
#   python sdb_ai/sd64/gplbld/check-msglen.py sdb_ai/sd64/sdsys/messages/10099
#
# 13 Nov 26 Windows: this file is Linux's again (8f005282, P.11), with this usage line; it replaces the 33-line form that had the bound written
# in (RELEASE_1.1 254, the test-subset audit's F4).  Its premises all read in this tree's gplsrc as they do in Linux's.
#
# Copied from SD Core for Windows (its gplbld/check-msglen.py) on the owner's
# instruction of 9 Sep 2026.  That copy hard-coded the bound 231 and would not
# say so if the source moved (PRE_RELEASE 11).  14 Sep 2026: the bound is now
# DERIVED from the C source every run, and each premise is printed with the
# file:line it was read from:
#   MAX_ERROR_LINES, MAX_EMSG_LEN   gplsrc/sddefs.h
#   char s[(MAX_ERROR_LINES * MAX_EMSG_LEN) + 1]    gplsrc/k_error.c
#   n = sprintf(s, "%08X: ", ...)                   gplsrc/k_error.c
#   vsnprintf(&(s[n]), sizeof(s) - n, ...)          gplsrc/k_error.c (D1 fix)
#   case 'n': *p = '\n'; *(p+1) = '\r';             gplsrc/messages.c
# ANY PREMISE NOT FOUND IN THE SOURCE IS A REFUSAL (exit 2), not a guess.
#
# The bound is compiled in, so no unit test could have caught the defect this
# exists for; in the port it was found by measuring a message that came back
# cut mid-word.  Note the refusal at the end: a run that substituted no escapes
# measured nothing and exits 2 rather than passing.
import os
import re
import sys

BS_N = chr(92) + 'n'          # a literal backslash followed by n
LFCR = chr(10) + chr(13)      # what messages.c substitutes for it

SD64 = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GPLSRC = os.path.join(SD64, 'gplsrc')


def refuse(why):
    print('REFUSED: %s' % why)
    sys.exit(2)


def find(fname, pattern):
    """Return (match, 'file:line') for the first line matching pattern."""
    path = os.path.join(GPLSRC, fname)
    try:
        lines = open(path, 'rb').read().decode('latin-1').split('\n')
    except OSError as e:
        refuse('cannot read %s: %s' % (path, e))
    for i, line in enumerate(lines):
        m = re.search(pattern, line)
        if m:
            return m, lines, i, 'gplsrc/%s:%d' % (fname, i + 1)
    refuse('premise not found in gplsrc/%s: /%s/' % (fname, pattern))


def derive_bound():
    m, _, _, at_lines = find('sddefs.h', r'^#define\s+MAX_ERROR_LINES\s+(\d+)\b')
    max_lines = int(m.group(1))
    m, _, _, at_len = find('sddefs.h', r'^#define\s+MAX_EMSG_LEN\s+(\d+)\b')
    max_len = int(m.group(1))
    _, _, _, at_buf = find(
        'k_error.c',
        r'^\s*char\s+s\[\(MAX_ERROR_LINES\s*\*\s*MAX_EMSG_LEN\)\s*\+\s*1\]\s*;')
    size = max_lines * max_len + 1
    m, _, _, at_pfx = find('k_error.c',
                           r'\bn\s*=\s*sprintf\(s,\s*"([^"]*)"\s*,\s*failing_offset\s*\)')
    try:
        prefix = len(m.group(1) % 0)
    except (TypeError, ValueError):
        refuse('%s: prefix format %r does not take one integer'
               % (at_pfx, m.group(1)))
    _, _, _, at_d1 = find('k_error.c',
                          r'vsnprintf\(&\(s\[n\]\),\s*sizeof\(s\)\s*-\s*n\s*,')
    _, lines, i, at_nl = find('messages.c', r"case\s+'n'\s*:")
    window = '\n'.join(lines[i:i + 4])
    if not (re.search(r"\*p\s*=\s*'\\n'\s*;", window)
            and re.search(r"\*\(p\s*\+\s*1\)\s*=\s*'\\r'\s*;", window)):
        refuse("%s: backslash-n is no longer replaced by LF then CR in place"
               % at_nl)
    print('premises (read from the source this run):')
    print('  MAX_ERROR_LINES = %-4d %s' % (max_lines, at_lines))
    print('  MAX_EMSG_LEN    = %-4d %s' % (max_len, at_len))
    print('  sizeof(s)       = %-4d %s' % (size, at_buf))
    print('  prefix bytes    = %-4d %s' % (prefix, at_pfx))
    print('  room            = sizeof(s) - n   %s' % at_d1)
    print('  \\n -> LF CR     = 2    %s' % at_nl)
    return size - prefix, max_lines


if len(sys.argv) != 2:
    print('usage: python3 %s <message file>' % os.path.abspath(__file__))
    sys.exit(2)

BOUND, MAX_LINES = derive_bound()

path = sys.argv[1]
raw = open(path, 'rb').read().decode('ascii')
if raw.endswith(chr(10)):
    raw = raw[:-1]

rendered = raw.replace(BS_N, LFCR).replace('%d', '3023')
lines = rendered.split(LFCR)

print('file            : %s' % os.path.abspath(path))
print('file bytes      : %d' % len(raw))
print('escapes found   : %d   (a 0 here would mean the check measured nothing)'
      % raw.count(BS_N))
print('rendered length : %d' % len(rendered))
print('bound           : %d' % BOUND)
print('fits            : %s' % (len(rendered) <= BOUND))
print('lines           : %d   (k_error is sized for %d)' % (len(lines), MAX_LINES))
for i, l in enumerate(lines):
    print('  %d (%2d chars) | %s' % (i + 1, len(l), l))

if raw.count(BS_N) == 0:
    print('REFUSED: no escapes were found, so nothing was substituted.')
    sys.exit(2)
sys.exit(0 if len(rendered) <= BOUND else 1)
