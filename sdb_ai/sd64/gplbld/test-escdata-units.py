#!/usr/bin/env python3
# test-escdata-units.py - text that comes from DATA never reaches the terminal as a control character (S.88 phase 2, S1; 28 Oct 2026): $sl_put's scrub, read off the source as text, a MODEL of
# it run over random byte strings, and the list of programs of the screen library that write to the terminal at all.  The behaviour is sandbox-escdata.py's (the raw bytes of a session;
# WRITTEN, not run); this holds the ORDER and the SHAPE:
#   - the scrub is in $sl_put, which every widget and SCREEN TEXT draw through, AFTER the marks became dots and BEFORE the clip, the DIFF comparison, the shadow and the terminal: so the
#     shadow holds what is shown and a repaint from it cannot send the control character either;
#   - the control characters are CHAR(0) to CHAR(31) except the tab (a blank) and the nine stand-ins CHAR(14) to CHAR(22) of $sl_line (the library's glyph path), and CHAR(127); each is
#     shown as the character 64 above it (DEL as ?), ONE CELL FOR ONE CHARACTER, in the reverse style; the bytes from 128 up pass (UTF-8 text and the library's own glyph bytes);
#   - THE C1 CONTROLS (28 Oct 2026, a review of the first version, which scrubbed 0-31 and 127 only): 0x9B is CSI on a terminal that is not in UTF-8 mode.  The mode is resolved once from
#     LC_ALL, LC_CTYPE, LANG (UTF-8 or UTF8) or is UTF-8 when the screen was opened with LINES; not UTF-8, the bytes 128-159 are shown as the character 64 below (0x9B as [), UTF-8 only the
#     pair C2 80..C2 9F is shown (a dot and that letter, two cells for two bytes) and every well-formed sequence, a curly quote included, passes; the same length throughout;
#   - $screen_text only calls $sl_put (it writes nothing itself);
#   - NO OTHER PROGRAM of the library (sl_*, screen_*, tk_*) writes text to the terminal: the DISPLAY statements are exactly the known ones, each a cursor, mode or style sequence or a bell,
#     never a variable holding data.  A new DISPLAY in the library fails here until it is looked at.
# AND a model in Python of the scrub over 3,000 random strings of all 256 byte values: same length, no control character left (but the stand-ins), printable ASCII and bytes from 128 up
# unchanged, the ESC byte is [ , idempotent.
# FREE CHECK: no install, no sd.
#
#   python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/test-escdata-units.py
#   python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/test-escdata-units.py --selftest
import glob
import os
import random
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
BP = os.environ.get("BPDIR", os.path.normpath(os.path.join(HERE, "..", "sdsys", "gpl.bp")))

# program -> number of DISPLAY statements (28 Oct 2026, measured).  Each is a sequence of the library's own (cursor, mode, style, clear, mouse) or a bell, or in sl_guard the
# library's own message line over the top row.  sl_memo is 1 since 9 Nov 2026 (S.184 stage 2): every bell goes through its ring.bell.
DISPLAYS = {"sl_cleanup": 2, "sl_desktop": 1, "sl_form": 3,"sl_guard": 3, "sl_memo": 1, "sl_put": 1, "sl_repaint": 1, "sl_scr": 2, "screen_close": 3, "screen_cursor": 2, "screen_open": 1,
            "tk_std": 1}     # 9 Nov 26 (S.186): View > Mouse sends the terminal $sl_mouse's switch sequence (mouse.apply)


def read(name):
    with open(os.path.join(BP, name), encoding="latin-1") as f:
        return f.read()


def code(text):
    out = []
    for l in text.split("\n"):
        s = re.sub(r";\*.*$", "", l).rstrip()
        if s.strip() and not s.lstrip().startswith("*"):
            out.append(s.strip())
    return "\n".join(out)


def ordered(text, *parts):
    pos = 0
    for p in parts:
        i = text.find(p, pos)
        if i < 0:
            return False
        pos = i + len(p)
    return True


def scrub(text, utf8=False):
    """The model of the scrub as the source writes it: a tab is a blank, every other control character the one 64 above it, DEL ?, the stand-ins 14-22 untouched.
    The C1 controls (review of 28 Oct): not UTF-8, each byte 128-159 is the one 64 below it; UTF-8, the pair C2 80..C2 9F is '.' and the one 64 below the second byte, and
    nothing else from 128 up changes."""
    out = []
    for ch in text:
        c = ord(ch)
        if c == 9:
            out.append(" ")
        elif c == 127:
            out.append("?")
        elif c < 32 and not (14 <= c <= 22):
            out.append(chr(c + 64))
        elif 128 <= c <= 159 and not utf8:
            out.append(chr(c - 64))
        else:
            out.append(ch)
    s = "".join(out)
    if utf8:
        o = []
        i = 0
        while i < len(s):
            if ord(s[i]) == 0xC2 and i + 1 < len(s) and 128 <= ord(s[i + 1]) <= 159:
                o.append(".")
                o.append(chr(ord(s[i + 1]) - 64))
                i += 2
            else:
                o.append(s[i])
                i += 1
        s = "".join(o)
    return s


