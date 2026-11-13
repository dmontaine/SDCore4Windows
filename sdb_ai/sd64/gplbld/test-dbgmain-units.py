#!/usr/bin/env python3
"""test-dbgmain-units.py - the debugger's full-screen display on a terminal with no alternate screen (S.98 H3), read off the source as text.

  python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/test-dbgmain-units.py
  python3 .../test-dbgmain-units.py --selftest

No sudo, no install, no sd.  Exit 0 all checks passed, 1 a check failed, 2 it could not run.  Written 2 Nov 26.

THE RULES HELD HERE are the ones a screen cannot show: full.screen needs cup and clear (never smcup), and alt.able alone says whether there is an alternate screen; smcup and rmcup are
written only under alt.on / alt.screen / alt.able; the main screen is taken (take.main) only for a stop that is to be SHOWN, after the IDE's hand-over and a conditional WATCH may have sent the
program on, and given back (give.main) on every exit by ONE routine called after theme.out; give.main reads the kept context again, repaints an owned library screen and puts the context
back, and clears any other with the cursor shown; the debugger writes the kept context back in that one place only; F4 / V on the main screen repaints an owned screen in the program's theme
or says there is none (12602); LINE.MODE keeps line mode; and the terminal types are what the claims say (linux, vt100, vt102, vt220 and ansi have cup and clear and no smcup; dumb, unknown
and null have no cup).

***WHAT THIS IS AND IS NOT.***  It reads gpl.bp/debug, debug.h and terminfo.src as text.  It cannot say a screen is drawn or given back: that is sandbox-dbgmain.py, and for the real console
the VM witness.  --selftest mutates the sources one way per check and requires each mutant to be caught.
"""

import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, os.pardir))
FILES = {"debug": os.path.join(ROOT, "sdsys", "gpl.bp", "debug"), "debug.h": os.path.join(ROOT, "sdsys", "gpl.bp", "debug.h"),
         "terminfo.src": os.path.join(ROOT, "terminfo.src"), "msg": os.path.join(ROOT, "sdsys", "messages", "12602")}


def code(src):
    out = []
    for line in src.splitlines():
        if line.lstrip().startswith("*") or line.lstrip().startswith("!"):
            continue
        out.append(re.sub(r"\s;\*.*$", "", line).rstrip())
    return "\n".join(out)


def routine(text, name):
    m = re.search(r"(?m)^%s:[^\n]*\n(.*?)(?=^[A-Za-z][\w.]*:|\Z)" % re.escape(name), text, re.S)
    return m.group(1) if m else None


def pos(text, pat, start=0):
    m = re.compile(pat, re.M).search(text, start)
    return m.start() if m else -1


def entry(ti, name):
    """the capability text of the terminfo.src entry whose first name is `name`"""
    m = re.search(r"(?m)^%s[|,][^\n]*\n((?:[ \t]+[^\n]*\n)+)" % re.escape(name), ti)
    return m.group(1) if m else None


