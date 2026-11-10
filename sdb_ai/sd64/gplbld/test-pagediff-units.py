#!/usr/bin/env python3
"""test-pagediff-units.py - the invariants that keep a page of the toolkit from being left stale when it draws only what changed (S.113).

  python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/test-pagediff-units.py
  python3 .../test-pagediff-units.py --selftest

No sudo, no install, no sd.  Exit 0 all checks passed, 1 a check failed, 2 it could not run.  Written 3 Nov 26 (S.113, track F).

THE RULE (owner, 3 Nov 2026: "All pages"): every full-screen page of the toolkit sends only what changed.  The screen library keeps two
pictures of a screen it owns: the SHADOW (what the program drew) and the TERMINAL's (SL.S.TERM, SL.S.TATTR: what the terminal shows).
SL.S.DIFF 1 writes only the cells the terminal does not already show; that is safe only while the terminal's picture is TRUE.  So:
  1. every write keeps the terminal's picture ($sl_put's keep.term runs after the text is written, on every path that writes);
  2. every routine that clears or overwrites the terminal outside $sl_put resets the picture with it ($sl_repaint, $sl_desktop) or marks
     the screen unsynced ($sl_key after the cursor lock's warning; a resize of a page; Ctrl-L and F5 on a page), and a flush of an
     unsynced screen repaints it whole;
  3. only SCREEN TEXT, SCREEN BOX and SCREEN CLEAR take the context with 'draw' (difference drawing), and only on a screen $tk_open marked;
  4. the program's own waits (SCREEN KEY, SCREEN WAIT) flush before they read a key, and SCREEN CLOSE does not;
  5. a direct DISPLAY that changes cells (a clear, or text) appears only in the routines listed here, each of which keeps rule 2.

***WHAT THIS IS AND IS NOT.***  It reads the programs as text.  It cannot say what the terminal shows: sandbox-pagedraw.py does that
(rows F4c-F14c, Q1c-Q3c, H1c-H3c, A2c-A3c: the emulated screen against a full repaint).  --selftest mutates the sources and requires
each mutant caught.
"""

import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
GP = os.path.abspath(os.path.join(HERE, os.pardir, "sdsys", "gpl.bp"))
FILES = ["sl.h", "sl_put", "sl_scr", "sl_repaint", "sl_desktop", "sl_resize", "sl_key", "sl_curat", "screen_key", "screen_wait", "screen_text", "screen_box",
         "screen_clear", "screen_close", "tk_open"]
# 5: the routines that may DISPLAY a clear or text without $sl_put, and why each is safe
RAW_WRITERS = {"sl_repaint": "resets the picture", "sl_desktop": "resets the picture", "sl_guard": "its caller $sl_key unsyncs",
               "screen_close": "the screen is given back", "sl_cleanup": "the screen is given back"}


def code(src):
    return "\n".join(l.split(";*")[0] for l in src.splitlines() if not l.lstrip().startswith("*"))


def label_body(c, label):
    m = re.search(r"^%s:\s*$(.*?)^\s*return\s*$" % re.escape(label), c, re.M | re.S)
    return m.group(1) if m else None