def display_counts():
    d = {}
    for path in sorted(glob.glob(os.path.join(BP, "sl_*")) + glob.glob(os.path.join(BP, "screen_*")) + glob.glob(os.path.join(BP, "tk_*"))):
        name = os.path.basename(path)
        if name.endswith(".h"):
            continue
        n = len(re.findall(r"(?m)^\s*(?:display|crt|print)\b", code(read(name))))
        if n:
            d[name] = n
    return d


def checks(src, dcounts):
    put = code(src["sl_put"])
    rows = []

    def ck(name, ok, detail=""):
        rows.append((name, bool(ok), detail))

    ck("C1 the table: CHAR(0) to CHAR(31) except 9 and 14-22, and CHAR(127) shown as ?, made once (the COMMON block /slctl/ starts as 0 or unassigned)",
       ordered(put, "common /slctl/ ctl.from, ctl.to", "if unassigned(ctl.from) then ctl.from = ''", "if len(ctl.from) < 20 then", "for ci = 0 to 31", "if ci # 9 and (ci < 14 or ci > 22) then",
               "ctl.from := char(ci)", "ctl.to := char(ci + 64)", "ctl.from := char(127)", "ctl.to := '?'"), put[:400])
    ck("C2 the scrub: the tab becomes a blank, the rest is converted through the table, and ONLY IF something changed the style of the changed cells is set to reverse one by one and the text replaced",
       ordered(put, "text = convert(char(9), ' ', text)", "safe = convert(ctl.from, ctl.to, text)", "if compare(safe, text) # 0 then", "for ci = 1 to n",
               "if compare(safe[ci, 1], text[ci, 1]) # 0 then cells = cells[1, ci - 1] : 'r' : cells[ci + 1, n]", "next ci", "text = safe"), "")
    # 3 Nov 26 (S.113): the shadow is written before the DIFF comparison now (which is against the terminal's picture); both stay after the scrub and the clip
    ck("C3 the order in $sl_put: the cells are made, the marks become dots, THEN the scrub, THEN the clip, the shadow, the DIFF comparison and the terminal",
       ordered(put, "cells = attr : str('n', n)", "text = convert(@fm : @vm : @sm : @tm : char(255), '.....', text)", "safe = convert(ctl.from, ctl.to, text)", "x0 = 0 ; x1 = sw - 1",
               "scr<SL.S.SHADOW, y + 1> =", "if dmode = 1 and has.term then", "display out :"), "")
    ck("C4 one cell for one character: n is not recomputed by the scrub and no character is added or removed (no CHANGE, no insert, no delete in the scrub's lines)",
       "n = len(text)" in put and put.count("n = len(text)") == 2 and "change(safe" not in put and "safe[" in put, "")
    ck("C5 the stand-ins of $sl_line stay (the glyph path): 14-22 are still turned into line characters or + - | # ^ v below, and the scrub's table excludes them",
       ordered(put, "lc.all = char(14)", "seg = change(seg, char(14)") and "ci < 14 or ci > 22" in put, "")
    ck("C6 the bytes from 128 up are not in the table (UTF-8 text and the library's own glyph bytes pass): the loop ends at 31 and the one other entry is CHAR(127)",
       "for ci = 0 to 31" in put and "ctl.from := char(127)" in put and not re.search(r"for ci = 0 to (3[2-9]|[4-9]\d|\d{3})", put), "")
    st = code(src["screen_text"])
    ck("C7 SCREEN TEXT draws through $sl_put and writes nothing itself (no DISPLAY, no CRT, no PRINT)", "call $sl_put(" in st and not re.search(r"(?m)^(display|crt|print)\b", st), st[:200])
    ck("C8 the programs of the library that write to the terminal are exactly the known ones with their known number of statements (%s)" % ", ".join("%s %d" % kv for kv in sorted(dcounts.items())),
       dcounts == DISPLAYS, "now %r, expected %r" % (dcounts, DISPLAYS))
    inp = code(src["sl_put"])
    ck("C9 $sl_put has exactly one DISPLAY, the last statement before RETURN, of the string it built", len(re.findall(r"(?m)^display\b", inp)) == 1 and ordered(inp, "display out :", "return"), "")
    # the C1 controls (28 Oct 2026, review): where the terminal's mode comes from, and the two ways to scrub
    ck("C10 the terminal mode is resolved ONCE per process, from LC_ALL, then LC_CTYPE, then LANG, upper-cased, UTF-8 or UTF8 (the IDE's and $tk_open's rule), in the COMMON block /slctl/ (starts as 0)",
       ordered(put, "common /slctl/ ctl.from, ctl.to, loc.mode, c1.from, c1.to", "if unassigned(loc.mode) then loc.mode = 0", "if loc.mode # 1 and loc.mode # 2 then", "loc = env('LC_ALL')",
               "if loc = '' then loc = env('LC_CTYPE')", "if loc = '' then loc = env('LANG')", "loc = upcase(loc)", "loc.mode = 2",
               "if index(loc, 'UTF-8', 1) > 0 or index(loc, 'UTF8', 1) > 0 then loc.mode = 1"), "")
    ck("C11 the table of the C1 controls: CHAR(128) to CHAR(159) shown as the character 64 below (0x9B as [), made once",
       ordered(put, "if len(c1.from) < 32 then", "for ci = 128 to 159", "c1.from := char(ci)", "c1.to := char(ci - 64)"), "")
    ck("C12 NOT UTF-8: after the C0 table and before the compare, the C1 table is applied byte for byte (convert, so the length cannot change); UTF-8 means the locale OR a screen opened with LINES (ln.on)",
       ordered(put, "safe = convert(ctl.from, ctl.to, text)", "if loc.mode = 1 or ln.on = 1 then", "end else", "safe = convert(c1.from, c1.to, safe)", "end", "if compare(safe, text) # 0 then"), "")
    ck("C13 UTF-8: only the pair C2 80 to C2 9F is replaced - the lead byte is looked for (CHAR(194)), the byte after it must exist (p < n) and be 128 to 159, the pair becomes '.' and the letter 64 below (two "
       "bytes for two), and the search moves on (k += 1) ONLY when nothing was replaced, so no loop can stand still and no other sequence is touched",
       ordered(put, "if loc.mode = 1 or ln.on = 1 then", "k = 1", "p = index(safe, char(194), k)", "while p > 0 do", "c2 = 0", "if p < n then c2 = seq(safe[p + 1, 1])",
               "if c2 >= 128 and c2 <= 159 then", "safe = safe[1, p - 1] : '.' : char(c2 - 64) : safe[p + 2, n]", "end else", "\nk += 1", "end", "repeat", "end else"), "")
    # 3 Nov 26 (S.113): "k += 1" at the start of its line (code() strips the lines) - $sl_put's run search counts with dk, and "dk += 1" must not stand in for the scrub's own step
    # the model
    rng = random.Random(20261028)
    for utf8 in (False, True):
        mode = "UTF-8" if utf8 else "not UTF-8"
        bad = 0
        ctl_left = 0
        c1_left = 0
        for _ in range(3000):
            s = "".join(chr(rng.choice((rng.randint(0, 255), 0xC2, rng.randint(128, 159)))) for _ in range(rng.randint(0, 60)))
            r = scrub(s, utf8)
            if len(r) != len(s) or scrub(r, utf8) != r:
                bad += 1
            if any((ord(c) < 32 and not 14 <= ord(c) <= 22) or ord(c) == 127 for c in r):
                ctl_left += 1
            if not utf8 and any(128 <= ord(c) <= 159 for c in r):
                c1_left += 1
            if utf8 and any(ord(a) == 0xC2 and 128 <= ord(b) <= 159 for a, b in zip(r, r[1:])):
                c1_left += 1
            # outside the replaced characters nothing from 32 up changes: printable ASCII always, the bytes from 160 up always, 128-159 in UTF-8 mode unless they follow a C2
            for a, b in zip(s, r):
                if a != b and 32 <= ord(a) <= 126:
                    bad += 1
                if a != b and ord(a) >= 160 and not (utf8 and ord(a) == 0xC2):
                    bad += 1
        ck("Y1 model, %s: 3,000 random byte strings (C2 and C1 bytes over-represented) keep their length, leave no control character but the stand-ins and no C1 control (%s), leave printable ASCII and "
           "the bytes from 160 up alone, and the scrub is idempotent (%d bad, %d with a control left, %d with a C1 left)"
           % (mode, "no byte 128-159" if not utf8 else "no C2 80-9F pair", bad, ctl_left, c1_left), bad == 0 and ctl_left == 0 and c1_left == 0, "")
    ck("Y2 model: ESC is shown as [ , BEL as G, NUL as @, DEL as ?, return as M, line feed as J, tab as a blank", scrub("\x1b\x07\x00\x7f\r\n\t") == "[G@?MJ ", repr(scrub("\x1b\x07\x00\x7f\r\n\t")))
    ck("Y3 model: the C1 CSI (0x9B) followed by 2J is shown as [2J when the terminal is not UTF-8, and C2 9B as .[ in UTF-8 mode; a lone 0x9B in UTF-8 mode is not a CSI there and passes",
       scrub("\x9b2J", False) == "[2J" and scrub("a\xc2\x9b2J", True) == "a.[2J" and scrub("\x9b", True) == "\x9b", repr((scrub("\x9b2J", False), scrub("a\xc2\x9b2J", True))))
    # real UTF-8 text must come through byte for byte in UTF-8 mode: the curly quotes, a dash, an e acute, a euro sign, and every well-formed two-byte sequence but U+0080 to U+009F
    keep = ["“", "”", "’", "–", "é", "€", " ", "ÿ", "Ā", "߿", "─", "\U0001f600", "x"]
    bad = 0
    for cp in list(range(0x00A0, 0x0800)) + [0x2018, 0x2019, 0x201C, 0x201D, 0x2013, 0x2014, 0x20AC, 0x2500, 0xFFFD, 0x1F600]:
        b = chr(cp).encode("utf-8").decode("latin-1")
        if scrub("a" + b + "z", True) != "a" + b + "z":
            bad += 1
    for ch in keep:
        b = ch.encode("utf-8").decode("latin-1")
        if scrub(b * 3, True) != b * 3:
            bad += 1
    ck("Y4 model, UTF-8: every character from U+00A0 to U+07FF and the curly quotes, dashes, euro sign and a four-byte emoji, as their UTF-8 bytes, pass byte for byte (%d changed)" % bad, bad == 0, "")
    bad = 0
    for cp in range(0x80, 0xA0):
        b = chr(cp).encode("utf-8").decode("latin-1")
        r = scrub("a" + b + "z", True)
        if len(r) != 4 or r != "a." + chr(cp - 64) + "z":
            bad += 1
    ck("Y5 model, UTF-8: each of U+0080 to U+009F (C2 80 to C2 9F) becomes a dot and the letter 64 below its second byte, two cells for two bytes (%d wrong)" % bad, bad == 0, "")
    return rows