def checks(s):
    out = []

    def ck(name, ok, detail=""):
        out.append((name, bool(ok), detail))

    c = code(s["debug"])
    h = code(s["debug.h"])
    ini = routine(c, "initialise") or ""

    ck("F1 full.screen is assigned from K$WINSIZE, cup and clear, never from smcup; alt.able from smcup and rmcup",
       re.search(r"kernel\(K\$WINSIZE, ''\) # '' and terminfo\('cup'\) # '' and terminfo\('clear'\) # '' then\s*\n\s*full\.screen = @true\s*\n\s*alt\.able = \(terminfo\('smcup'\) # '' and terminfo\('rmcup'\) # ''\)", ini)
       and not re.search(r"full\.screen = .*smcup", ini), ini[:200])
    # 13 Nov 26 Windows port (RELEASE_1.1 253(b)): or run.in's debugged child, a cross-process stop whose screen is this terminal's (relay.on)
    ck("F2 alt.screen is the alternate screen in use: full.screen, not a phantom (Windows: or run.in's relay), and alt.able",
       "alt.screen = full.screen and (not(phantom) or relay.on) and alt.able" in c)

    # smcup / rmcup are written only under alt.on, alt.screen or alt.able
    bad = []
    lines = c.splitlines()
    for i, l in enumerate(lines):
        if re.search(r"display terminfo\('(smcup|rmcup)'\)", l):
            window = "\n".join(lines[max(0, i - 6):i + 1])
            if not re.search(r"alt\.(on|screen|able)", window):
                bad.append(l.strip())
    ck("F3 every write of smcup or rmcup is under alt.on, alt.screen or alt.able", not bad and "smcup" in c, repr(bad))

    ck("F4 the first-stop paint in initialise is for an alternate screen only (full.screen and alt.able)", re.search(r"if full\.screen and alt\.able then\s*\n\s*gosub theme\.in", ini))

    for lab in ("exit.debug", "abort.debug", "stop.debug"):
        body = routine(c, lab) or ""
        to, ls, st = pos(body, r"gosub theme\.out"), pos(body, r"gosub leave\.screen"), pos(body, r"gosub dbg\.stop")
        ok = 0 <= to < ls and "gosub leave.alt" not in body and (lab == "exit.debug" or ls < st)
        ck("F5 %s: theme.out, then leave.screen (never leave.alt directly), then dbg.stop" % lab, ok, repr((to, ls, st)))

    ls_ = routine(c, "leave.screen") or ""
    ck("F6 leave.screen: leave.alt, then give.main only if main.on", 0 <= pos(ls_, r"gosub leave\.alt") < pos(ls_, r"if main\.on then gosub give\.main"), ls_)

    gm = routine(c, "give.main") or ""
    g_off, g_get, g_own, g_rep, g_put, g_clr = (pos(gm, p) for p in (r"main\.on = @false", r"call \$sl_scr\('get', ps\)", r"if ps<SL\.S\.OWNED> then",
                                                                   r"call \$sl_repaint\(ps\)", r"call \$sl_scr\('put', ps\)", r"display @\(-31\) : sq : @\(-1\)"))
    ck("F7 give.main reads the kept context again, repaints an owned screen then puts it back, and clears any other with the cursor shown (@(-31)) and the plain style",
       0 <= g_off < g_get < g_own < g_rep < g_put < g_clr, repr((g_off, g_get, g_own, g_rep, g_put, g_clr)))
    # 9 Nov 26 (S.186): dbg.find (F2, the finder) puts the debugger's own context in place for $sl_palette and then the kept one back, exactly as it was got:
    # the only other pair, and it must be get-keep, put-own, palette, get-own, put-keep in that order
    fd = routine(c, "dbg.find") or ""
    f_get, f_own, f_pal, f_back, f_keep = (pos(fd, p) for p in (r"call \$sl_scr\('get', pal\.keep\)", r"call \$sl_scr\('put', scr\)", r"call \$sl_palette\(",
                                                               r"call \$sl_scr\('get', scr\)", r"call \$sl_scr\('put', pal\.keep\)"))
    ck("F8 the debugger writes the kept context back ($sl_scr 'put') in give.main, and otherwise only dbg.find's pair (its own for the finder, the kept one back after)",
       c.count("$sl_scr('put'") == 3 and "$sl_scr('put'" in gm and fd.count("$sl_scr('put'") == 2 and 0 <= f_get < f_own < f_pal < f_back < f_keep,
       repr((c.count("$sl_scr('put'"), f_get, f_own, f_pal, f_back, f_keep)))
    ck("F9 the debugger still calls none of the one-app toolkit routines", not re.search(r"call \$tk_(open|close|frame|menubar|help)\b", c))

    tm = routine(c, "take.main") or ""
    ck("F10 take.main: main.on, the plain style, a clear with @(-1)", re.search(r"main\.on = @true\s*\n\s*call \$sl_sgr\('n', sq\)\s*\n\s*display sq : @\(-1\) :", tm), tm)

    top = c[:c.find("found.program:")]
    ck("F11 main.on is reset at every entry, next to alt.on", re.search(r"alt\.on = @false\s*\n\s*main\.on = @false", top))
    watch = pos(c, r"if not\(watch\.met\) then")
    gx = pos(c, r"goto exit\.debug", watch if watch >= 0 else 0)
    take = pos(c, r"if full\.screen and not\(alt\.able\) then\s*\n\s*gosub take\.main\s*\n\s*gosub theme\.in\s*\n\s*gosub paint\.layout\s*\n\s*gosub paint\.data\.area")
    disp = pos(c, r"^\s*gosub display\.source\s*\n\s*if full\.screen then gosub refresh\.panes")
    ck("F12 the main screen is taken only for a stop to be shown: after the hand-over and the conditional WATCH may have gone on, before the source is displayed, with theme.in AFTER it",
       0 <= watch < gx < take < disp, repr((watch, gx, take, disp)))
    ck("F13 take.main is called at one place only, and not in initialise", c.count("gosub take.main") == 1 and "take.main" not in ini)

    vw = routine(c, "view") or ""
    v_main = pos(vw, r"if main\.on then")
    v_get, v_out, v_rep, v_key, v_in, v_msg = (pos(vw, p, max(v_main, 0)) for p in (r"call \$sl_scr\('get', ps\)", r"gosub theme\.out", r"call \$sl_repaint\(ps\)",
                                                                              r"s = keycode\(\)", r"gosub theme\.in", r"message = sysmsg\(12602\)"))
    ck("F14 view on the main screen: an owned screen is repainted in the program's theme (theme.out first), a key is waited for, the debugger's theme and frame come back; any other gets message 12602",
       0 <= v_main < v_get < v_out < v_rep < v_key < v_in < v_msg and "gosub refresh.panes" in vw[v_in:], repr((v_main, v_get, v_out, v_rep, v_key, v_in, v_msg)))
    ck("F15 message 12602 exists, is one line and starts with a capital", s["msg"].count("\n") == 1 and s["msg"][:1].isupper(), repr(s["msg"]))

    lm = pos(ini, r"=\s*'LINE\.MODE' then full\.screen = @false")
    need = pos(ini, r"call \$sl_need\(")
    ck("F16 LINE.MODE in $debug.options turns the full screen off, before the window is tested", 0 <= lm < need, repr((lm, need)))

    block = h.split("common /$debug/", 1)[1] if "common /$debug/" in h else ""
    block = block.split("$define DE$WATCH", 1)[0].rstrip()
    # 13 Nov 26 Windows port (RELEASE_1.1 253(b)): dbg.relay went after it, at the very end, so that alt.able itself did not move
    ck("F17 alt.able comes after auto.prev in debug.h's common block, and only dbg.relay (Windows, 13 Nov 26) after it (no earlier one moves)",
       block.endswith("dbg.relay") and block.rfind("auto.prev") < block.rfind("alt.able") < block.rfind("dbg.relay"), block[-120:])

    ti = s["terminfo.src"]
    got = {}
    for name in ("linux", "vt100", "vt102", "vt220", "ansi", "dumb", "unknown", "null", "xterm"):
        e = entry(ti, name) or ""
        got[name] = tuple(bool(re.search(r"(?<![\w])%s=" % cap, e)) for cap in ("cup", "clear", "smcup", "rmcup"))
    served = all(got[n][0] and got[n][1] and not got[n][2] for n in ("linux", "vt100", "vt102", "vt220", "ansi"))
    ck("F18 terminfo.src: linux, vt100, vt102, vt220 and ansi have cup and clear and no smcup (the types H3 newly serves)", served, repr(got))
    ck("F19 terminfo.src: dumb, unknown and null have no cup (they stay in line mode); xterm has smcup and rmcup", not any(got[n][0] for n in ("dumb", "unknown", "null")) and got["xterm"][2] and got["xterm"][3], repr(got))
    return out


