#!/usr/bin/env python3
"""test-aipass-units.py - RELEASE_1.1 386: a key the AI line has no use for is the page's.

The owner, 22 Nov 2026: "i can not quit the page while the cursor is in the ai line", "ctrl T does not work
either", "however mouse clicks work - let's fix it".  While the line had the focus every key but F6 went to it,
and $sl_entry dropped the ones it does not use (Ctrl-Q, Ctrl-T, F1, F10 ...).  Now:

  P1  tk_ai on.key: after $sl_entry 'key', ret<1> = 'unhandled' takes the focus away and answers out 'pass'
  P2  tk_aipage 'key': ko = 'pass' leaves out null, so the page's bar and own keys see the key
  P3  tool_home ai.key: out = 'pass' gives the focus back (aif = 0) and keeps the key (ai.again); the loop takes it before
      reading a new one, so the menu bar and on.key see it on their one path
  P4  control: sl_entry still answers 'unhandled' for a key it has no use for (the case the rule depends on)

Reads source only; prints what it read; a file it cannot find is a failure, never a pass.
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
BP = os.path.join(os.path.dirname(HERE), 'sdsys', 'gpl.bp')


def read(name):
    p = os.path.join(BP, name)
    print('  reading', p)
    if not os.path.isfile(p):
        return None
    with open(p, 'rb') as f:
        return f.read().decode('utf-8', 'replace').replace('\r\n', '\n')


def block(text, label, end_pat):
    """the lines from 'label:' to the next line matching end_pat"""
    m = re.search(r'(?m)^' + re.escape(label) + r':\s*$', text)
    if not m:
        return ''
    rest = text[m.end():]
    e = re.search(end_pat, rest, re.M)
    return rest[:e.start()] if e else rest


def main():
    fails = 0
    rows = 0

    def check(row, ok, what):
        nonlocal fails, rows
        rows += 1
        print('  [%s] %s  %s' % ('PASS' if ok else 'FAIL', row, what))
        if not ok:
            fails += 1

    tk_ai = read('tk_ai')
    tk_aipage = read('tk_aipage')
    home = read('tool_home')
    entry = read('sl_entry')
    if None in (tk_ai, tk_aipage, home, entry):
        print('FAIL: a source file is missing; nothing was checked')
        return 1

    ok_ = block(tk_ai, 'on.key', r'^return\s*$|^   return\s*$')
    print('  tk_ai on.key: %d lines' % ok_.count('\n'))
    check('P1', bool(re.search(r"\$sl_entry\('key', ai\.w, scr, nm, r\)[\s\S]*?if r<1> = 'unhandled' then\s*(;\*[^\n]*)?\n\s*ai\.focus = 0\s*\n\s*gosub paint\s*\n\s*b = 'pass'", ok_)),
          "tk_ai on.key: 'unhandled' -> ai.focus = 0, paint, b = 'pass'")

    m = re.search(r"case op = 'key'[\s\S]*?end case", tk_aipage)
    kp = m.group(0) if m else ''
    print('  tk_aipage key op: %d lines' % kp.count('\n'))
    check('P2', bool(re.search(r"case ko = 'pass'\s*\n\s*out = ''", kp)), "tk_aipage 'key': case ko = 'pass' -> out = ''")

    ak = block(home, 'ai.key', r'^   return\s*$')
    print('  tool_home ai.key: %d lines' % ak.count('\n'))
    m = re.search(r"case out = 'pass'([\s\S]*?)(\n\s*case |\n\s*end case)", ak)
    pb = m.group(1) if m else ''
    check('P3a', 'aif = 0' in pb and 'ai.again = nm' in pb, "tool_home ai.key 'pass': aif = 0, and the key is kept in ai.again")
    lp = home[home.find('\n   loop\n'):home.find('\n   gosub finish\n')]
    print('  tool_home loop: %d lines' % lp.count('\n'))
    check('P3b', bool(re.search(r"nm = ''\s*\n\s*if ai\.again # '' then\s*\n\s*nm = ai\.again[^\n]*\n\s*ai\.again = ''\s*\n\s*end else\s*\n\s*screen key timeout 30 returning nm", lp))
          and lp.find('nm = ai.again') < lp.find("call $tk_menubar('key'"),
          "tool_home loop: the kept key is taken before a new one is read, ahead of the menu bar and on.key")
    check('P3c', "ai.again = ''" in home[:home.find('\n   loop\n')], "tool_home: ai.again starts empty")

    check('P4', bool(re.search(r"case 1\s*\n\s*ret = 'unhandled'", entry)), "sl_entry: a key it has no use for is 'unhandled'")

    print('test-aipass-units: %d rows, %d failed' % (rows, fails))
    return 1 if fails else 0


if __name__ == '__main__':
    sys.exit(main())
