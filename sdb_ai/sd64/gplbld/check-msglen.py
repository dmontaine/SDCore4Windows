# check_msg_len.py - does a message fit k_error()'s buffer once sysmsg() has
# expanded it?  messages.c turns a literal backslash-n into LF followed by CR
# (two characters), and k_error writes at offset n after a 10-byte "%08X: "
# prefix, so the room is sizeof(s) - n = (3 * 80 + 1) - 10 = 231.
import sys

BS_N = chr(92) + 'n'          # a literal backslash followed by n
LFCR = chr(10) + chr(13)      # what messages.c substitutes for it
BOUND = (3 * 80 + 1) - 10

path = sys.argv[1]
raw = open(path, 'rb').read().decode('ascii')
if raw.endswith(chr(10)):
    raw = raw[:-1]

rendered = raw.replace(BS_N, LFCR).replace('%d', '3023')
lines = rendered.split(LFCR)

print('file            : %s' % path)
print('file bytes      : %d' % len(raw))
print('escapes found   : %d   (a 0 here would mean the check measured nothing)'
      % raw.count(BS_N))
print('rendered length : %d' % len(rendered))
print('bound           : %d' % BOUND)
print('fits            : %s' % (len(rendered) <= BOUND))
print('lines           : %d   (k_error is sized for %d)' % (len(lines), 3))
for i, l in enumerate(lines):
    print('  %d (%2d chars) | %s' % (i + 1, len(l), l))

if raw.count(BS_N) == 0:
    print('REFUSED: no escapes were found, so nothing was substituted.')
    sys.exit(2)
sys.exit(0 if len(rendered) <= BOUND else 1)
