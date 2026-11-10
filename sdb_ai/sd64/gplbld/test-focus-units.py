#!/usr/bin/env python3
# test-focus-units.py - the form's focus service, read off the source as text (S.88 p3.6, 30 Oct 2026; owner decision 6 of 29 Oct).
#
# The rule it holds: the form's focus is always on a widget that can have it, or on none.  A widget CAN have the focus (can.focus) when it takes keys, is not disabled, is not inside
# a container that is disabled, and is on the page the form shows and not hidden.
#   F1  the op 'focus' answers ret 1 until the focus moved; on a SHOWN form it asks can.focus first (the target must be on the page, visible and enabled), on a form that is not shown it
#       moves the pointer and the flags only (fpaint 0) and asks the weak test (focusable, not disabled itself)
#   F2  set.focus draws the widget that LOSES the focus only when fpaint is on and the widget is on the page and not hidden (a hidden one was drawn over what the page shows now); the
#       widget that gains it is drawn only when fpaint is on; f{'nofocus'} is cleared
#   F3  fix.focus: nothing when the focus is right; else the next widget that can have it, round the ring from the old one; else none (f{'focus'} = 0, f{'nofocus'} = 1) with the old
#       widget told it lost the focus (drawn only when fpaint and visible)
#   F4  the op 'redraw' makes the focus right BEFORE it lays out and draws (fpaint 0 round fix.focus, 1 again after); the op 'recheck' does init.page and fix.focus and draws nothing else
#   F5  route.key asks can.focus of the focused widget before the widget gets the key; a stale focus goes to stale.key, which lets Tab, Shift-Tab, Up, Down and Esc through to other.key,
#       swallows every other key with a bell (decision 6b) and never calls a widget
#   F6  park.cursor hides the cursor when the form has no focus because fix.focus found no widget (f{'nofocus'}), and only then
#   F7  route.mouse asks can.focus (it used to repeat its conditions)
#   F8  SCREEN FOCUS (screen_focus) on a shown form that is not a phantom: the widget that has the focus is no move (status 0, nothing drawn); another goes through $sl_form 'focus'
#       between $sl_scr get and put and the status is the op's answer; a form that is not shown only sets the pointer
#   F9  SCREEN SET (screen_set) tells a QUIET shown form to 'recheck' after ENABLED, VISIBLE or a tab strip's VALUE (bits 8 + 64 and VALUE of a 'tabs'), between $sl_scr get and put; the
#       form that is not quiet is covered by 'redraw'
#   F10 sl_form writes to the terminal in three places only: the cursor off, the cursor on, and the bell of stale.key (test-escdata-units pins the number)
#   F11 the 'focus' EVENT for a focus move the program caused is NOT built (owner decision 6c: droppable; it would add an event to programs that have none now)
#
# FREE CHECK: no install, no sd.     python3 .../test-focus-units.py        python3 .../test-focus-units.py --selftest [--from=N]
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
BP = os.environ.get("BPDIR", os.path.normpath(os.path.join(HERE, "..", "sdsys", "gpl.bp")))
FILES = {n: os.path.join(BP, n) for n in ("sl_form", "screen_focus", "screen_set")}


def read(p):
    with open(p, encoding="latin-1") as f:
        return f.read()


def code(t):
    out = []
    for ln in t.split("\n"):
        s = ln.lstrip()
        if s.startswith("*") or not s.strip():
            continue
        out.append(re.sub(r"\s*;\*.*$", "", ln).rstrip())
    return "\n".join(out)


def ordered(t, *needles):
    pos = -1
    for n in needles:
        i = t.find(n, pos + 1)
        if i < 0:
            return False
        pos = i
    return True


def label(src, name):
    """The lines of a label's routine: from `name:` at column 0 to the next label at column 0 (or the end of the code)."""
    m = re.search(r"(?m)^%s:\n" % re.escape(name), src)
    if not m:
        return ""
    rest = src[m.end():]
    n = re.search(r"(?m)^[A-Za-z][A-Za-z0-9.]*:$", rest)
    return rest[:n.start()] if n else rest


def op(src, name):
    """The body of `case op = 'name'` in sl_form: up to the next case op."""
    m = re.search(r"(?m)^      case op = '%s'\n" % re.escape(name), src)
    if not m:
        return ""
    rest = src[m.end():]
    n = re.search(r"(?m)^      case op = ", rest)
    e = rest.find("   end case")
    cut = min(x for x in (n.start() if n else len(rest), e if e >= 0 else len(rest)))
    return rest[:cut]


def load():
    return {k: read(p) for k, p in FILES.items()}