def checks(srcs, raw_dir_files):
    out = []

    def ck(name, ok, detail=""):
        out.append((name, bool(ok), detail))

    h = srcs["sl.h"]
    slots = re.findall(r"^\$define\s+SL\.S\.\w+\s+(\d+)", h, re.M)
    for nm in ("TERM", "TATTR", "TK"):
        m = re.search(r"^\$define\s+SL\.S\.%s\s+(\d+)" % nm, h, re.M)
        ck("sl.h: SL.S.%s is defined, on a slot no other SL.S name has" % nm, m is not None and slots.count(m.group(1)) == 1, m.group(0) if m else None)

    # 1. $sl_put: the shadow before the early returns; keep.term after display; keep.term updates both pictures
    p = code(srcs["sl_put"])
    i_shadow = p.find("scr<SL.S.SHADOW, y + 1> = row[1, x]")
    i_defer = p.find("if dmode = 2 then return")
    i_same = p.find("if compare(ot, text) = 0 and compare(oa, cells) = 0 then return")
    i_disp = p.find("display out :")
    i_keep = p.find("gosub keep.term")
    i_clip = p.find("if n < 1 then return")
    between = p[i_clip + len("if n < 1 then return"):i_shadow] if 0 <= i_clip < i_shadow else "return"
    ck("sl_put: the shadow is changed before any return that writes nothing (DIFF 2, cells already shown), and nothing returns between the clip and it",
       0 <= i_shadow < i_defer and i_shadow < i_same and "return" not in between, (i_shadow, i_defer, i_same, between.strip()[:60]))
    ck("sl_put: the terminal's picture is kept (gosub keep.term) right after the text is written", 0 <= i_disp < i_keep and p.count("display ") == 1 and p.count("gosub keep.term") == 1,
       (i_disp, i_keep))
    kb = label_body(p, "keep.term") or ""
    ck("sl_put: keep.term writes both SL.S.TERM and SL.S.TATTR over x to x + n", "scr<SL.S.TERM, y + 1> = tr[1, x] : text" in kb and "scr<SL.S.TATTR, y + 1> = ta[1, x] : cells" in kb, kb[:80])
    ck("sl_put: DIFF 1 compares with the TERMINAL's picture (SL.S.TERM / SL.S.TATTR), not with the shadow",
       re.search(r"if dmode = 1 and has\.term then\s*tr = scr<SL\.S\.TERM, y \+ 1>\s*ta = scr<SL\.S\.TATTR, y \+ 1>", p) is not None)

    # 2. resets
    r = code(srcs["sl_repaint"])
    ck("sl_repaint: the terminal's picture is blanked after the clear @(-1) and before any row is written",
       0 <= r.find("@(-1)") < r.find("scr<SL.S.TERM, r + 1> = space(") < r.find("call $sl_put"), (r.find("@(-1)"), r.find("scr<SL.S.TERM, r + 1>"), r.find("call $sl_put")))
    ck("sl_repaint: SL.S.SYNC is set 1 at the end", re.search(r"scr<SL\.S\.SYNC> = 1\s*return\s*end", r) is not None)
    d = code(srcs["sl_desktop"])
    ck("sl_desktop: the terminal's picture is blanked with the clear", 0 <= d.find("@(-1)") < d.find("scr<SL.S.TERM, r + 1> = space(sw)"), d.find("scr<SL.S.TERM, r + 1>"))
    s = code(srcs["sl_scr"])
    rb = label_body(s, "resize") or ""
    ck("sl_scr: a resize of a page of the toolkit (defer) marks the screen unsynced: SYNC 0 and the note ss.lost",
       re.search(r"call \$sl_resize\(ctx, 'defer'\)\s*ctx<SL\.S\.SYNC> = 0 ; ss\.lost = 1", rb) is not None, rb[:120])
    fb = label_body(s, "flush") or ""
    ck("sl_scr: a flush of a screen that is unsynced (the note, or a page whose SYNC is not 1) repaints it whole and forgets the note",
       "fl.all = ss.lost" in fb and "if ctx<SL.S.TK> and ctx<SL.S.SYNC> # 1 then fl.all = 1" in fb and re.search(r"call \$sl_repaint\(ctx\)\s*ss\.lost = 0", fb) is not None)
    ck("sl_scr: a flush lifts the clip while it writes and puts it back", "ctx<SL.S.CLIP> = ''" in fb and "ctx<SL.S.CLIP> = fl.clip" in fb)
    ck("sl_scr: 'unsync' and 'refresh' set the note and SYNC 0; refresh only on a page of the toolkit",
       re.search(r"case op = 'unsync'\s*if ctx\.open then\s*ss\.lost = 1\s*ctx<SL\.S\.SYNC> = 0", s) is not None
       and re.search(r"case op = 'refresh'\s*if ctx\.open and ctx<SL\.S\.TK> then\s*ss\.lost = 1\s*ctx<SL\.S\.SYNC> = 0", s) is not None)
    ck("sl_scr: a context handed out while the note is set says SYNC 0 (a form then writes everything)", "if ss.lost then scr<SL.S.SYNC> = 0" in s)
    ck("sl_scr: 'draw' gives DIFF 1 or 2 only on a page of the toolkit; get and peek give 0",
       re.search(r"scr<SL\.S\.DIFF> = 0.*?if op = 'draw' and ctx<SL\.S\.TK> then\s*scr<SL\.S\.DIFF> = \(if scr<SL\.S\.SYNC> = 1 then 1 else 2\)", s, re.S) is not None)
    ck("sl_scr: get flushes on a page of the toolkit; peek and draw do not", "if op = 'get' and ctx<SL.S.TK> then gosub flush" in s)
    ck("sl_scr: open blanks the terminal's picture and forgets the note; close forgets the note",
       re.search(r"case op = 'open'.*?blank\.scr<SL\.S\.TERM, r \+ 1> = space\(@crtwide\).*?ss\.lost = 0", s, re.S) is not None
       and re.search(r"case op = 'close'.*?ss\.lost = 0", s, re.S) is not None)
    z = code(srcs["sl_resize"])
    ck("sl_resize: the new context's terminal picture is blank, and SL.S.TK is carried", "nscr<SL.S.TERM, r + 1> = space(sw)" in z and "nscr<SL.S.TK> = old<SL.S.TK>" in z)
    ck("sl_resize: without defer the screen is repainted", re.search(r"if rmode = 'defer' then return\s*call \$sl_repaint\(scr\)", z) is not None)
    k = code(srcs["sl_key"])
    gb = label_body(k, "guard.cursor") or ""
    ck("sl_key: after the cursor lock's guard has drawn, the screen is unsynced", gb.find("call $sl_guard") < gb.find("call $sl_scr('unsync', '')") and "call $sl_scr('unsync', '')" in gb, gb[-200:])

    # 3. who draws by difference
    users = sorted(f for f, t in raw_dir_files.items() if "$sl_scr('draw'" in code(t))
    ck("only SCREEN TEXT, SCREEN BOX and SCREEN CLEAR take the context with 'draw'", users == ["screen_box", "screen_clear", "screen_text"], users)
    c = code(srcs["screen_clear"])
    ck("screen_clear: a rectangle on a page goes to the shadow only (DIFF 1 becomes 2 for the clear)", "if scr<SL.S.DIFF> = 1 then scr<SL.S.DIFF> = 2" in c)
    b = code(srcs["screen_box"])
    ck("screen_box: a box on a page goes to the shadow only (DIFF 1 becomes 2), after draw", 0 <= b.find("$sl_scr('draw', scr)") < b.find("if scr<SL.S.DIFF> = 1 then scr<SL.S.DIFF> = 2"))
    # the cursor a statement leaves: skipped only when nothing was written, and owed to the flush
    ck("sl_scr: put leaves the cursor out only for a statement that drew by difference and left the terminal's picture as it was",
       re.search(r"if scr<SL\.S\.DIFF> \+ 0 >= 1 then\s*if compare\(scr<SL\.S\.TERM>, ctx<SL\.S\.TERM>\) = 0 and compare\(scr<SL\.S\.TATTR>, ctx<SL\.S\.TATTR>\) = 0 then put\.skip = 1", s) is not None
       and re.search(r"if put\.skip then\s*cq\.owed = 1\s*end else\s*cq\.owed = 0\s*gosub put\.cursor", s) is not None)
    ck("sl_scr: a flush places an owed cursor (or the one $sl_curat placed last)", "if fl.wrote or cq.owed then" in fb and "if cq.last = 'curat' and fl.cur<1, 1> + 0 then" in fb)
    cu = code(srcs["sl_curat"])
    ck("sl_curat: every DISPLAY of the cursor is followed by cq.last = 'curat' and nothing owed",
       len(re.findall(r"display @\(cu\.x, cu\.y\) :\s*cq\.last = 'curat'\s*cq\.owed = 0", cu)) == cu.count("display ") == 2, cu.count("display "))
    t = code(srcs["tk_open"])
    ck("tk_open: the screen it took is marked the toolkit's, after SCREEN OPEN", 0 <= t.find("screen open clear") < t.find("call $sl_scr('toolkit', '')"))

    # 4. waits flush; close does not
    sk = code(srcs["screen_key"])
    ck("screen_key: flushes before it reads the keyboard", 0 <= sk.find("call $sl_scr('flush', '')") < sk.find("call $sl_key("))
    ck("screen_key: F5 and Ctrl-L ask for a whole repaint", "if ret = 'f5' or ret = 'ctrl-l' then call $sl_scr('refresh', '')" in sk)
    ck("screen_key: after a resize the picture is taken with peek (the page is repainted once, after it drew)", "call $sl_scr('peek', scr)" in sk and "$sl_scr('get'" not in sk)
    sw = code(srcs["screen_wait"])
    ck("screen_wait: flushes before the form waits", 0 <= sw.find("call $sl_scr('flush', '')") < sw.find("call $sl_form('wait'"))
    sc = code(srcs["screen_close"])
    ck("screen_close: takes the picture with peek, not get", "$sl_scr('peek', scr)" in sc and "$sl_scr('get'" not in sc)

    # 5. raw writers
    raw = []
    for f, txt in raw_dir_files.items():
        cc = code(txt)
        if re.search(r"display[^\n]*@\(-1\)", cc) or (f.startswith(("sl_", "screen_", "tk_")) and re.search(r"display\s+(?:rev|nor)\s*:\s*@\(", cc)):
            raw.append(f)
    extra = sorted(set(raw) - set(RAW_WRITERS))
    ck("a DISPLAY that clears the screen or writes text outside $sl_put appears only in %s" % ", ".join(sorted(RAW_WRITERS)), not extra, extra)
    return out


