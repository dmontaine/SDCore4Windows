#!/usr/bin/env python3
"""test-tkbase-units.py - the toolkit's shared base, slice 1 (TK-0.1: the frame, the key table and the function-key row), read off the source as text.

  python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/test-tkbase-units.py
  python3 .../test-tkbase-units.py --selftest

No sudo, no install, no sd.  Exit 0 every check passed, 1 a check failed, 2 it could not run.  Written 22 Oct 2026 (S.75, plan .claude/plan-fullscreen-toolkit.md sections 2.1, 2.2, 2.12).

WHAT IT HOLDS: the order of what `$tk_open` does (a phantom has no terminal; the size is asked of the library's one check, 140 by 43 by the owner's ruling of 20 Oct; the audience
is tested BEFORE the screen is opened and before any data is read; only then the screen is taken, with the cursor lock) and that every failure returns instead of going on; that
`$tk_close` gives back the break setting and the screen; that the frame is drawn from the layout and writes the status line only when its text changed; that the function-key row
shows only the keys the focused pane uses, from the app's one key table; that no raw escape sequence is written (the library's styles and line characters only); that the
throw-away test app ends when its input ends; and that every program is internal, catalogued under its own name, and cites only messages of the toolkit's block that exist.

***IT READS SOURCE AS TEXT AND RUNS NOTHING***: that the frame appears where it should and the keys do what the labels say is `sandbox-tk-base.py`'s job, on a pseudo-terminal.

--selftest runs every check on the real files and then on a copy with one deliberate fault at a time: each must make a check fail.
"""

import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SDSYS = os.path.normpath(os.path.join(HERE, "..", "sdsys"))
BP = os.path.join(SDSYS, "gpl.bp")
NAMES = ["tk.h", "tk_open", "tk_close", "tk_frame", "tk_fkeys", "tk_keys", "sl_pickwin", "sl_slider", "sl_caption", "sl_check", "sl_color", "sl_selector", "sl_accel", "tool_keys"]
# the programs of the gate pages and the throw-away test app: checked when the tree has them (Core), skipped when it has not (Solo's carry 13 leaves them for the gate page, 22 Oct 26)
OPTIONAL = ["tk_gate_info", "tk_run", "tk_runx", "tk_gates", "tk_explain", "tk_confirm", "tk_wrap", "tool_tktest"]


def strip_bas(src):
    out = []
    for line in src.split("\n"):
        s = line.lstrip()
        if s.startswith("*") or s.startswith("!"):
            out.append("")
            continue
        cut = line.find(";*")
        out.append(line if cut < 0 else line[:cut])
    return "\n".join(out)


def squeeze(t):
    return re.sub(r"\s+", " ", t).strip()


def ordered(text, *needles):
    pos = -1
    for n in needles:
        p = text.find(n, pos + 1)
        if p < 0:
            return False
        pos = p
    return True