def checks(s):
    rows = []

    def ck(name, ok, detail=""):
        rows.append((name, bool(ok), detail))

    sf = code(s["sl_form"])
    sfo = code(s["screen_focus"])
    sst = code(s["screen_set"])

    of = op(sf, "focus")
    ck("F1 the op 'focus' answers 1 until the focus moved; on a shown form it asks can.focus (i = fw) before set.focus, on a form that is not shown it moves the pointer and flags only (fpaint 0) after the weak test",
       "ret = 1" in of and ordered(of, "if f{'shown'} then", "i = fw", "gosub can.focus", "if cf then", "gosub set.focus", "ret = 0", "end else",
                                   "w{'focusable'} + 0 = 1 and w{'disabled'} + 0 = 0", "fpaint = 0", "gosub set.focus", "fpaint = 1", "ret = 0"), of[:300])

    sfc = label(sf, "set.focus")
    ck("F2 set.focus draws the widget that loses the focus only when fpaint and it is on the page and visible (else focused = 0), clears nofocus, and draws the new one only when fpaint",
       ordered(sfc, "gosub on.page", "if fpaint and vis then", "gosub call.widget", "end else", "w{'focused'} = 0", "f{'focus'} = ni", "f{'nofocus'} = 0", "if fpaint then",
               "gosub reveal", "wop = 'focus' ; wkey = 1", "gosub call.widget", "gosub park.cursor", "end else", "w{'focused'} = 1")
       and "wop = 'focus' ; wkey = 0\n      gosub on.page" in sfc, sfc[:300])

    fx = label(sf, "fix.focus")
    ck("F3 fix.focus: returns when the focus can be had, takes the next that can (round the ring from the old one), else none (focus 0, nofocus 1), the old widget drawn only when fpaint and visible",
       ordered(fx, "fx.old = f{'focus'} + 0", "gosub can.focus", "if cf then return", "ni = 0", "i = fx.old", "for fx.k = 1 to nw", "i += 1", "if i > nw then i = 1", "gosub can.focus",
               "if cf then ni = i ; exit", "next fx.k", "if ni > 0 then", "gosub set.focus", "end else", "gosub on.page", "if fpaint and vis then", "gosub call.widget", "end else", "w{'focused'} = 0",
               "f{'focus'} = 0", "f{'nofocus'} = 1")
       and "if f{'nofocus'} + 0 = 0 then return" in fx, fx[:300])

    orr = op(sf, "redraw")
    orc = op(sf, "recheck")
    ck("F4 'redraw' makes the focus right before it lays out and draws (fpaint 0 round fix.focus), 'recheck' (shown only) is init.page and fix.focus and nothing that draws",
       ordered(orr, "gosub init.page", "fpaint = 0", "gosub fix.focus", "fpaint = 1", "gosub layout", "gosub draw.all")
       and ordered(orc, "if f{'shown'} then", "gosub init.page", "gosub fix.focus") and not any(w in orc for w in ("draw.all", "layout", "fpaint = 0", "call.widget")), orr[:200] + " / " + orc[:200])

    rk = label(sf, "route.key")
    sk = label(sf, "stale.key")
    ck("F5 route.key asks can.focus of the focused widget before it gives the widget the key; a stale focus goes to stale.key; stale.key lets tab btab up down esc through to other.key, rings the bell for "
       "every other key and never calls a widget",
       ordered(rk, "fi = f{'focus'} + 0", "i = fi", "gosub can.focus", "if cf = 0 then", "gosub stale.key", "return", "w = f{'widgets', fi}", "wop = 'key' ; wkey = key", "gosub call.widget")
       and ordered(sk, "case key = 'tab' or key = 'down' or key = 'btab' or key = 'up' or key = 'esc'", "k2 = key", "gosub other.key", "case 1", "display char(7) :", "ret = 'handled'")
       and "call.widget" not in sk and "enter" not in sk, sk[:300])

    pc = label(sf, "park.cursor")
    ck("F6 park.cursor hides the cursor for a form without a focus only when fix.focus found nothing (f{'nofocus'}), not for every focusless form",
       ordered(pc, "if pfi >= 1 and pfi <= nw then", "end else", "if pfi < 1 then phide = f{'nofocus'} + 0", "if phide then"), pc[:300])

    rm = label(sf, "route.mouse")
    ck("F7 route.mouse asks can.focus (the same test as Tab and the accelerators) and does not repeat the conditions",
       ordered(rm, "for i = nw to 1 step -1", "gosub can.focus", "if cf then", "if mx >= w{'ax'}") and "w{'disabled'} + 0 = 0 and ancdis = 0" not in rm, rm[:200])

    ck("F8 screen_focus on a shown form that is not a phantom: the same widget is no move (status 0, before any $sl_scr or $sl_form call), another goes through $sl_form 'focus' between $sl_scr get and put "
       "with the status of the op; a form that is not shown only sets the pointer",
       ordered(sfo, "if f{'shown'} and not(system(25)) then", "if f{'focus'} + 0 = n then", "status = 0", "return", "end", "call $sl_scr('get', scr)", "call $sl_form('focus', f, scr, id, r)",
               "call $sl_scr('put', scr)", "status = r + 0", "return", "end", "f{'focus'} = n", "status = 0"), sfo[-400:])

    ck("F9 screen_set tells a shown, non-phantom, QUIET form to 'recheck' after ENABLED (8), VISIBLE (64) or a tab strip's VALUE, between $sl_scr get and put, after the redraw of the form that is not quiet",
       ordered(sst, "call $sl_form('redraw', f, scr, '', r)", "if f{'shown'} and not(system(25)) and f{'quiet'} + 0 and (bitand(given, 72) or (wt = 'tabs' and bitand(given, 1))) then",
               "call $sl_scr('get', scr)", "call $sl_form('recheck', f, scr, '', r)", "call $sl_scr('put', scr)", "status = 0"), sst[-500:])

    nd = len(re.findall(r"(?m)^\s*display\b", sf))
    ck("F10 sl_form has three DISPLAY statements: the cursor off (park.cursor), the cursor on (show.cursor) and the bell of stale.key", nd == 3 and sk.count("display") == 1, "%d display statements" % nd)

    ck("F11 no 'focus' event is made for a focus move the program caused (decision 6c dropped): sl_form holds no fnote", "fnote" not in sf and "fnote" not in sst and "fnote" not in sfo, "")
    ck("F12 fpaint is 1 at the top of every call, before the op is chosen, and is set to 0 only in the three places that put it back", ordered(sf, "wkey = ''", "fpaint = 1", "begin case")
       and len(re.findall(r"fpaint = 0", sf)) == 2 and len(re.findall(r"fpaint = 1", sf)) == 3, "%d zeros, %d ones" % (len(re.findall(r"fpaint = 0", sf)), len(re.findall(r"fpaint = 1", sf))))
    return rows