def mutants(srcs, raw):
    res = []

    def mut(name, f, old, new):
        s = dict(srcs)
        r2 = dict(raw)
        s[f] = srcs[f].replace(old, new, 1)
        if f in r2:
            r2[f] = s[f]
        res.append((name, s, r2, s[f] == srcs[f]))

    mut("sl_put: the terminal's picture not kept after a write", "sl_put", "   gosub keep.term                                    ;* MUTANT-POINT term\n", "")
    mut("sl_put: DIFF 1 judged against the shadow", "sl_put", "      tr = scr<SL.S.TERM, y + 1>", "      tr = scr<SL.S.SHADOW, y + 1>")
    mut("sl_put: a DIFF 2 write returns before the shadow is changed", "sl_put", "   * The shadow: what the program has drawn", "   if scr<SL.S.DIFF> = 2 then return\n   * The shadow")
    mut("sl_repaint: the picture not blanked with the terminal", "sl_repaint", "         scr<SL.S.TERM, r + 1> = space(scr<SL.S.W> + 0)\n", "")
    mut("sl_desktop: the picture not blanked with the clear", "sl_desktop", "         scr<SL.S.TERM, r + 1> = space(sw)\n", "")
    mut("sl_scr: a resize of a page keeps SYNC (the runtime mutant resize-keeps-sync)", "sl_scr", "      ctx<SL.S.SYNC> = 0 ; ss.lost = 1           ;* MUTANT-POINT resize\n", "")
    mut("sl_scr: a flush ignores the note", "sl_scr", "   fl.all = ss.lost\n", "   fl.all = 0\n")
    mut("sl_scr: refresh on every screen", "sl_scr", "      case op = 'refresh'\n         if ctx.open and ctx<SL.S.TK> then", "      case op = 'refresh'\n         if ctx.open then")
    mut("sl_scr: draw gives DIFF 1 on every screen", "sl_scr", "            if op = 'draw' and ctx<SL.S.TK> then", "            if op = 'draw' then")
    mut("sl_scr: the note not shown to a copy", "sl_scr", "            if ss.lost then scr<SL.S.SYNC> = 0\n", "")
    mut("sl_scr: the clip not lifted for a flush", "sl_scr", "   ctx<SL.S.CLIP> = ''\n", "")
    mut("sl_key: no unsync after the guard", "sl_key", "   call $sl_scr('unsync', '')", "   null")
    mut("screen_key: no flush before the wait", "screen_key", "      call $sl_scr('flush', '')", "      null")
    mut("screen_key: F5 does not repaint", "screen_key", "if ret = 'f5' or ret = 'ctrl-l' then", "if ret = 'ctrl-l' then")
    mut("screen_key: get after a resize (a repaint before the page drew)", "screen_key", "call $sl_scr('peek', scr)", "call $sl_scr('get', scr)")
    mut("screen_wait: no flush", "screen_wait", "   call $sl_scr('flush', '')", "   null")
    mut("screen_close: get (a flush of a screen given back)", "screen_close", "$sl_scr('peek', scr)", "$sl_scr('get', scr)")
    mut("tk_open: the screen not marked the toolkit's", "tk_open", "   call $sl_scr('toolkit', '')", "   null")
    mut("screen_clear: a clear written at once on a page", "screen_clear", "      if scr<SL.S.DIFF> = 1 then scr<SL.S.DIFF> = 2", "      null")
    mut("sl.h: SL.S.TK on SL.S.DIFF's slot", "sl.h", "$define SL.S.TK        17", "$define SL.S.TK        14")
    mut("sl_resize: SL.S.TK not carried", "sl_resize", "   nscr<SL.S.TK> = old<SL.S.TK>\n", "")
    mut("screen_box: a box written at once on a page", "screen_box", "   if scr<SL.S.DIFF> = 1 then scr<SL.S.DIFF> = 2", "   null")
    mut("sl_scr: put leaves the cursor out whatever was written", "sl_scr", "and compare(scr<SL.S.TATTR>, ctx<SL.S.TATTR>) = 0 then put.skip = 1", "or 1 then put.skip = 1")
    mut("sl_scr: an owed cursor never placed", "sl_scr", "   if fl.wrote or cq.owed then", "   if fl.wrote then")
    mut("sl_curat: a cursor it placed not noted", "sl_curat", "            cq.last = 'curat'\n", "")
    return res


