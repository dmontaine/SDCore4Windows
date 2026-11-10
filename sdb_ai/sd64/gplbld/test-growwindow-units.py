"""test-growwindow-units.py - SD grows a small CLASSIC console window to 140 by 43, and nothing else.

    python test-growwindow-units.py

Exit 0 all checks passed, 1 a check failed, 2 the guard could not run.  No install, no build, no elevation.

WHY IT EXISTS (RELEASE_1.1 215, 10 Nov 2026).  A console window opens at 120 by 30 and HOME, the IDE, CED and the
toolkit take 140 by 43 at least, so an account that starts in HOME was refused (Solo: the owner's paste) and on Core
signed out (S.164).  The owner chose "SD grows its window": gplsrc/win32vt.c grow_console_window(), called by
linuxio.c init_console().  Each condition below is one that, if lost, would resize a window SD has no business
resizing (a script's console, Windows Terminal's pseudo console) or shrink one the person made bigger, and none of
them shows up in a run on the developer's own machine, so they are held here.

WHAT IT READS (both files of THIS tree, never a copy):
  win32vt.c  grow_console_window(): input and output must both be a console; the window's class must be conhost's
             ConsoleWindowClass (Windows Terminal's pseudo console window is not); user32.dll is loaded at run time,
             so GetClassNameA is never called directly (sd.exe's import list stays as it is); the size is capped by
             GetLargestConsoleWindowSize; a dimension is never made smaller; the buffer grows before the window.
  linuxio.c  init_console() calls grow_console_window(140, 43) inside the CN_CONSOLE block, after
             enable_console_vt() and before the first read_window_size(), so LOGIN sees the grown window; and
             RELEASE_1.1 212's poll_window_size() asks console_window_cells() first, from console_resized() and
             console_window_size(), or the grown size would not be seen until the next key.

THE NULL CASE IS REFUSED: a file that is missing is exit 2; a function that cannot be found fails its checks; and
each MUTANT (the live text altered in memory, never on disk) must turn a named check red, or the guard is not looking.
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.normpath(os.path.join(HERE, '..', 'gplsrc'))
WIN = os.path.join(SRC, 'win32vt.c')
LIO = os.path.join(SRC, 'linuxio.c')

CALL = '(void)grow_console_window(140, 43);'
READ = 'if (read_window_size())'

passed = 0
failed = 0


def check(what, ok, detail=''):
    global passed, failed
    if ok:
        passed += 1
        print('  [PASS] ' + what)
    else:
        failed += 1
        print('  [FAIL] ' + what + (' - ' + detail if detail else ''))


def read(path):
    with open(path, 'rb') as fh:
        return fh.read().decode('utf-8', 'replace').replace('\r\n', '\n')


def body(text, head):
    """The text from `head` to the first line that is a lone closing brace, or '' if `head` is absent."""
    i = text.find(head)
    if i < 0:
        return ''
    j = text.find('\n}\n', i)
    return text[i:j + 3] if j >= 0 else ''


def faults(win, lio):
    """{check name: True if it holds} for one pair of texts."""
    out = {}
    g = body(win, 'int grow_console_window(int want_cols, int want_rows) {')
    out['grow_console_window is defined'] = bool(g)
    out['input must be a console'] = 'if (!GetConsoleMode(in, &mode))' in g and 'GetStdHandle(STD_INPUT_HANDLE)' in g
    out['output must be a console'] = 'if (!GetConsoleScreenBufferInfo(out, &info))' in g
    out['the window must be conhost\'s (ConsoleWindowClass), or nothing is done'] = \
        re.search(r'lstrcmpA\(cls, "ConsoleWindowClass"\) != 0\)\)\s*\n\s*return 0;', g) is not None
    out['user32 is loaded at run time; GetClassNameA is never called directly'] = \
        'LoadLibraryA("user32.dll")' in g and '"GetClassNameA"' in g and re.search(r'(?<!")\bGetClassNameA\s*\(', win) is None
    out['the size is capped by GetLargestConsoleWindowSize'] = \
        'GetLargestConsoleWindowSize(out)' in g and 'if (c > largest.X)' in g and 'if (n > largest.Y)' in g
    out['a dimension is never made smaller'] = \
        re.search(r'if \(c < cols\)\s*\n\s*c = cols;', g) is not None and re.search(r'if \(n < rows\)\s*\n\s*n = rows;', g) is not None
    sb = g.find('SetConsoleScreenBufferSize')
    sw = g.find('SetConsoleWindowInfo')
    out['the buffer grows before the window'] = 0 <= sb < sw

    ic = body(lio, 'bool init_console() {')
    blk = ic.find('if (connection_type == CN_CONSOLE) {')
    vt = ic.find('(void)enable_console_vt();')
    call = ic.find(CALL)
    rd = ic.find(READ)  # the call, not a comment's mention of the name
    out['init_console() calls grow_console_window(140, 43) in the CN_CONSOLE block, after enable_console_vt()'] = \
        0 <= blk < vt < call
    out['the call comes before the first read_window_size() in init_console()'] = 0 <= call < rd
    out['linuxio.c declares grow_console_window'] = 'int grow_console_window(int want_cols, int want_rows);' in lio
    p = body(lio, 'Private void poll_window_size() {')
    out['poll_window_size() asks console_window_cells() first'] = 'if (!console_window_cells(&c, &r)) {' in p
    out['console_resized() and console_window_size() ask poll_window_size()'] = \
        'poll_window_size();' in body(lio, 'Public bool console_resized() {') and \
        'poll_window_size();' in body(lio, 'Public bool console_window_size(cols, rows)')
    return out


print('test-growwindow-units: ' + WIN)
print('test-growwindow-units: ' + LIO)
for p in (WIN, LIO):
    if not os.path.isfile(p):
        print('test-growwindow-units: no ' + p)
        sys.exit(2)

win = read(WIN)
lio = read(LIO)
live = faults(win, lio)
for name in live:
    check('live: ' + name, live[name])
ic = body(lio, 'bool init_console() {')
print('  init_console(): %d characters; the call at offset %d, enable_console_vt() at %d, first "%s" at %d'
      % (len(ic), ic.find(CALL), ic.find('(void)enable_console_vt();'), READ, ic.find(READ)))


def mutant(label, w, l, must_fail):
    check('CONTROL: mutant "' + label + '" changed the text', (w, l) != (win, lio))
    res = faults(w, l)
    check('MUTANT "' + label + '" turns "' + must_fail + '" red', res.get(must_fail) is False, str(res.get(must_fail)))


mutant('no class test', re.sub(r'\n\s*if \(\(n <= 0\) \|\| \(lstrcmpA\(cls, "ConsoleWindowClass"\) != 0\)\)\s*\n\s*return 0;[^\n]*', '', win), lio,
       'the window must be conhost\'s (ConsoleWindowClass), or nothing is done')
mutant('no input test', win.replace('if (!GetConsoleMode(in, &mode))', 'if (0)'), lio, 'input must be a console')
mutant('shrinks', win.replace('if (c < cols)\n    c = cols;', ''), lio, 'a dimension is never made smaller')
mutant('direct GetClassNameA', win.replace('n = (class_name == NULL) ? 0 : class_name(w, cls, (int)sizeof(cls));',
                                           'n = GetClassNameA(w, cls, (int)sizeof(cls));'), lio,
       'user32 is loaded at run time; GetClassNameA is never called directly')
mutant('no call', win, lio.replace(CALL, ''),
       'init_console() calls grow_console_window(140, 43) in the CN_CONSOLE block, after enable_console_vt()')
moved = lio.replace(CALL, '', 1)
k = moved.find(READ, moved.find('bool init_console() {'))
e = moved.find('\n', k) if k >= 0 else -1
moved = moved[:e] + '\n    ' + CALL + moved[e:] if e >= 0 else moved  # on the line after the first read
mutant('call after the size is read', win, moved, 'the call comes before the first read_window_size() in init_console()')

print('')
if passed == 0:
    print('test-growwindow-units: VOID - no check ran.')
    sys.exit(2)
if failed:
    print('test-growwindow-units: FAILED - %d passed, %d failed.' % (passed, failed))
    sys.exit(1)
print('test-growwindow-units: PASSED - %d of %d checks passed.' % (passed, passed))
sys.exit(0)