def mutants(s):
    res = []

    def mut(name, f, old, new):
        if old not in s[f]:
            res.append((name, None))
            return
        t = dict(s)
        t[f] = s[f].replace(old, new, 1)
        res.append((name, t))

    mut("F1 full.screen from smcup again", "debug", "terminfo('cup') # '' and terminfo('clear') # '' then", "terminfo('smcup') # '' and terminfo('clear') # '' then")
    mut("F2 alt.screen ignores alt.able", "debug", "alt.screen = full.screen and (not(phantom) or relay.on) and alt.able", "alt.screen = full.screen and (not(phantom) or relay.on)")
    mut("F3 rmcup written unguarded", "debug", "leave.alt:\n   if alt.on then\n      display terminfo('rmcup') :", "leave.alt:\n   if 1 then\n      display terminfo('rmcup') :")
    mut("F4 initialise paints on every full screen", "debug", "if full.screen and alt.able then\n      * Set up initial display", "if full.screen then\n      * Set up initial display")
    mut("F5 stop.debug gives back the alternate screen only", "debug", "stop.debug:\n   gosub ibk.sync\n   if full.screen then gosub theme.out\n   gosub leave.screen", "stop.debug:\n   gosub ibk.sync\n   if full.screen then gosub theme.out\n   gosub leave.alt")
    mut("F6 leave.screen never gives the main screen back", "debug", "   if main.on then gosub give.main\n", "")
    mut("F7 give.main skips the repaint", "debug", "      call $sl_repaint(ps)\n      call $sl_scr('put', ps)", "      call $sl_scr('put', ps)")
    mut("F8 the debugger writes the context back elsewhere", "debug", "         gosub theme.in\n         gosub paint.layout\n         gosub paint.data.area\n         src.line = line",
        "         gosub theme.in\n         call $sl_scr('put', scr)\n         gosub paint.layout\n         gosub paint.data.area\n         src.line = line")
    mut("F8 the finder does not give the kept context back", "debug", "   call $sl_scr('get', scr)\n   call $sl_scr('put', pal.keep)\n", "   call $sl_scr('get', scr)\n")
    mut("F8 the finder draws on the kept context", "debug", "   call $sl_scr('put', scr)\n   call $sl_palette(", "   call $sl_palette(")
    mut("F9 the debugger opens a toolkit app", "debug", "   gosub take.main\n      gosub theme.in", "   gosub take.main\n      call $tk_open('x', 'y', ctx, err)\n      gosub theme.in")
    mut("F10 take.main does not clear", "debug", "   display sq : @(-1) :\n   return\n\n* GIVE.MAIN", "   return\n\n* GIVE.MAIN")
    mut("F11 main.on is not reset at entry", "debug", "   alt.on = @false\n   main.on = @false\n", "   alt.on = @false\n")
    mut("F12 the main screen is taken before the conditional WATCH", "debug", "   if full.screen and not(alt.able) then       ;* S.98 H3: this stop", "   if full.screen and not(alt.able) and 0 then       ;* S.98 H3: this stop")
    mut("F13 take.main is also called in initialise", "debug", "   if full.screen and alt.able then\n      * Set up initial display", "   gosub take.main\n   if full.screen and alt.able then\n      * Set up initial display")
    mut("F14 view repaints in the debugger's theme", "debug", "         gosub theme.out\n         call $sl_repaint(ps)", "         call $sl_repaint(ps)")
    mut("F15 message 12602 gone", "msg", "There is no second screen", "")
    mut("F16 LINE.MODE ignored", "debug", "'LINE.MODE' then full.screen = @false", "'LINE.MODE' then null")
    mut("F17 alt.able moved up the block", "debug.h", "                   auto.prev,\n                   alt.able", "                   alt.able,\n                   auto.prev")
    return res