def checks(raw):
    names = NAMES + [n for n in OPTIONAL if n in raw]
    progs = [n for n in names if n != "tk.h"]
    code = {n: strip_bas(raw[n]) for n in names}
    sq = {n: squeeze(code[n]) for n in names}
    out = []

    def add(i, what, ok, detail=""):
        out.append((i, what, bool(ok), detail))

    def optadd(need, i, what, ok, detail=""):
        if need in raw:
            add(i, what, ok, detail)

    add("T0", "NULL CASE: every file of the base was found and none is trivially short (a check on nothing would pass)", all(len(raw[n]) > 300 for n in names),
        ", ".join("%s %d" % (n, len(raw[n])) for n in names))
    h = raw["tk.h"]
    add("T1", "tk.h fixes the minimum at 140 by 43 and names the chrome rows", re.search(r"\$define TK\.MINW\s+140\b", h) is not None and re.search(r"\$define TK\.MINH\s+43\b", h) is not None
        and "TK.C.YSTAT" in h and "TK.C.YBORD" in h and "TK.C.YKEYS" in h, "")
    op = sq["tk_open"]
    add("T2", "ORDER in $tk_open: a phantom is turned away, then the size is asked, then the audience, and only then the screen is taken, then the cursor lock",
        ordered(op, "system(25)", "call $sl_need(", "K$ADMINISTRATOR", "screen open", "call $sl_guardmode("), "")
    add("T3", "the size asked is TK.MINW by TK.MINH (never a number typed in the program) and so is the cursor lock's",
        "call $sl_need(app, TK.MINW, TK.MINH," in op and "call $sl_guardmode(app, TK.MINW, TK.MINH)" in op and not re.search(r"\b(140|42|43)\b", op), "")
    before = op.split("screen open", 1)[0]
    add("T4", "EVERY REFUSAL RETURNS before the screen is opened: the phantom, the size and the audience each set err and return",
        before.count("return") >= 3 and "err = " in before, "returns before screen open: %d" % before.count("return"))
    add("T5", "the audience test is asked of the kernel (K$ADMINISTRATOR, -1) and only for the administrator audience, before any data is read",
        re.search(r"audience = 'admin' then if not\(kernel\(K\$ADMINISTRATOR, -1\)\)", op) is not None, "")
    add("T6", "the break setting is saved before it is changed, and the screen is opened with line drawing only when the terminal says UTF-8",
        ordered(op, "pterm(PT$BREAK, -1)", "pterm(PT$BREAK, @false)", "screen open") and "screen open clear lines" in op and "UTF-8" in op, "")
    cl = sq["tk_close"]
    add("T7", "$tk_close gives the screen back, then the break setting it saved, then the break key", ordered(cl, "screen close", "pterm(PT$BREAK,", "break on"), "")
    fr = sq["tk_frame"]
    add("T8", "$tk_frame writes the status line in reverse video, only when its text changed since it was last written, and keeps the cursor where the widget left it",
        "attr 'reverse'" in fr and "if t = last.stat then" in fr and "call $sl_curat('get'" in fr and re.search(r"attr 'reverse' call \$sl_curat\('back'", fr) is not None, "")
    add("T9", "$tk_frame draws the border with the library's own line character ($sl_line 'h') and the function keys from $tk_fkeys, on rows the layout gives (never a literal row number)",
        "call $sl_line('h'," in fr and "call $tk_fkeys(" in fr and not re.search(r"\bat \d+,\d+\b", fr) and "TK.C.YKEYS" in fr and "TK.C.YBORD" in fr and "TK.C.YSTAT" in fr
        and "if ft # last.keys then" in fr and "if b # last.bord then" in fr
        and re.search(r"at 0,ybord call \$sl_curat\('back'", fr) is not None and re.search(r"at 0,ykeys attr 'bar' call \$sl_curat\('back'", fr) is not None, "")
    fk = sq["tk_fkeys"]
    add("T10", "the function-key row shows a key only if it is enabled and the focused pane uses it (a null pane list means every pane), in the order of the key table",
        "TK.K.PANES" in fk and "TK.K.ON" in fk and ("pane" in fk) and re.search(r"index\(@sm : .* : @sm, @sm : pane : @sm, 1\)", fk) is not None, "")
    ky = sq["tk_keys"]
    add("T11", "the key table has an add, a name and an action operation, and an action is looked up by key AND pane",
        all(("op = '%s'" % o) in ky for o in ("add", "name", "action")) and "TK.K.ACT" in ky and "pane" in ky, "")
    anycode = "\n".join(code[n] for n in progs)
    add("T12", "no program writes a raw escape sequence or a cursor code: the library's styles and line characters only",
        "char(27)" not in anycode.lower() and "@(-" not in anycode and "\\x1b" not in anycode and "crt @(" not in anycode, "")
    app = sq.get("tool_tktest", "")
    optadd("tool_tktest", "T13", "the test app's key loop treats the end of input as the end of the app (status() = ER$EOF is tested, never taken for an empty key) and leaves on the cursor lock's own way out",
        "ER$EOF" in app and "guardquit" in app and "call $tk_close(" in app, "")
    add("T14", "every program is internal and catalogued under its own name, and they are all different",
        all(re.search(r"^\$internal\b", raw[n], re.M) for n in progs) and len({re.search(r"^\$catalog (\S+)", raw[n], re.M).group(1) for n in progs if re.search(r"^\$catalog (\S+)", raw[n], re.M)}) == len(progs)
        and all(re.search(r"^\$catalog \$%s\b" % n, raw[n], re.M) for n in progs), "")
    cited = set()
    for n in progs:
        cited |= set(int(x) for x in re.findall(r"sysmsg\((\d+)", code[n]))
    have = {int(f) for f in os.listdir(os.path.join(SDSYS, "messages")) if f.isdigit()}
    add("T15", "the messages the base cites (%s) are all in the toolkit's block 12805 to 12854 and all exist" % sorted(cited), bool(cited) and all(12805 <= m <= 12854 and m in have for m in cited), sorted(m for m in cited if m not in have))
    rn = sq.get("tk_run", "")
    optadd("tk_run", "T16", "ORDER in $tk_run: an empty sentence, a too long one, a first word outside the tool's list and a bad character are each refused (and return) BEFORE the one EXECUTE",
        ordered(rn, "sysmsg(12809)", "sysmsg(12812)", "if not(ok.verb) then err = sysmsg(12810, verb)", "if index(good, w[j, 1], 1) = 0 then err = sysmsg(12811, w)",
                "execute s trapping aborts capturing out")
        and all(re.search(r"err = sysmsg\(%d[^)]*\) return" % m, rn) for m in (12809, 12810, 12811, 12812)), "")
    optadd("tk_run", "T17", "$tk_run runs only the sentence it checked (s), traps aborts, hands back the return code, and writes no audit line and no screen text",
        rn.count("execute ") == 1 and "execute sentence" not in rn and "status = @system.return.code" in rn and "K$AUDIT" not in rn and not re.search(r"\b(crt|display|print|screen)\b", rn), "")
    optadd("tk_run", "T18", "$tk_run allows exactly a-z, 0-9, dot, dash and underscore in a word, and the first word is compared whole against the tool's list, in lower case as typed",
        "good = 'abcdefghijklmnopqrstuvwxyz0123456789._-'" in rn and "field(allow, ' ', i) = verb and verb # ''" in rn, "")
    rx = sq.get("tk_runx", "")
    optadd("tk_runx", "T18b", "$tk_runx (23 Oct 26, tool.ai) is $tk_run for a verb that checks its own words: the same ORDER (an empty sentence, a too long one, a first word outside the tool's list and a bad character are each "
           "refused and return BEFORE the one EXECUTE of the checked sentence), the same trap and return code, no audit line and no screen text, and a word may hold a-z, A-Z, 0-9 and . _ : / @ + , - and nothing more",
        ordered(rx, "sysmsg(12809)", "sysmsg(12812)", "if not(ok.verb) then err = sysmsg(12810, verb)", "if index(good, w[j, 1], 1) = 0 then err = sysmsg(12811, w)", "execute s trapping aborts capturing out")
        and all(re.search(r"err = sysmsg\(%d[^)]*\) return" % m, rx) for m in (12809, 12810, 12811, 12812)) and rx.count("execute ") == 1 and "execute sentence" not in rx
        and "status = @system.return.code" in rx and "K$AUDIT" not in rx and not re.search(r"\b(crt|display|print|screen)\b", rx)
        and "good = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._:/@+,-'" in rx and "field(allow, ' ', i) = verb and verb # ''" in rx, "")
    gi = sq.get("tk_gate_info", "")
    gi_code =re.sub(r'rows<-1> = "[^"]*"', "rows<-1> = ROW", gi)          # the rows are prose: the words of a sentence are not statements
    optadd("tk_gate_info", "T19", "$tk_gate_info answers a list and one gate at a time from its rows, writes nothing and changes no state",
        "id = 'list' then" in gi and "convert('|', @fm, rows<i>)" in gi and gi_code.count("rows<-1> = ROW") >= 10
        and not re.search(r"\b(crt|display|print|screen|write|writev|kernel|execute)\b", gi_code), "")
    tg = sq.get("tk_gates", "")
    optadd("tk_gates", "T20", "ORDER in $tk_gates: the administrator is asked of the kernel (and refused with 12805) BEFORE the name is looked at, before the register is opened and before it is read; each refusal returns",
        ordered(tg, "if not(kernel(K$ADMINISTRATOR, -1)) then err = sysmsg(12805, 'tk_gates') return", "sysmsg(12813, name) return", "if index(good, name[j, 1], 1) = 0 then err = sysmsg(12813, name) return",
                "openpath @sdsys:@ds:'accounts' to acc.f else err = sysmsg(12814) return", "read rec from acc.f, name else", "call $tk_gate_info('list', ids)"), "")
    optadd("tk_gates", "T21", "$tk_gates only READS the register (no write, delete, lock or command), closes it on both paths, and puts nothing on the screen",
        not re.search(r"\b(write|writev|writeu|writet|delete|readu|execute|crt|display|print|screen|os\.execute)\b", re.sub(r"'[^']*'", "''", tg)) and tg.count("close acc.f") == 2, "")
    optadd("tk_gates", "T22", "$tk_gates: a gate with its default on (shared-read) is on unless the field says no, every other register gate only if it says yes, and a route gate on an account with no person is 'na' (never a membership test of nobody)",
        "if gi<TK.G.DEFAULT> = 'on' then state = (if raw # 'NO' then 1 else 0) end else state = (if raw = 'YES' then 1 else 0) end" in tg
        and "if atype = 'USER' then state = (if is_grp_member(user, gi<TK.G.GROUP>) then 1 else 0) end else state = 'na' end" in tg, "")
    cf = sq.get("tk_confirm", "")
    optadd("tk_confirm", "T23", "ORDER in $tk_confirm: the answer starts as 'cancel' and a session with no terminal returns at once; the box starts on Cancel (default 2); anything but Run returns BEFORE the name is asked for; a name that is not the one asked for, or an Esc at the name, never reaches 'run'; 'run' is set last",
        ordered(cf, "res = 'cancel'", "if system(25) then return", "default 2 returning b else b = 0", "if b # 1 then return", "returning ans then got = 1 else got = 0", "if not(got) then return",
                "if trim(ans) # typed then res = 'wrong'", "res = 'run'") and cf.count("res = 'run'") == 1, "")
    optadd("tk_confirm", "T24", "$tk_confirm shows the sentence wrapped at spaces but whole (a hard cut only when a word is longer than the line), wraps the lines the caller gave the same way (24 Oct 26: the box cut a long line at its edge; an empty line stays empty), and runs, reads and writes nothing",
        "wrapw" in cf and "call $tk_wrap(sentence, wrapw, pieces)" in cf and "body<-1> = ' ' : pieces<p>" in cf and "call $tk_wrap(lines<li>, wrapw, pieces)" in cf and "body := @fm : lines" not in cf and "rest[cut" not in cf and not re.search(r"\b(execute|write|writev|readu|delete|kernel|os\.execute|crt|display)\b", cf), "")
    tw = sq.get("tk_wrap", "")
    optadd("tk_wrap", "T24b", "$tk_wrap (23 Oct 26: the wrapping loop of $tk_confirm, moved so that the menu management page and the help box use it too) cuts at the last space that keeps a piece within the width, whole words, a hard cut only for a word longer than the width, and touches nothing outside its three arguments",
        "loop while rest # '' do" in tw and "loop while cut > 1 and rest[cut, 1] # ' ' do cut -= 1 repeat" in tw and "rest = trimf(rest[cut + 1, 99999])" in tw and "if cut <= 1 then cut = wrapw" in tw
        and not re.search(r"\b(execute|write|writev|readu|delete|kernel|os\.execute|crt|display|screen|openpath|open|read)\b", tw), "")
    ex = sq.get("tk_explain", "")
    optadd("tk_explain", "T25", "$tk_explain: a planned gate or one not in the table gives nothing; turning ON a gate delivered off carries the core-direction line (12822), turning OFF one delivered on carries 12823, a gate that reaches beyond SD carries 12824, and the typed name is asked only for turning ON a gate that reaches beyond SD",
        ordered(ex, "if gi = '' then return", "if gi<TK.G.STATUS> # 'built' then return", "sysmsg(12825,")
        and "if on and gi<TK.G.DEFAULT> = 'off' then lines<-1> = sysmsg(12822)" in ex and "if not(on) and gi<TK.G.DEFAULT> = 'on' then lines<-1> = sysmsg(12823)" in ex
        and "if gi<TK.G.BEYOND> = 1 then lines<-1> = sysmsg(12824)" in ex and "if on and gi<TK.G.BEYOND> = 1 then typed = 1" in ex and ex.count("typed = 1") == 1
        and not re.search(r"\b(execute|write|writev|readu|openpath|open|read|kernel|screen|crt|display)\b", ex), "")
    pw = sq["sl_pickwin"]
    add("T26", "ORDER in $sl_pickwin: a session with no terminal returns at once, the screen under the window is saved before the frame is drawn and put back (and the screen given back) after the loop, "
        "and an Esc, an input that ended and the cursor lock's own way out all end as a cancel",
        ordered(pw, "if system(25) then return", "call $sl_region('save'", "call $sl_frame(", "call $sl_key('', k)", "call $sl_region('restore'", "call $sl_scr('put', scr)")
        and "if k = '' or k = 'guardquit' then k = 'esc'" in pw and "case k = 'esc' st = 'cancel'" in pw
        and "call $sl_scr('put', scr) if fmode then clearselect 10 if st = 'done' then status = 0" in pw, "")
    add("T27", "$sl_pickwin answers entries by their NUMBER IN THE LIST (oi), never by their place among the entries the filter shows, and keeps picks by that number; Enter with picks answers the picks, "
        "without them the entry the person is on, and with nothing shown answers nothing",
        "oi = i if fo then oi = vis<1, i> return" in pw and "ret = oi if fmode then ret = items<oi, 1> st = 'done'" in pw and "pk = oi if fmode then pk = items<oi, 1> locate pk in picked<1, 1> setting at then del picked<1, at> end else picked<1, -1> = pk" in pw
        and "if multi and picked # '' then ret = picked st = 'done' end else if cur >= 1 then" in pw
        and "ret = cur" not in pw and "picked<1, -1> = cur" not in pw, "")
    add("T28", "$sl_pickwin filters on the name and the description together, without regard to case; Backspace and Ctrl-U widen it; ? is the help line and is never part of the filter; "
        "in a multi window the space picks; a printable character is added to the filter only after those cases",
        "if index(upcase(items<i, 1> : ' ' : items<i, 2>), uf, 1) then vis<1, -1> = i" in pw and pw.count("uf = upcase(filt)") == 2
        and ordered(pw, "case k = 'bs'", "case k = 'ctrl-u'", "case k = '?'", "case k = ' ' and multi", "case len(k) = 1 and seq(k) >= 32 and seq(k) < 127"), "")
    add("T29", "$sl_pickwin only draws and reads keys, and with a file reads ids and records: it runs, writes, locks and opens nothing",
        not re.search(r"\b(execute|write|writev|readu|delete|openpath|open|kernel|os\.execute|crt|display)\b", re.sub(r"'[^']*'", "''", pw)) and pw.count("read rec from src, id then") == 1
        and pw.count("readnext id from 10") == 1 and pw.count("sselect src to 10") == 1, "")
    add("T30", "$sl_pickwin, paged source: one read looks at the page, the scan and the cache numbers at most and gives up when the ids are done; a record is read only when a description is asked for; the filter "
        "is applied while reading; the cache grows only there; End reads on until the ids are done or the cache is full; the select list is cleared on every way out; a new filter starts the read again",
        "loop while got < page and scanned < scancap and n < cachecap do readnext id from 10 else exhausted = 1 ; exit" in pw and "if exhausted or n >= cachecap then return" in pw
        and "if dfield > 0 then read rec from src, id then" in pw and "if filt # '' then keepit = index(upcase(id : ' ' : desc), uf, 1)" in pw and pw.count("n += 1") == 1
        and "loop while not(exhausted) and n < cachecap do gosub fetch repeat" in pw and pw.count("clearselect 10") == 3 and "clearselect 10 sselect src to 10" in pw
        and "if fmode and cur >= n then gosub fetch" in pw and "if fmode and cur + lh - 1 > n then gosub fetch" in pw
        and "if fmode and not(exhausted) and cur > n - lh then gosub fetch" in pw and "if fmode then gosub file.refilter return end" in pw, "")
    sl = sq["sl_slider"]
    add("T31", "$sl_slider: the value is 0 or 1 from the start; the space bar slides it the other way, Left sets it off and Right sets it on (each 'handled'), any other key is 'unhandled' with its name; "
        "a click on a word sets that state and a click on the text slides it the other way; it is drawn [OFF | on] off and [off | ON] on (the owner's look) with the words the program chose, the word in force "
        "in the style attr (bold unless the program says another) unless the switch has the focus, with the cursor on that word; it draws, reads and writes nothing else",
        "if w{'value'} + 0 # 0 then v = 1 w{'value'} = v" in sl and "if w{'attr'} = '' then w{'attr'} = 'bold'" in sl
        and "if w{'offw'} = '' then w{'offw'} = 'off' if w{'onw'} = '' then w{'onw'} = 'on'" in sl
        and "case key = ' ' ret = 'handled' v = 1 if w{'value'} then v = 0 w{'value'} = v gosub paint" in sl
        and "case key = 'left' ret = 'handled' w{'value'} = 0 gosub paint" in sl and "case key = 'right' ret = 'handled' w{'value'} = 1 gosub paint" in sl
        and "case 1 ret = 'unhandled' : @fm : key" in sl and sl.count("case key = ") == 3
        and ("lo = len(w{'offw'}) ln = len(w{'onw'}) call $sl_caption(w{'place'}, lo + ln + 5, w{'label'}, geom) rel = key<3> - w{'ax'} - geom<1, SL.CAP.CX> rrow = key<4> - w{'ay'} - geom<1, SL.CAP.CY> "
             "begin case case rrow = 0 and rel >= 0 and rel <= lo + 2 w{'value'} = 0 case rrow = 0 and rel >= 0 and rel <= lo + ln + 4 w{'value'} = 1 case 1 v = 1 if w{'value'} then v = 0 w{'value'} = v end case gosub paint") in sl
        and ("lo = len(w{'offw'}) ln = len(w{'onw'}) sw = '[' : upcase(w{'offw'}) : ' | ' : downcase(w{'onw'}) : ']' a0 = 1 al = lo if w{'value'} then "
             "sw = '[' : downcase(w{'offw'}) : ' | ' : upcase(w{'onw'}) : ']' a0 = lo + 4 al = ln end") in sl
        and "call $sl_caption(w{'place'}, len(sw), w{'label'}, geom)" in sl and "call $sl_caption(w{'place'}, len(w{'offw'}) + len(w{'onw'}) + 5, t, geom)" in sl
        and "if not(w{'focused'}) then call $sl_attr(w{'attr'}, ac) for k = 1 to al cells[cx + a0 + k, 1] = ac next k end" in sl and "call $sl_curat(w{'ax'} + cx + a0, w{'ay'} + cy)" in sl
        and not re.search(r"\b(execute|write|writev|readu|delete|openpath|open|read|kernel|os\.execute|crt|display)\b", re.sub(r"'[^']*'", "''", sl)), "")
    co = sq["sl_color"]
    add("T34", "$sl_color: a null pair of colours changes nothing; the colours are asked of $sl_theme as a user style; 'none' (no colour on this terminal) is ignored, 'full' and 'bad' refuse the control; the control gets ccode; "
        "only an entry and a combo box also get cfocus (the same colours underlined), so that they keep their colours while focused",
        "if trim(fg) = '' and trim(bg) = '' then return" in co and "call $sl_theme('slot', fg, bg, '', '', c1)" in co and "case c1 = 'none' return" in co and "case c1 = 'full' or c1 = 'bad' st = 1 return" in co
        and "w{'ccode'} = c1" in co and "if t = 'entry' or t = 'combo' then call $sl_theme('slot', fg, bg, 'underline', '', c2)" in co and "if c2 # 'none' then w{'cfocus'} = c2" in co
        and co.count("w{'cfocus'}") == 1, "")
    th, sh = squeeze(strip_bas(raw["sl_theme"])), raw["sl.h"]
    codes = re.search(r"\$define SL\.CODES\s+'([^']+)'", sh)
    codes = codes.group(1) if codes else ""
    add("T35", "the colour slots: SL.CODES has 46 different letters, the last sixteen (ACDEFHIJKLMNOQRS) being the user styles; $sl_theme names them user1 to user16 after the thirty styles it had, "
        "keeps them across a theme change (saved before clear.defs, put back before the sequences are built), empties them at SCREEN CLOSE, and gives out the slot that already holds a pair or the first free one, refusing when none is",
        len(codes) == 46 and len(set(codes)) == 46 and codes.endswith("ACDEFHIJKLMNOQRS") and "for q = 1 to 16 th.names := @fm : 'user' : q next q" in th
        and "keepu<s> = th.defs<s>" in th and ordered(th, "keepu = ''", "gosub clear.defs", "if keepu<s> # '' then th.defs<s> = keepu<s>", "gosub build.seqs")
        and "th.defs<s> = ''" in th and ordered(th, "case op = 'reset'", "th.defs<s> = ''", "gosub set.theme")
        and "if th.defs<s, 4> = skey and have = 0 then have = s" in th and "if th.defs<s, 4> = '' and free = 0 then free = s" in th and "case free = 0 ret = 'full'" in th
        and "th.defs<i, 4> = skey ucode = th.codes[i, 1] gosub build.seqs ret = ucode" in th and "if @(-37, 7) = '' or @(-38, 0) = '' then ret = 'none'" in th, "")
    cp = sq["sl_caption"]
    add("T32", "$sl_caption: the place is left unless it is right, above or below (anything else, or nothing, is left); left and right are one row, the label and the control a space apart, the control "
        "on the right of the label for left and on the left for right; above and below are two rows, as wide as the wider of the two, the control under the label for above and over it for below; "
        "no label gives the control alone; it draws and reads nothing",
        ordered(cp, "p = downcase(place)", "if lw > 0 then", "case p = 'right'", "case p = 'above'", "case p = 'below'", "case 1")
        and "gw = lw + 1 + cw cx = lw + 1" in cp and "gw = cw + 1 + lw lx = cw + 1" in cp and cp.count("gh = 2") == 2 and "cy = 1" in cp and "ly = 1" in cp
        and cp.count("if lw > gw then gw = lw") == 2 and "geom = gw : @vm : gh : @vm : cx : @vm : cy : @vm : lx : @vm : ly" in cp
        and not re.search(r"\b(execute|write|writev|readu|delete|openpath|open|read|kernel|os\.execute|crt|display|call)\b", re.sub(r"'[^']*'", "''", cp)), "")
    ck = sq["sl_check"]
    add("T33", "$sl_check: the box and the label are drawn where $sl_caption says (three cells for the box), row by row, the whole in the focus style while focused, the cursor in the box; the space bar and "
        "a click anywhere on it, the label included, check or uncheck it; any other key is 'unhandled'",
        "call $sl_caption(w{'place'}, 3, t, geom)" in ck and "call $sl_caption(w{'place'}, 3, w{'label'}, geom)" in ck
        and "if r = cy then rowtext[cx + 1, 3] = mark" in ck and "if r = ly and w{'label'} # '' then rowtext[lx + 1, len(w{'label'})] = w{'label'}" in ck
        and "call $sl_curat(w{'ax'} + cx + 1, w{'ay'} + cy)" in ck and "if key<1> = 'press' then v = 1 if w{'value'} then v = 0 w{'value'} = v gosub paint" in ck
        and "if key = ' ' then ret = 'handled'" in ck and "ret = 'unhandled' : @fm : key" in ck and "if w{'value'} + 0 # 0 then v = 1" in ck, "")
    se = sq["sl_selector"]
    add("T36", "$sl_selector: the value is brought into range (1 to the number of words); Right and Left step and stop at the last and the first, Home and End go to them, the space bar steps and "
        "after the last goes to the first (each 'handled'), any other key is 'unhandled' with its name; a click on a word (and the space after it, and the bracket at either end) chooses it, a click on the "
        "label the next word; it is drawn [blue | GREEN | red] with the word in force in capitals, the others in lower case, the word in the style attr (bold unless the program says another) unless it has "
        "the focus, the cursor on that word, the label where $sl_caption says; it draws, reads and writes nothing else",
        "v = w{'value'} + 0 if v < 1 or v > n then v = 1 w{'value'} = v" in se and "if w{'attr'} = '' then w{'attr'} = 'bold'" in se
        and "case key = ' ' ret = 'handled' gosub nextword gosub paint" in se and "case key = 'right' ret = 'handled' if v < n then w{'value'} = v + 1 gosub paint" in se
        and "case key = 'left' ret = 'handled' if v > 1 then w{'value'} = v - 1 gosub paint" in se and "case key = 'home' ret = 'handled' w{'value'} = 1 gosub paint" in se
        and "case key = 'end' ret = 'handled' w{'value'} = n gosub paint" in se and "case 1 ret = 'unhandled' : @fm : key" in se and se.count("case key = ") == 5
        and "nextword: v = w{'value'} + 0 + 1 if v > n then v = 1 w{'value'} = v return" in se
        and ("if rrow = 0 and rel >= 0 and rel < len(sw) then chosen = n for j = n to 1 step -1 if rel <= lastc<j> + 1 then chosen = j next j w{'value'} = chosen end else gosub nextword end") in se
        and "rel = key<3> - w{'ax'} - geom<1, SL.CAP.CX> rrow = key<4> - w{'ay'} - geom<1, SL.CAP.CY>" in se
        and ("sw = '[' a0 = 1 al = 0 lastc = '' for j = 1 to n wd = items<1, j, 1> if j = v then wd = upcase(wd) a0 = len(sw) al = len(wd) end else wd = downcase(wd) end "
             "lastc<j> = len(sw) + len(wd) - 1 sw := wd if j < n then sw := ' | ' next j sw := ']' return") in se
        and se.count("call $sl_caption(w{'place'}, len(sw), w{'label'}, geom)") == 2 and "gosub layout call $sl_caption(w{'place'}, len(sw), t, geom)" in se
        and "if w{'ccode'} # '' then code = w{'ccode'} if w{'focused'} then call $sl_attr('highlight', code)" in se
        and "if not(w{'focused'}) then call $sl_attr(w{'attr'}, ac) for k = 1 to al cells[cx + a0 + k, 1] = ac next k end" in se and "call $sl_curat(w{'ax'} + cx + a0, w{'ay'} + cy)" in se
        and not re.search(r"\b(execute|write|writev|readu|delete|openpath|open|read|kernel|os\.execute|crt|display)\b", re.sub(r"'[^']*'", "''", se)), "")
    ac = sq["sl_accel"]
    add("T37", "$sl_accel: no key means no accelerator; the key is lower-cased and a + is a -; f1 to f12 (a whole number, no leading zero), ctrl-a to ctrl-z except ctrl-h, ctrl-i, ctrl-j and ctrl-m, and alt-a to alt-z "
        "and alt-0 to alt-9 are taken (w{'accel'} is the name $sl_key reports), anything else is status 1; it draws, reads and writes nothing",
        "st = 0 if trim(accel) = '' then return" in ac and "a = convert('+', '-', downcase(trim(accel)))" in ac and "case a[1, 1] = 'f' and tail # '' and num(tail)" in ac
        and "if tail + 0 >= 1 and tail + 0 <= 12 and int(tail) = tail + 0 and len(tail) = len(tail + 0) then ok = 1" in ac
        and "case len(a) = 6 and a[1, 5] = 'ctrl-' if index('abcdefghijklmnopqrstuvwxyz', a[6, 1], 1) and index('hijm', a[6, 1], 1) = 0 then ok = 1" in ac
        and "case len(a) = 5 and a[1, 4] = 'alt-' if index('abcdefghijklmnopqrstuvwxyz0123456789', a[5, 1], 1) then ok = 1" in ac and "if ok then w{'accel'} = a else st = 1" in ac
        and not re.search(r"\b(execute|write|writev|readu|delete|openpath|open|read|kernel|os\.execute|crt|display|call)\b", re.sub(r"'[^']*'", "''", ac)), "")
    kk, kc, kb = squeeze(strip_bas(raw["sl_key"])), squeeze(strip_bas(raw["_keycode"])), squeeze(strip_bas(raw["_bindkey"]))
    add("T38", "an Alt-letter: $sl_key asks KEYCODE for it (BINDKEY(, -7)) for the one read and gives the state back (-7 if it was on, else -8), and names Esc and one character alt- and the character in lower case "
        "before it takes a longer string for a binding's; KEYCODE returns an unbound Esc and one printable character as the two characters only when kc.alt is set, before it rings the bell; BINDKEY -7 sets and -8 "
        "clears kc.alt and each answers the old state; kc.alt is in the common block",
        "alt.was = bindkey('', -7) k = keycode(1) kst = status() if alt.was then x = bindkey('', -7) else x = bindkey('', -8) set.status kst" in kk
        and ordered(kk, "case len(k) = 2 and k[1,1] = char(27) name = 'alt-' : downcase(k[2,1])", "case len(k) > 1 name = k")
        and "if kc.alt and len(key.string) = 2 and key.string[1,1] = char(27) then if seq(key.string[2,1]) > 32 and seq(key.string[2,1]) < 127 then return value key.string end display @sys.bell" in kc
        and "case action = -7 n = kc.alt + 0 kc.alt = @true return value n case action = -8 n = kc.alt + 0 kc.alt = @false return value n" in kb
        and "kc.alt" in raw["keycode.h"], "")
    fm = squeeze(strip_bas(raw["sl_form"]))
    add("T39", "the form's accelerators: before the focused control sees a key named alt-, ctrl- or f and a number it looks for a control (find.accel): the first, in the order added, that is on the page, not disabled "
        "and focusable (or a label), whose ACCEL is the key or whose & letter is the Alt-letter; a label hands the focus to the next control that can have it; run.accel gives that control the focus, "
        "presses a button, turns a check box, slider or selector over (as the space bar would) and makes the change event wait.event reports before the focus event; a label's letter is read only when it is created, "
        "a button's Alt-letter only when marked with & (its plain mnemonic is separate), a check box, slider and selector keep theirs",
        "f{'achg'} = '' if len(key) >= 2 and (key[1, 4] = 'alt-' or key[1, 5] = 'ctrl-' or (key[1, 1] = 'f' and len(key) <= 3 and num(key[2, 9]))) then gosub find.accel if ni > 0 then gosub run.accel return end end nw = inmat(f{'widgets'})" in fm
        and ordered(fm, "if key = 'guardquit' then", "f{'achg'} = ''", "gosub find.accel", "nw = inmat(f{'widgets'}) fi = f{'focus'} + 0")
        and ("find.accel: ni = 0 nw = inmat(f{'widgets'}) for i = 1 to nw w = f{'widgets', i} gosub on.page if vis and w{'disabled'} + 0 = 0 and ancdis = 0 and (w{'focusable'} + 0 = 1 or w{'type'} = 'label') then "
             "if w{'accel'} = key then ni = i if len(key) = 5 and key[1, 4] = 'alt-' and w{'amn'} # '' and w{'amn'} = upcase(key[5, 1]) then ni = i if ni > 0 then exit end next i") in fm
        and "if w{'type'} = 'label' then lab = ni ni = 0 for k = 1 to nw lab += 1 if lab > nw then lab = 1 i = lab gosub can.focus if cf then ni = lab ; exit next k if ni = 0 then ni = -1" in fm
        and ("run.accel: ret = 'handled' if ni < 0 then return hit = ni if hit # f{'focus'} + 0 then gosub set.focus wi = hit w = f{'widgets', hit} wt = w{'type'} v1 = w{'value'} begin case case wt = 'button' "
             "gosub press.button case wt = 'check' or wt = 'slider' or wt = 'selector' wop = 'key' ; wkey = ' ' gosub call.widget gosub after.widget if w{'value'} # v1 then f{'achg'} = hit end case gosub park.cursor return") in fm
        and "case f{'achg'} # '' w = f{'widgets', f{'achg'}} evt = 'change' ; eid = w{'id'} ; edata = w{'value'} case fi1 # fi0 and fi1 >= 1" in fm
        and all("w{'amn'} = upcase(t[p + 1, 1])" in squeeze(strip_bas(raw[n])) for n in ("sl_check", "sl_slider", "sl_selector", "screen_label")) and squeeze(strip_bas(raw["sl_button"])).count("w{'amn'} = w{'mn'}") == 1 and "w{'amn'} = '' w{'apos'} = 0 if p and p < len(t) then w{'mn'} = upcase(t[p + 1, 1]) w{'amn'} = w{'mn'}" in squeeze(strip_bas(raw["sl_button"]))
        and "amn" not in raw["sl_label"] and "p = index(t, '&', 1)" in squeeze(strip_bas(raw["screen_label"])), "")
    tk = sq["tool_keys"]
    add("T40", "tool.keys (TK-1): an app for everyone (audience null), that opens the base first and prints what it refuses; its keys are Ctrl-L, Ctrl-R, Ctrl-T and Ctrl-Q; every key is recorded BEFORE the table acts on it; "
        "the end of the input and the cursor lock's own way out end it, in both reading modes, and every way out is $tk_close; names mode reads with SCREEN KEY, raw mode with KEYIN (a second at a time, a burst at 0.05) "
        "and asks the library for the size when the window changed; the cursor waits at the start of the status line (so a smaller window shows the lock); a resize raises the frame's generation; "
        "the grid is 52 keys (ctrl-h, i, j and m are other keys); it reads and writes no file, runs no command and asks no gate",
        "call $tk_open('tool.keys', '', ctx, err) if err # '' then display err stop end" in tk
        and ordered(tk, "call $tk_keys('add', keys, 'ctrl-l', 'clear', 'clear', '', 1)", "call $tk_keys('add', keys, 'ctrl-r', 'raw/names', 'raw', '', 1)", "call $tk_keys('add', keys, 'ctrl-t', 'theme', 'theme', '', 1)",
                "call $tk_keys('add', keys, 'ctrl-q', 'quit', 'quit', '', 1)") and tk.count("call $tk_keys('add'") == 4
        and "gosub record call $tk_keys('action', keys, nm, pane, act, '', '')" in tk
        and "repeat call $tk_close(ctx) stop" in tk and "if ended then exit if nm = 'guardquit' then exit" in tk
        and tk.count("if status() = ER$EOF then") == 2 and "if status() = ER$EOF then ended = 1 exit end" in tk
        and "if rawmode then gosub read.raw else gosub read.names" in tk and "screen key returning nm" in tk
        and "c = keyin(1)" in tk and "loop c = keyin(0.05) until c = '' do raw := c repeat" in tk
        and "if @crtwide : ',' : @crthigh # lastsz then screen key timeout 1 returning nm exit end" in tk
        and "call $sl_curat(0, ctx<TK.C.YSTAT>)" in tk
        and "if nm = 'resize' then gosub redraw.all" in tk and "redraw.all: gen += 1 ctx<TK.C.GEN> = gen gosub draw.all return" in tk
        and "if i # 8 and i # 9 and i # 10 and i # 13 then gnames := @fm : 'ctrl-' : downcase(char(i + 64))" in tk and "gnames := @fm : 'alt-x' : @fm : 'char' : @fm : 'mouse'" in tk
        and "if len(nm) = 1 then cell = 'char' if nm[1, 4] = 'alt-' then cell = 'alt-x'" in tk
        and "case mev<1> = 'wheel' and mev<2> = 'up' ; mu += 1 case mev<1> = 'wheel' ; mdn += 1" in tk
        and "ins line before logl<1> if dcount(logl, @fm) > LOGN then del logl<LOGN + 1>" in tk
        and "call $sl_theme('slot', 'white', 'black', '', '', cs) colour = (if cs = 'none' then 'no' else 'yes')" in tk
        and not re.search(r"\b(execute|write|writev|readu|delete|openpath|open|openseq|readseq|kernel|os\.execute|clearfile)\b", re.sub(r"'[^']*'", "''", tk)), "")
    # TK-0.12, the marked letter drawn: each control keeps where the letter is in its label (apos, 1-based, 0 when there is no &) and paints that cell in the hotkey style
    HK_INIT = "w{'amn'} = '' w{'apos'} = 0 if p and p < len(t) then w{'amn'} = upcase(t[p + 1, 1]) w{'apos'} = p t = t[1, p - 1] : t[p + 1, 99999] end w{'label'} = t"
    HK_ROW = ("gosub hotkey for r = 0 to gh - 1 rowtext = space(gw) cells = str(code, gw) if r = cy then ", "if r = ly and w{'label'} # '' then rowtext[lx + 1, len(w{'label'})] = w{'label'} "
              "if hk then cells[lx + w{'apos'}, 1] = hcode end call $sl_put(scr, w{'ax'} + 0, w{'ay'} + r, rowtext, cells) next r")
    HK_PARA = ("hotkey: hk = 0 if not(w{'focused'}) and w{'disabled'} + 0 = 0 and w{'apos'} + 0 > 0 and w{'apos'} + 0 <= len(w{'label'}) then hk = 1 call $sl_attr('hotkey', hcode) end return end")
    bt, lb, sl_, ss = (squeeze(strip_bas(raw[n])) for n in ("sl_button", "sl_label", "screen_label", "screen_set"))
    add("T41", "the marked letter is drawn: the check box, slider and selector keep its place in the label with the & out (apos, 0 without one), find hotkey once before the rows and, when the control "
        "has not the focus and is not disabled and the place is in the label, put the hotkey style on that one cell of the label's row (counted from the label's own column); the button the same in '[ label ]' "
        "(two cells in), but not for its plain mnemonic; a label (SCREEN LABEL) keeps the place, draws it when it is in the text and in the width and is not disabled, and SCREEN SET ... TEXT clears it",
        all(HK_INIT in s_ and HK_PARA in s_ and HK_ROW[0] in s_ and HK_ROW[1] in s_ and s_.count("call $sl_attr('hotkey', hcode)") == 1 and s_.count("w{'apos'}") == 5
            for n_, s_ in (("sl_check", ck), ("sl_slider", sl), ("sl_selector", se)))
        and "w{'amn'} = '' w{'apos'} = 0 if p and p < len(t) then w{'mn'} = upcase(t[p + 1, 1]) w{'amn'} = w{'mn'} w{'apos'} = p t = t[1, p - 1] : t[p + 1, 99999] end else w{'mn'} = upcase(t[1, 1]) end w{'label'} = t" in bt
        and ("rowtext = '[ ' : w{'label'} : ' ]' cells = str(code, len(rowtext)) if not(w{'focused'}) and w{'disabled'} + 0 = 0 and w{'apos'} + 0 > 0 and w{'apos'} + 0 <= len(w{'label'}) then "
             "call $sl_attr('hotkey', hcode) cells[w{'apos'} + 2, 1] = hcode end call $sl_put(scr, w{'ax'} + 0, w{'ay'} + 0, rowtext, cells) if w{'focused'} then call $sl_curat(w{'ax'} + 2, w{'ay'} + 0) return") in bt
        and bt.count("w{'apos'}") == 5
        and ("cells = str(code, len(t)) if w{'disabled'} + 0 = 0 and w{'apos'} + 0 > 0 and w{'apos'} + 0 <= len(w{'text'}) and w{'apos'} + 0 <= len(t) then call $sl_attr('hotkey', hcode) "
             "cells[w{'apos'} + 0, 1] = hcode end call $sl_put(scr, w{'ax'} + 0, w{'ay'} + 0, t, cells)") in lb and lb.count("w{'apos'}") == 4
        and "w{'amn'} = upcase(t[p + 1, 1]) w{'apos'} = p t = t[1, p - 1] : t[p + 1, 99999] end w{'text'} = t" in sl_ and sl_.count("w{'apos'}") == 1
        and "w{'text'} = text if wt = 'label' then w{'apos'} = 0 call $sl_widget_init(w) end" in ss and ss.count("w{'apos'}") == 1, "")
    return out