def load():
    return {"sl_put": read("sl_put"), "screen_text": read("screen_text")}


def run():
    rows = checks(load(), display_counts())
    bad = 0
    for name, ok, detail in rows:
        print("  [%s] %s%s" % ("PASS" if ok else "FAIL", name, "" if ok else "   <- " + detail[:300]))
        bad += 0 if ok else 1
    print("test-escdata-units: %d passed, %d failed" % (len(rows) - bad, bad))
    return 1 if bad or not rows else 0


def selftest():
    src = load()
    dc = display_counts()
    if not all(ok for _, ok, _ in checks(src, dc)):
        print("  [FAIL] the real source does not pass")
        return 1
    print("  [ok] the real source passes")
    caught = missed = 0

    def mutant(name, prog, old, new, dcounts=None):
        nonlocal caught, missed
        s = dict(src)
        if s[prog].count(old) != 1:
            print("  [MISSED] %s: the text to change is found %d times" % (name, s[prog].count(old)))
            missed += 1
            return
        s[prog] = s[prog].replace(old, new, 1)
        failing = [n for n, ok, _ in checks(s, dcounts if dcounts is not None else dc) if not ok]
        if failing:
            print("  [caught] %s (%s)" % (name, ", ".join(f.split()[0] for f in failing)))
            caught += 1
        else:
            print("  [MISSED] %s" % name)
            missed += 1

    mutant("no scrub", "sl_put", "   if compare(safe, text) # 0 then\n", "   if compare(safe, text) # 0 and 0 then\n")
    mutant("ESC left out of the table", "sl_put", "      for ci = 0 to 31\n", "      for ci = 0 to 26\n")
    mutant("tab left as a tab", "sl_put", "   text = convert(char(9), ' ', text)\n", "")
    mutant("stand-ins scrubbed too", "sl_put", "if ci # 9 and (ci < 14 or ci > 22) then", "if ci # 9 then")
    mutant("high bytes scrubbed", "sl_put", "for ci = 0 to 31", "for ci = 0 to 255")
    mutant("DEL left out", "sl_put", "      ctl.from := char(127)\n      ctl.to := '?'\n", "")
    mutant("the cells are not marked", "sl_put", " then cells = cells[1, ci - 1] : 'r' : cells[ci + 1, n]", " then null")
    # the whole scrub block, cut out of its place and put after the clip (taken from the source itself, so it follows the block as it grows)
    a = src["sl_put"].find("   text = convert(char(9), ' ', text)\n")
    b = src["sl_put"].find("   * Clip to the screen and to the clip rectangle\n")
    c = src["sl_put"].find("   * 19 Oct 26: a form is drawing on a screen")
    if 0 <= a < b < c:
        block = src["sl_put"][a:b]
        mutant("scrub after the clip", "sl_put", src["sl_put"][a:c], src["sl_put"][b:c] + block)
    else:
        print("  [MISSED] scrub after the clip: the block was not found")
        missed += 1
    mutant("the table is not made once", "sl_put", "   if len(ctl.from) < 20 then\n", "   if 1 then\n")
    mutant("SCREEN TEXT writes by itself", "screen_text", "   call $sl_put(scr, x + 0, y + 0, line, code)\n", "   call $sl_put(scr, x + 0, y + 0, line, code)\n   display line :\n")
    # the C1 controls (28 Oct 2026, review)
    mutant("C1: not UTF-8 mode scrubs nothing", "sl_put", "      safe = convert(c1.from, c1.to, safe)\n", "")
    mutant("C1: the table stops at 158", "sl_put", "for ci = 128 to 159", "for ci = 128 to 158")
    mutant("C1: the table reaches 160", "sl_put", "for ci = 128 to 159", "for ci = 128 to 160")
    mutant("C1: the table maps to the wrong letter", "sl_put", "c1.to := char(ci - 64)", "c1.to := char(ci - 63)")
    mutant("C1: the table is not made once", "sl_put", "   if len(c1.from) < 32 then\n", "   if 1 then\n")
    mutant("C1: the locale is never resolved", "sl_put", "   if loc.mode # 1 and loc.mode # 2 then\n", "   if 0 then\n")
    mutant("C1: LANG is read before LC_ALL", "sl_put", "      loc = env('LC_ALL')\n      if loc = '' then loc = env('LC_CTYPE')\n      if loc = '' then loc = env('LANG')\n",
           "      loc = env('LANG')\n      if loc = '' then loc = env('LC_CTYPE')\n      if loc = '' then loc = env('LC_ALL')\n")
    mutant("C1: UTF8 is not recognized", "sl_put", "index(loc, 'UTF8', 1) > 0", "index(loc, 'UTF9', 1) > 0")
    mutant("C1: LINES does not count as UTF-8", "sl_put", "   if loc.mode = 1 or ln.on = 1 then\n", "   if loc.mode = 1 then\n")
    mutant("C1: a UTF-8 terminal is scrubbed byte for byte too", "sl_put", "   if loc.mode = 1 or ln.on = 1 then\n", "   if 0 then\n")
    mutant("C1: UTF-8, the pair range reaches C2 A0 (a no-break space)", "sl_put", "if c2 >= 128 and c2 <= 159 then", "if c2 >= 128 and c2 <= 160 then")
    mutant("C1: UTF-8, any byte after C2 is replaced", "sl_put", "if c2 >= 128 and c2 <= 159 then", "if c2 >= 128 then")
    mutant("C1: UTF-8, the search never moves on", "sl_put", "         k += 1\n", "         null\n")
    mutant("C1: UTF-8, the last byte is read past the end", "sl_put", "if p < n then c2 = seq(safe[p + 1, 1])", "c2 = seq(safe[p + 1, 1])")
    mutant("C1: UTF-8, the pair becomes one cell", "sl_put", "safe = safe[1, p - 1] : '.' : char(c2 - 64) : safe[p + 2, n]", "safe = safe[1, p - 1] : char(c2 - 64) : safe[p + 2, n]")
    mutant("C1: UTF-8, the pair is left in two halves", "sl_put", "safe = safe[1, p - 1] : '.' : char(c2 - 64) : safe[p + 2, n]", "safe = safe[1, p - 1] : '.' : char(c2 - 64) : safe[p + 1, n]")
    d2 = dict(dc)
    d2["tk_ai"] = 1
    mutant("a new DISPLAY in the library", "sl_put", "   return\nend\n", "   return\nend\n", d2)
    print("selftest: %d of %d mutants caught, %d missed" % (caught, caught + missed, missed))
    return 0 if missed == 0 else 1


if __name__ == "__main__":
    sys.exit(selftest() if "--selftest" in sys.argv else run())