def sub(src, old, new):
    if src.count(old) != 1:
        raise SystemExit("selftest: the old text occurs %d times, not once:\n%s" % (src.count(old), old[:120]))
    return src.replace(old, new)


MUTANTS = [
    ("the op focus says 0 for a target that cannot have it", "sl_form", "               if cf then\n                  gosub set.focus\n                  ret = 0\n               end", "               gosub set.focus\n               ret = 0", "F1"),
    ("the op focus on a shown form does not ask can.focus", "sl_form", "               i = fw\n               gosub can.focus               ;* on a shown form", "               cf = 1\n               gosub can.focus               ;* on a shown form", "F1"),
    ("an unshown form is drawn into", "sl_form", "                  fpaint = 0                 ;* nothing is on the screen: the pointer and the flags\n", "", "F1"),
    ("a hidden widget that loses the focus is drawn", "sl_form", "      if fpaint and vis then\n         gosub call.widget\n      end else\n         w{'focused'} = 0\n      end\n   end\n   f{'focus'} = ni", "      gosub call.widget\n   end\n   f{'focus'} = ni", "F2"),
    ("set.focus forgets nofocus", "sl_form", "   f{'nofocus'} = 0\n   w = f{'widgets', ni}", "   w = f{'widgets', ni}", "F2"),
    ("set.focus draws the new widget with fpaint 0", "sl_form", "   if fpaint then\n      if w{'pn'} + 0 > 0 and f{'shown'} then", "   if 1 then\n      if w{'pn'} + 0 > 0 and f{'shown'} then", "F2"),
    ("fix.focus always moves the focus", "sl_form", "      gosub can.focus\n      if cf then return\n   end else", "      gosub can.focus\n   end else", "F3"),
    ("fix.focus starts the scan at the top, not after the old widget", "sl_form", "   ni = 0\n   i = fx.old\n   if i < 0 or i > nw then i = 0\n", "   ni = 0\n   i = 0\n", "F3"),
    ("fix.focus leaves the pointer on a widget that cannot have it", "sl_form", "      f{'focus'} = 0\n      f{'nofocus'} = 1", "      f{'nofocus'} = 1", "F3"),
    ("redraw draws before the focus is made right", "sl_form", "            fpaint = 0                       ;* the whole form is drawn below: the flags are made right first, no widget drawn twice\n            gosub fix.focus\n            fpaint = 1\n            gosub layout\n            gosub draw.all", "            gosub layout\n            gosub draw.all\n            fpaint = 0\n            gosub fix.focus\n            fpaint = 1", "F4"),
    ("recheck draws the whole form", "sl_form", "      case op = 'recheck'\n         if f{'shown'} then\n            gosub init.page\n            gosub fix.focus\n", "      case op = 'recheck'\n         if f{'shown'} then\n            gosub init.page\n            gosub fix.focus\n            gosub draw.all\n", "F4"),
    ("a stale focus still gets the key", "sl_form", "   if cf = 0 then\n      gosub stale.key                            ;* 30 Oct 26", "   if 0 then\n      gosub stale.key                            ;* 30 Oct 26", "F5"),
    ("a stale focus passes Enter on", "sl_form", "key = 'btab' or key = 'up' or key = 'esc'\n         k2 = key", "key = 'btab' or key = 'up' or key = 'esc' or key = 'enter'\n         k2 = key", "F5"),
    ("a stale focus gives the key to the widget", "sl_form", "      case 1\n         display char(7) :\n         ret = 'handled'", "      case 1\n         wop = 'key' ; wkey = key\n         gosub call.widget\n         ret = 'handled'", "F5"),
    ("the cursor is hidden for every form without a focus", "sl_form", "      if pfi < 1 then phide = f{'nofocus'} + 0", "      if pfi < 1 then phide = 1", "F6"),
    ("route.mouse repeats the conditions again", "sl_form", "   for i = nw to 1 step -1\n      gosub can.focus\n      if cf then\n         if mx >= w{'ax'}", "   for i = nw to 1 step -1\n      w = f{'widgets', i}\n      gosub on.page\n      if vis and w{'disabled'} + 0 = 0 and ancdis = 0 then\n         if mx >= w{'ax'}", "F7"),
    ("SCREEN FOCUS on the same widget draws", "screen_focus", "      if f{'focus'} + 0 = n then\n         status = 0\n         return\n      end\n", "", "F8"),
    ("SCREEN FOCUS says 0 whatever the op answered", "screen_focus", "      status = r + 0\n", "      status = 0\n", "F8"),
    ("SCREEN FOCUS on a form that is not shown draws", "screen_focus", "   if f{'shown'} and not(system(25)) then", "   if not(system(25)) then", "F8"),
    ("SCREEN SET rechecks after every clause", "screen_set", "f{'quiet'} + 0 and (bitand(given, 72) or (wt = 'tabs' and bitand(given, 1))) then", "f{'quiet'} + 0 then", "F9"),
    ("SCREEN SET never rechecks a quiet form", "screen_set", "call $sl_form('recheck', f, scr, '', r)", "null", "F9"),
    ("another display is added to sl_form", "sl_form", "         display char(7) :\n", "         display char(7) :\n         display char(7) :\n", "F10"),
    ("a focus event is noted", "sl_form", "      f{'focus'} = 0\n      f{'nofocus'} = 1", "      f{'focus'} = 0\n      f{'nofocus'} = 1\n      f{'fnote'} = 1", "F11"),
    ("fpaint is not set at the top", "sl_form", "   fpaint = 1                                ;* set.focus draws", "   null                                      ;* set.focus draws", "F12"),
]