EXTRA = ["sl_form", "sl_key", "_keycode", "_bindkey", "keycode.h", "screen_label", "screen_set", "sl_button", "sl_label", "sl_theme", "sl.h"]             # read for the colour slots; not checked as toolkit programs (the theme writes terminal sequences, which T12 forbids the base to do)


def load():
    raw = {}
    for n in NAMES + OPTIONAL + EXTRA:
        p = os.path.join(BP, n)
        if not os.path.isfile(p):
            if n in OPTIONAL:
                continue                  # this tree has no gate pages (Solo)
            raise FileNotFoundError(p)
        with open(p, encoding="latin-1") as f:
            raw[n] = f.read()
    return raw


def run(raw, quiet=False):
    rows = checks(raw)
    bad = [r for r in rows if not r[2]]
    if not quiet:
        for i, what, ok, detail in rows:
            print("  [%s] %s %s%s" % ("PASS" if ok else "FAIL", i, what, ("   <- " + str(detail)) if (detail and not ok) else ""))
    return rows, bad


MUT = [
    ("tk_open", "the audience is tested after the screen is taken", "audience = 'admin' then", "audience = 'admin' and 0 then"),
    ("tk_open", "a refusal does not return", "err = sysmsg(12806, app)\n      return", "err = sysmsg(12806, app)"),
    ("tk_open", "the size is typed into the program", "call $sl_need(app, TK.MINW, TK.MINH,", "call $sl_need(app, 140, 42,"),
    ("tk_open", "the cursor lock is not asked for", "call $sl_guardmode(app, TK.MINW, TK.MINH)", "null"),
    ("tk_open", "the break setting is changed before it is saved", "saved.trap = pterm(PT$BREAK, -1)", "saved.trap = 1"),
    ("tk_close", "the break setting is not given back", "void pterm(PT$BREAK, ctx<TK.C.TRAP>)", "null"),
    ("tk_frame", "the status line is written every time", "if t = last.stat then", "if 0 then"),
    ("tk_frame", "the status line moves the cursor", "screen text t at 0,ystat attr 'reverse'\n      call $sl_curat('back', keep.cur)", "screen text t at 0,ystat attr 'reverse'"),
    ("tk_frame", "the function keys are redrawn on every call", "if ft # last.keys then", "if 1 then"),
    ("tk_frame", "the status line is not reverse video", "screen text t at 0,ystat attr 'reverse'", "screen text t at 0,ystat"),
    ("tk_frame", "the border is a typed character", "call $sl_line('h', 0, hc)", "hc = '-'"),
    ("tk_fkeys", "a key is shown on every pane", "index(@sm : panes : @sm, @sm : pane : @sm, 1)", "1"),
    ("tk_keys", "an action is looked up by key alone", "op = 'action'", "op = 'actionx'"),
    ("tool_tktest", "end of input is taken for an empty key", "ER$EOF", "ER$XXX"),
    ("tk_open", "an escape sequence is written", "screen open clear lines", "crt char(27) : '[2J' ; screen open clear lines"),
    ("tk_run", "the tool's list is not asked", "if not(ok.verb) then", "if 0 then"),
    ("tk_run", "the characters of a word are not checked", "if index(good, w[j, 1], 1) = 0 then", "if 0 then"),
    ("tk_run", "the raw sentence is run, not the checked one", "execute s trapping aborts capturing out", "execute sentence trapping aborts capturing out"),
    ("tk_run", "aborts are not trapped", "execute s trapping aborts capturing out", "execute s capturing out"),
    ("tk_run", "a refused sentence does not return", "err = sysmsg(12810, verb)\n      return", "err = sysmsg(12810, verb)"),
    ("tk_run", "an extra character is allowed (the semicolon)", "0123456789._-'", "0123456789._-;'"),
    ("tk_run", "the first word is matched as a prefix", "field(allow, ' ', i) = verb and verb # ''", "field(allow, ' ', i)[1, len(verb)] = verb"),
    # 23 Oct 26: $tk_runx, the wider word set of tool.ai
    ("tk_runx", "the tool's list is not asked", "if not(ok.verb) then", "if 0 then"),
    ("tk_runx", "the characters of a word are not checked", "if index(good, w[j, 1], 1) = 0 then", "if 0 then"),
    ("tk_runx", "the raw sentence is run, not the checked one", "execute s trapping aborts capturing out", "execute sentence trapping aborts capturing out"),
    ("tk_runx", "a semicolon is allowed in a word", "0123456789._:/@+,-'", "0123456789._:/@+,-;'"),
    ("tk_runx", "a space is allowed in a word", "0123456789._:/@+,-'", "0123456789._:/@+,- '"),
    ("tk_runx", "a refused sentence does not return", "err = sysmsg(12811, w)\n            return", "err = sysmsg(12811, w)"),
    ("tk_gates", "the administrator is not asked", "if not(kernel(K$ADMINISTRATOR, -1)) then", "if 0 then"),
    ("tk_gates", "the administrator refusal does not return", "err = sysmsg(12805, 'tk_gates')\n      return", "err = sysmsg(12805, 'tk_gates')"),
    ("tk_gates", "the name is not checked", "if index(good, name[j, 1], 1) = 0 then", "if 0 then"),
    ("tk_gates", "a missing account leaves the register open", "      close acc.f\n      err = sysmsg(12813, name)", "      err = sysmsg(12813, name)"),
    ("tk_gates", "shared-read needs the word yes like the rest", "state = (if raw # 'NO' then 1 else 0)", "state = (if raw = 'YES' then 1 else 0)"),
    ("tk_gates", "every gate is on unless the field says no", "state = (if raw = 'YES' then 1 else 0)\n            end", "state = (if raw # 'NO' then 1 else 0)\n            end"),
    ("tk_gates", "a route is looked up for an account with no person", "if atype = 'USER' then", "if 1 then"),
    ("tk_gates", "the register is written", "   close acc.f\n\n   grp = rec<ACC$GROUP>", "   close acc.f\n   write rec to acc.f, name\n\n   grp = rec<ACC$GROUP>"),
    ("tk_confirm", "the answer starts as run", "   res = 'cancel'\n   msg = sysmsg(12826)", "   res = 'run'\n   msg = sysmsg(12826)"),
    ("tk_confirm", "a session with no terminal is asked", "if system(25) then return", "if 0 then return"),
    ("tk_confirm", "the box starts on Run", "default 2 returning b else b = 0", "default 1 returning b else b = 0"),
    ("tk_confirm", "Cancel does not return", "if b # 1 then return", "if 0 then return"),
    ("tk_confirm", "an Esc at the name goes on", "if not(got) then return", "if 0 then return"),
    ("tk_confirm", "the name is not compared", "if trim(ans) # typed then", "if 0 then"),
    ("tk_confirm", "the name is compared without regard to case", "if trim(ans) # typed then", "if upcase(trim(ans)) # upcase(typed) then"),
    ("tk_wrap", "the sentence is cut instead of wrapped", "rest = trimf(rest[cut + 1, 99999])", "rest = ''"),
    ("tk_wrap", "a word is cut at the wrong place", "loop while cut > 1 and rest[cut, 1] # ' ' do cut -= 1 repeat", "loop while cut > 1 and rest[cut, 1] # 'x' do cut -= 1 repeat"),
    ("tk_wrap", "the wrapper writes something", "   out<-1> = piece\n", "   out<-1> = piece\n   write piece to 0, 'x'\n"),
    ("tk_confirm", "the confirm box has its own wrapping loop again", "call $tk_wrap(sentence, wrapw, pieces)", "rest[cut"),
    ("tk_confirm", "a command is run from the box", "   res = 'run'\n   msg = ''", "   execute sentence\n   res = 'run'\n   msg = ''"),
    ("tk_explain", "the typed name is asked for turning a gate off", "if on and gi<TK.G.BEYOND> = 1 then typed = 1", "if gi<TK.G.BEYOND> = 1 then typed = 1"),
    ("tk_explain", "the beyond-SD warning is left out", "if gi<TK.G.BEYOND> = 1 then lines<-1> = sysmsg(12824)", "null"),
    ("tk_explain", "the core-direction line is left out", "if on and gi<TK.G.DEFAULT> = 'off' then lines<-1> = sysmsg(12822)", "null"),
    ("tk_explain", "a planned gate is explained", "if gi<TK.G.STATUS> # 'built' then return", "null"),
    ("sl_pickwin", "a phantom is asked to pick", "if system(25) then return", "if 0 then return"),
    ("sl_pickwin", "the screen under the window is not put back", "call $sl_region('restore', scr, bx, by, bw, bh, under)", "null"),
    ("sl_pickwin", "Esc does not cancel", "         case k = 'esc'\n            st = 'cancel'", "         case k = 'esc'\n            st = ''"),
    ("sl_pickwin", "Enter answers the place", "         ret = oi\n         if fmode then ret = items<oi, 1>", "         ret = cur\n         if fmode then ret = items<oi, 1>"),
    ("sl_pickwin", "a pick is kept by place", "         picked<1, -1> = pk\n      end\n   end\n   return", "         picked<1, -1> = cur\n      end\n   end\n   return"),
    ("sl_pickwin", "the filter ignores the description", "upcase(items<i, 1> : ' ' : items<i, 2>)", "upcase(items<i, 1>)"),
    ("sl_pickwin", "the filter is case sensitive", "      uf = upcase(filt)\n      for i = 1 to n", "      uf = filt\n      for i = 1 to n"),
    ("sl_pickwin", "the paged filter is case sensitive", "   uf = upcase(filt)\n   loop while got < page", "   uf = filt\n   loop while got < page"),
    ("sl_pickwin", "a read ignores the scan number", "loop while got < page and scanned < scancap and n < cachecap do", "loop while got < page and n < cachecap do"),
    ("sl_pickwin", "a read ignores the page", "loop while got < page and scanned < scancap and n < cachecap do", "loop while scanned < scancap and n < cachecap do"),
    ("sl_pickwin", "a read ignores the cache size", "loop while got < page and scanned < scancap and n < cachecap do", "loop while got < page and scanned < scancap do"),
    ("sl_pickwin", "the paged filter is not applied while reading", "      if filt # '' then keepit = index(upcase(id : ' ' : desc), uf, 1)", "      if 0 then keepit = index(upcase(id : ' ' : desc), uf, 1)"),
    ("sl_pickwin", "the paged answer is a number", "         if fmode then ret = items<oi, 1>", "         if 0 then ret = items<oi, 1>"),
    ("sl_pickwin", "a paged pick is kept by number", "      pk = oi\n      if fmode then pk = items<oi, 1>\n      locate", "      pk = oi\n      if 0 then pk = items<oi, 1>\n      locate"),
    ("sl_pickwin", "End does not read on", "               loop while not(exhausted) and n < cachecap do\n                  gosub fetch\n               repeat", "               gosub fetch"),
    ("sl_pickwin", "the select list is left on the way out", "   call $sl_scr('put', scr)\n   if fmode then clearselect 10\n   if st = 'done' then status = 0", "   call $sl_scr('put', scr)\n   if st = 'done' then status = 0"),
    ("sl_pickwin", "a new filter does not start the read again", "   if fmode then\n      gosub file.refilter\n      return\n   end", "   if 0 then\n      gosub file.refilter\n      return\n   end"),
    ("sl_pickwin", "the cache has no bound at the start of a read", "   if exhausted or n >= cachecap then return", "   if exhausted then return"),
    ("sl_pickwin", "? is added to the filter", "         case k = '?'\n            helpon = 1 - helpon\n", ""),
    ("sl_pickwin", "the space picks only after a character is added to the filter", "         case k = ' ' and multi\n            gosub toggle\n", ""),
    ("sl_pickwin", "the window writes a record", "   if fmode then clearselect 10\n   if st = 'done' then status = 0", "   write items to scr, 'x'\n   if fmode then clearselect 10\n   if st = 'done' then status = 0"),
    ("sl_slider", "the space bar does nothing", "            case key = ' '\n               ret = 'handled'", "            case key = 'zz'\n               ret = 'handled'"),
    ("sl_slider", "Left slides it on", "               w{'value'} = 0\n               gosub paint", "               w{'value'} = 1\n               gosub paint"),
    ("sl_slider", "Right slides it off", "               w{'value'} = 1\n               gosub paint", "               w{'value'} = 0\n               gosub paint"),
    ("sl_slider", "a start value of 5 stays 5", "if w{'value'} + 0 # 0 then v = 1", "if 0 then v = 1"),
    ("sl_slider", "off and on look the same", "      sw = '[' : downcase(w{'offw'}) : ' | ' : upcase(w{'onw'}) : ']'", "      sw = '[' : upcase(w{'offw'}) : ' | ' : downcase(w{'onw'}) : ']'"),
    ("sl_slider", "the slider ignores the place", "call $sl_caption(w{'place'}, len(sw), w{'label'}, geom)", "call $sl_caption('', len(sw), w{'label'}, geom)"),
    ("sl_slider", "a click on the label is taken for the control", "case rrow = 0 and rel >= 0 and rel <= lo + 2", "case rel <= lo + 2"),
    ("sl_caption", "left is the default no more", "         case 1\n            gw = lw + 1 + cw\n            cx = lw + 1", "         case 1\n            gw = cw + 1 + lw\n            lx = cw + 1"),
    ("sl_caption", "right puts the label first", "            lx = cw + 1", "            lx = 0"),
    ("sl_caption", "above puts the control first", "            gh = 2\n            cy = 1", "            gh = 2\n            cy = 0"),
    ("sl_caption", "below puts the label first", "            gh = 2\n            ly = 1", "            gh = 2\n            ly = 0"),
    ("sl_caption", "the width ignores a longer label", "            gw = cw\n            if lw > gw then gw = lw\n            gh = 2\n            cy = 1", "            gw = cw\n            gh = 2\n            cy = 1"),
    ("sl_color", "a null pair of colours is asked for", "if trim(fg) = '' and trim(bg) = '' then return", "if 0 then return"),
    ("sl_color", "a full pool does not refuse the control", "      case c1 = 'full' or c1 = 'bad'\n         st = 1", "      case c1 = 'zz'\n         st = 1"),
    ("sl_color", "an entry loses its colours when it has the focus", "if c2 # 'none' then w{'cfocus'} = c2", "null"),
    ("sl_color", "every control gets a focus variant", "if t = 'entry' or t = 'combo' then", "if 1 then"),
    ("sl_theme", "a theme change forgets the user styles", "if keepu<s> # '' then th.defs<s> = keepu<s>", "null"),
    ("sl_theme", "SCREEN CLOSE leaves the user styles", "th.defs<s> = ''", "null"),
    ("sl_theme", "the same pair takes two slots", "if th.defs<s, 4> = skey and have = 0 then have = s", "if 0 then have = s"),
    ("sl_check", "the check box ignores the place", "call $sl_caption(w{'place'}, 3, w{'label'}, geom)", "call $sl_caption('', 3, w{'label'}, geom)"),
    ("sl_check", "the box is drawn where the label is", "if r = cy then rowtext[cx + 1, 3] = mark", "if r = cy then rowtext[lx + 1, 3] = mark"),
    ("sl_slider", "the words of the program are not used", "         if w{'offw'} = '' then w{'offw'} = 'off'", "         w{'offw'} = 'off'"),
    ("sl_slider", "the word in force is styled one cell early", "      a0 = lo + 4\n      al = ln", "      a0 = lo + 3\n      al = ln"),
    ("sl_slider", "the word in force is not in the style", "call $sl_attr(w{'attr'}, ac)", "call $sl_attr('window', ac)"),
    ("sl_slider", "no style is the default", "if w{'attr'} = '' then w{'attr'} = 'bold'", "if w{'attr'} = '' then w{'attr'} = 'window'"),
    ("sl_slider", "a click on the word on sets it off", "               case rrow = 0 and rel >= 0 and rel <= lo + ln + 4\n                  w{'value'} = 1", "               case rrow = 0 and rel >= 0 and rel <= lo + ln + 4\n                  w{'value'} = 0"),
    ("sl_slider", "a click on the text does nothing", "               case 1\n                  v = 1\n                  if w{'value'} then v = 0\n                  w{'value'} = v\n            end case", "               case 1\n                  null\n            end case"),
    ("sl_slider", "the cursor is not put on the word in force", "call $sl_curat(w{'ax'} + cx + a0, w{'ay'} + cy)", "null"),
    ("sl_slider", "an arrow other than Left and Right is taken", "            case 1\n               ret = 'unhandled' : @fm : key", "            case key = 'up'\n               ret = 'handled'\n            case 1\n               ret = 'unhandled' : @fm : key"),
    ("tk_gate_info", "the table is written to the screen","   if id = 'list' then", "   crt 'x'\n   if id = 'list' then"),
    # TK-0.11, the selector (the sitting's own mutants)
    ("sl_selector", "Right goes past the last word", "               if v < n then w{'value'} = v + 1", "               w{'value'} = v + 1"),
    ("sl_selector", "Left goes past the first word", "               if v > 1 then w{'value'} = v - 1", "               w{'value'} = v - 1"),
    ("sl_selector", "Home goes to the last word", "            case key = 'home'\n               ret = 'handled'\n               w{'value'} = 1", "            case key = 'home'\n               ret = 'handled'\n               w{'value'} = n"),
    ("sl_selector", "End goes to the first word", "            case key = 'end'\n               ret = 'handled'\n               w{'value'} = n", "            case key = 'end'\n               ret = 'handled'\n               w{'value'} = 1"),
    ("sl_selector", "the space bar does not wrap", "   v = w{'value'} + 0 + 1\n   if v > n then v = 1", "   v = w{'value'} + 0 + 1\n   if v > n then v = n"),
    ("sl_selector", "the word in force is in lower case", "         wd = upcase(wd)\n         a0 = len(sw)", "         wd = downcase(wd)\n         a0 = len(sw)"),
    ("sl_selector", "the other words are in capitals", "         wd = downcase(wd)\n      end", "         wd = upcase(wd)\n      end"),
    ("sl_selector", "the word in force is styled one cell early", "         a0 = len(sw)\n         al = len(wd)", "         a0 = len(sw) - 1\n         al = len(wd)"),
    ("sl_selector", "the space after a word belongs to the next word", "if rel <= lastc<j> + 1 then chosen = j", "if rel <= lastc<j> then chosen = j"),
    ("sl_selector", "a click on the closing bracket chooses the first word", "               chosen = n\n", "               chosen = 1\n"),
    ("sl_selector", "a click on the label does nothing", "            end else\n               gosub nextword\n            end\n            gosub paint", "            end else\n               null\n            end\n            gosub paint"),
    ("sl_selector", "a start value above the last word stays", "         if v < 1 or v > n then v = 1", "         if v < 1 then v = 1"),
    ("sl_selector", "an arrow other than Left and Right is taken", "            case 1\n               ret = 'unhandled' : @fm : key", "            case key = 'up'\n               ret = 'handled'\n            case 1\n               ret = 'unhandled' : @fm : key"),
    ("sl_selector", "the cursor is not put on the word in force", "call $sl_curat(w{'ax'} + cx + a0, w{'ay'} + cy)", "null"),
    ("sl_selector", "the colour is not used", "   if w{'ccode'} # '' then code = w{'ccode'}\n", "\n"),
    ("sl_selector", "the focus is not shown", "   if w{'focused'} then call $sl_attr('highlight', code)\n", "\n"),
    ("sl_selector", "no style is the default", "if w{'attr'} = '' then w{'attr'} = 'bold'", "if w{'attr'} = '' then w{'attr'} = 'window'"),
    # TK-0.12, the accelerators (the sitting's own mutants)
    ("sl_accel", "ctrl-i is taken", " and index('hijm', a[6, 1], 1) = 0", ""),
    ("sl_accel", "f13 is taken", "tail + 0 <= 12", "tail + 0 <= 13"),
    ("sl_accel", "a + is not a -", "a = convert('+', '-', downcase(trim(accel)))", "a = downcase(trim(accel))"),
    ("sl_accel", "no key is refused", "   if trim(accel) = '' then return\n", "\n"),
    ("sl_accel", "a letter of any case is taken as typed", "a = convert('+', '-', downcase(trim(accel)))", "a = convert('+', '-', trim(accel))"),
    ("sl_form", "a disabled control takes the key", "w{'disabled'} + 0 = 0 and ancdis = 0 and (w{'focusable'}", "ancdis = 0 and (w{'focusable'}"),
    ("sl_form", "the last control with a key wins", "         if ni > 0 then exit\n", "         null\n"),
    ("sl_form", "a button is not pressed by its key", "      case wt = 'button'\n         gosub press.button\n      case wt = 'check'", "      case wt = 'button'\n         null\n      case wt = 'check'"),
    ("sl_form", "a turned-over control makes no change event", "if w{'value'} # v1 then f{'achg'} = hit", "null"),
    ("sl_form", "the Alt-letter is matched as typed", "w{'amn'} = upcase(key[5, 1])", "w{'amn'} = key[5, 1]"),
    ("sl_form", "a label with no control to go to still moves", "if ni = 0 then ni = -1", "null"),
    ("sl_key", "the Alt-letter is not asked for", "alt.was = bindkey('', -7)", "alt.was = 0"),
    ("sl_key", "BINDKEY's clearing of STATUS() is not undone", "      set.status kst\n", "\n"),
    ("sl_key", "the Alt-letter stays asked for","if alt.was then x = bindkey('', -7) else x = bindkey('', -8)", "x = bindkey('', -7)"),
    ("sl_key", "the Alt-letter keeps the case typed", "name = 'alt-' : downcase(k[2,1])", "name = 'alt-' : k[2,1]"),
    ("_keycode", "an Alt-letter is returned whether asked for or not", "if kc.alt and len(key.string) = 2", "if len(key.string) = 2"),
    ("_bindkey", "-8 leaves the Alt-letter on", "kc.alt = @false", "kc.alt = @true"),
    ("sl_button", "a button's first letter is also an Alt-letter", "            w{'mn'} = upcase(t[1, 1])\n", "            w{'mn'} = upcase(t[1, 1])\n            w{'amn'} = w{'mn'}\n"),
    # TK-1, tool.keys (the sitting's own mutants)
    ("tool_keys", "the app asks for the administrator", "call $tk_open('tool.keys', '', ctx, err)", "call $tk_open('tool.keys', 'admin', ctx, err)"),
    ("tool_keys", "a key is not shown before it is acted on", "            gosub record\n            call $tk_keys('action', keys, nm, pane, act, '', '')", "            call $tk_keys('action', keys, nm, pane, act, '', '')"),
    ("tool_keys", "the end of the input is not seen in names mode", "      if status() = ER$EOF then ended = 1\n", "      if 0 then ended = 1\n"),
    ("tool_keys", "the end of the input is not seen in raw mode", "      if status() = ER$EOF then\n         ended = 1\n         exit\n      end", "      if 0 then\n         ended = 1\n         exit\n      end"),
    ("tool_keys", "the cursor is not parked", "      call $sl_curat(0, ctx<TK.C.YSTAT>)", "      null"),
    ("tool_keys", "a resize does not have the frame written again", "   ctx<TK.C.GEN> = gen\n", "   null\n"),
    ("tool_keys", "raw mode takes one byte of a burst", "      c = keyin(0.05)\n", "      c = ''\n"),
    ("tool_keys", "ctrl-i has a cell of its own", "if i # 8 and i # 9 and i # 10 and i # 13 then", "if i # 8 and i # 10 and i # 13 then"),
    ("tool_keys", "an Alt-letter has no cell", "if nm[1, 4] = 'alt-' then cell = 'alt-x'", "if 0 then cell = 'alt-x'"),
    ("tool_keys", "Ctrl-Q does not leave", "   call $tk_keys('add', keys, 'ctrl-q', 'quit', 'quit', '', 1)\n", "\n"),
    ("tool_keys", "a wheel down is counted as up", "case mev<1> = 'wheel' ; mdn += 1", "case mev<1> = 'wheel' ; mu += 1"),
    ("tool_keys", "Last keys is not cut to its 25 lines", "if dcount(logl, @fm) > LOGN then del logl<LOGN + 1>", "null"),
    ("tool_keys", "the window is not watched in raw mode", "      if @crtwide : ',' : @crthigh # lastsz then", "      if 0 then"),
    ("tool_keys", "a colour terminal is told it has none", "colour = (if cs = 'none' then 'no' else 'yes')", "colour = 'no'"),
    ("screen_label", "a label's letter is not kept","w{'amn'} = upcase(t[p + 1, 1])", "null"),
    ("sl_check", "a check box's letter is not kept", "w{'amn'} = upcase(t[p + 1, 1])", "null"),
    # TK-0.12, the marked letter drawn (the sitting's own mutants)
    ("sl_check", "the check box's letter is one cell off", "w{'apos'} = p  ", "w{'apos'} = p + 1  "),
    ("sl_check", "the check box's letter is counted from the box, not the label", "if hk then cells[lx + w{'apos'}, 1] = hcode", "if hk then cells[cx + w{'apos'}, 1] = hcode"),
    ("sl_check", "a disabled check box still shows its letter", "and w{'disabled'} + 0 = 0 and w{'apos'}", "and w{'apos'}"),
    ("sl_check", "the check box's letter is in another style", "call $sl_attr('hotkey', hcode)", "call $sl_attr('bar', hcode)"),
    ("sl_slider", "the slider's letter is not drawn", "if hk then cells[lx + w{'apos'}, 1] = hcode", "if 0 then cells[lx + w{'apos'}, 1] = hcode"),
    ("sl_slider", "the slider's letter is not looked for before the rows", "   ly = geom<1, SL.CAP.LY>\n   gosub hotkey\n", "   ly = geom<1, SL.CAP.LY>\n"),
    ("sl_selector", "the selector's letter is drawn while it has the focus", "if not(w{'focused'}) and w{'disabled'} + 0 = 0 and w{'apos'}", "if w{'disabled'} + 0 = 0 and w{'apos'}"),
    ("sl_selector", "the selector's letter is never kept", "w{'apos'} = p  ", "null  "),
    ("sl_button", "the button's bracket and space are not counted", "cells[w{'apos'} + 2, 1] = hcode", "cells[w{'apos'}, 1] = hcode"),
    ("sl_button", "a button's plain mnemonic is drawn marked", "            w{'mn'} = upcase(t[1, 1])\n", "            w{'mn'} = upcase(t[1, 1])\n            w{'apos'} = 1\n"),
    ("sl_button", "the button's letter is drawn while it has the focus", "if not(w{'focused'}) and w{'disabled'} + 0 = 0 and w{'apos'}", "if w{'disabled'} + 0 = 0 and w{'apos'}"),
    ("screen_label", "the label's place is not kept", "w{'apos'} = p  ", "null  "),
    ("sl_label", "the label's letter is in another style", "call $sl_attr('hotkey', hcode)", "call $sl_attr('bar', hcode)"),
    ("sl_label", "the label's letter may lie beyond its text", " and w{'apos'} + 0 <= len(w{'text'})", ""),
    ("screen_set", "SCREEN SET ... TEXT keeps the label's old place", "if wt = 'label' then w{'apos'} = 0", "if 0 then w{'apos'} = 0"),
]