def main():
    s = {}
    for name, p in FILES.items():
        if not os.path.isfile(p):
            print("test-dbgmain-units: CANNOT RUN - no %s at %s" % (name, p))
            return 2
        s[name] = open(p, errors="replace").read()
    if "--selftest" in sys.argv:
        base = checks(s)
        if not all(ok for _, ok, _ in base):
            print("selftest: CANNOT RUN - the unmutated source already fails:")
            for n, ok, d in base:
                if not ok:
                    print("  FAIL %s (%s)" % (n, d))
            return 2
        bad = 0
        ms = mutants(s)
        for name, t in ms:
            if t is None:
                print("  [NOT APPLIED] %s" % name)
                bad += 1
                continue
            caught = [n for n, ok, _ in checks(t) if not ok]
            print("  [%s] %s%s" % ("caught" if caught else "MISSED", name, "  (%d check(s) failed)" % len(caught) if caught else ""))
            bad += 0 if caught else 1
        print("test-dbgmain-units --selftest: %d mutant(s), %d not caught" % (len(ms), bad))
        return 1 if bad else 0
    res = checks(s)
    fails = 0
    for name, ok, detail in res:
        print("  [%s] %s%s" % ("PASS" if ok else "FAIL", name, "" if ok or not detail else "  (" + str(detail)[:300] + ")"))
        fails += 0 if ok else 1
    print("test-dbgmain-units: %d checks, %d failed" % (len(res), fails))
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