def run(over=None):
    s = load()
    if over:
        s.update(over)
    return checks(s)


def selftest(first=0):
    base = run()
    bad0 = [n.split()[0] for n, ok, _ in base if not ok]
    print("selftest: the unchanged tree fails %d check(s): %s" % (len(bad0), " ".join(bad0) or "none"))
    if bad0:
        return 1
    s0 = load()
    bad = 0
    for name, key, old, new, want in MUTANTS[first:]:
        if s0[key].count(old) != 1:
            print("  [FAIL] selftest: %s: the old text occurs %d times in %s, not once" % (name, s0[key].count(old), key))
            bad += 1
            continue
        failed = [n.split()[0] for n, ok, _ in run({key: s0[key].replace(old, new)}) if not ok]
        hit = want in failed
        print("  [%s] selftest: %s is caught by %s (failed: %s)" % ("PASS" if hit else "FAIL", name, want, " ".join(failed) or "none"))
        bad += 0 if hit else 1
    print("selftest: %s" % ("every mutant was caught" if bad == 0 else "%d problem(s)" % bad))
    return 0 if bad == 0 else 1


def main(argv):
    for p in FILES.values():
        if not os.path.exists(p):
            print("test-focus-units: no such file %s" % p)
            return 2
    if "--selftest" in argv:
        first = 0
        for a in argv:
            if a.startswith("--from="):
                first = int(a[len("--from="):])
        return selftest(first)
    rows = run()
    bad = 0
    for n, ok, detail in rows:
        print("  [%s] %s%s" % ("PASS" if ok else "FAIL", n, "" if ok or not detail else "   <- " + detail[:300]))
        bad += 0 if ok else 1
    print("test-focus-units: %d checks, %d failed" % (len(rows), bad))
    return 0 if bad == 0 else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