def selftest():
    try:
        raw = load()
    except FileNotFoundError as e:
        print("CANNOT RUN: %s is not there" % e)
        return 2
    rows, bad = run(raw)
    if bad:
        print("selftest: the real files already fail %d check(s)" % len(bad))
        return 1
    killed, missed, skipped = 0, [], 0
    for fname, what, old, new in MUT:
        if fname not in raw:
            skipped += 1                  # a mutant of a program this tree has not (Solo has no gate pages)
            continue
        if raw[fname].count(old) != 1:
            print("  [CANNOT] %s: the text to change is found %d times in %s, not once" % (what, raw[fname].count(old), fname))
            return 2
        m = dict(raw)
        m[fname] = raw[fname].replace(old, new)
        rows_m, bad_m = run(m, quiet=True)
        if bad_m:
            killed += 1
            print("  [killed] %s  <- %s" % (what, ", ".join(r[0] for r in bad_m)))
        else:
            missed.append(what)
            print("  [MISSED] %s" % what)
    print("selftest: %d mutants, %d killed, %d missed%s" % (len(MUT) - skipped, killed, len(missed), (", %d skipped (their program is not in this tree)" % skipped) if skipped else ""))
    return 0 if not missed else 1


def main():
    if "--selftest" in sys.argv:
        return selftest()
    try:
        raw = load()
    except FileNotFoundError as e:
        print("CANNOT RUN: %s is not there" % e)
        return 2
    rows, bad = run(raw)
    print("test-tkbase-units: %d passed, %d failed" % (len(rows) - len(bad), len(bad)))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