def load():
    srcs = {}
    for p in FILES:
        path = os.path.join(GP, p)
        if not os.path.isfile(path):
            return None, None, path
        srcs[p] = open(path, encoding="utf-8", errors="replace").read()
    raw = {}
    for f in sorted(os.listdir(GP)):
        if f.startswith(("sl_", "screen_", "tk_")):
            raw[f] = open(os.path.join(GP, f), encoding="utf-8", errors="replace").read()
    return srcs, raw, None


def main():
    srcs, raw, missing = load()
    if srcs is None:
        print("test-pagediff-units: CANNOT RUN - no %s" % missing)
        return 2
    if len(raw) < 50:
        print("test-pagediff-units: CANNOT RUN - only %d sl_/screen_/tk_ programs read from %s" % (len(raw), GP))
        return 2
    if "--selftest" in sys.argv:
        base = checks(srcs, raw)
        if not all(ok for _, ok, _ in base):
            print("selftest: CANNOT RUN - the unmutated sources already fail:")
            for n, ok, d in base:
                if not ok:
                    print("  FAIL %s (%s)" % (n, d))
            return 2
        bad = 0
        ms = mutants(srcs, raw)
        for name, s, r2, same in ms:
            if same:
                print("  [NOT APPLIED] %s" % name)
                bad += 1
                continue
            caught = [n for n, ok, _ in checks(s, r2) if not ok]
            print("  [%s] %s%s" % ("caught" if caught else "MISSED", name, "  (%d check(s) failed)" % len(caught) if caught else ""))
            bad += 0 if caught else 1
        print("test-pagediff-units --selftest: %d mutant(s), %d not caught" % (len(ms), bad))
        return 1 if bad else 0
    print("gpl.bp : %s (%d sl_/screen_/tk_ programs read)" % (GP, len(raw)))
    res = checks(srcs, raw)
    fails = 0
    for name, ok, detail in res:
        print("  [%s] %s%s" % ("PASS" if ok else "FAIL", name, "" if ok or not detail else "  (" + str(detail) + ")"))
        fails += 0 if ok else 1
    print("test-pagediff-units: %d checks, %d failed" % (len(res), fails))
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
