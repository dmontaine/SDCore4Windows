#!/usr/bin/env python3
"""test-dictform-units.py - S.90 stage 2: the dictionary item form (gpl.bp/dict_form) and the IDE's hook for it (do.dform, /form, the Go menu entry), read off the source as text.

  python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/test-dictform-units.py
  python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/test-dictform-units.py --selftest

No sudo, no install, no sd.  Exit 0 every check passed, 1 a check failed, 2 it could not run.

START-HISTORY:
31 Oct 26 dm  New with the form (plan .claude/plan-s90-dict-form.md).
31 Oct 26 dm  The form is the DEFAULT face of a dictionary item (the owner's word): I5 reads /text too, I8-I10 hold dform.default (the start, the tree, silent for a tab it cannot or must not
              show) and 8 mutants of the sitting.
1 Nov 26 dm   F8 pins the order tl.ty = cv, gosub collect, vals{'type'} = tl.ty (the old pin held the order that lost the Type) and a mutant that restores the defect.
3 Nov 26 dm   S.97, THE FORM'S AI LINE: F1 reads the fifth argument (org); AI1-AI7 and their mutants (--selftest --from=N runs from mutant N; M_S97 marks this sitting's first): the
              line only when the AI is usable, Return in it asks rather than accepts, the request says where the item is (fail shut when the caller did not), no command, the
              fields offered, and every accepted value goes through !dict_item before it is in a row; the form still writes nothing.  The IDE passes ai.origin to the form.
END-HISTORY

WHAT IT HOLDS.  $dict_form is the screen over !dict_item: it opens nothing, writes nothing and makes no record of its own (every record comes from the engine's 'build'); it
checks a row as the focus leaves it and every row again before it ends with a record; it ends with save, text, cancel or cannot and nothing else; an item the engine cannot parse
is `cannot` BEFORE any form is made; a change of type collects what was typed before the form is made again; Esc asks only when something changed.  The IDE's do.dform refuses a
tab that is not a dictionary item and a read-only tab, keeps the editor's text first (stash.current), calls the form once, redraws, puts the record in the tab as the token form
and writes it with the IDE's own save only for `save`; `/form` is taken off the sentence before any id is read from it; the Go menu has the entry, with no key.

***IT READS THE SOURCE AS TEXT.***  That the form shows what the engine says and the IDE saves what the form built is sandbox-dictform.py (the IDE on a pseudo-terminal).
--selftest requires each mutation to match its text exactly once and to be caught.
"""

import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SDSYS = os.path.join(HERE, os.pardir, "sdsys")
GPL = os.path.join(SDSYS, "gpl.bp")
FILES = {"form": os.path.join(GPL, "dict_form"), "ide": os.path.join(GPL, "ide"), "go": os.path.join(SDSYS, "messages", "12231"),
         "m1": os.path.join(SDSYS, "messages", "12954"), "m2": os.path.join(SDSYS, "messages", "12955")}


def strip(src):
    """the code without comment lines and trailing ;* comments"""
    out = []
    for ln in src.split("\n"):
        if ln.lstrip().startswith("*"):
            continue
        out.append(re.sub(r"\s*;\*.*$", "", ln))
    return "\n".join(out)


def ordered(text, *parts):
    pos = -1
    for p in parts:
        i = text.find(p, pos + 1)
        if i < 0:
            return False
        pos = i
    return True


def between(text, start, end):
    a = text.find(start)
    if a < 0:
        return ""
    b = text.find(end, a + len(start))
    return text[a:] if b < 0 else text[a:b]


def checks(src, others):
    rows = []

    def ck(name, ok, detail=""):
        rows.append((name, bool(ok), detail))

    form, ide = strip(src["form"]), strip(src["ide"])
    ck("F0 NULL CASE: the reader sees the form (over 5 KB of code) and the IDE (over 100 KB)", len(form) > 5000 and len(ide) > 100000, repr((len(form), len(ide))))
    ck("F1 the form is $internal, `subroutine dict_form(rec, title, newrec, res, org)`, catalogued as $dict_form, and no other program takes the name",
       form.lstrip().startswith("$internal") and re.search(r"^subroutine dict_form\(rec, title, newrec, res, org\)$", form, re.M) is not None and "$catalog $dict_form" in form
       and not any(re.search(r"^\$catalog\s+\$dict_form\b", strip(t), re.M | re.I) for t in others.values()), "")
    bad = re.findall(r"\b(openseq|openpath|open|write|writev|writeu|delete|execute|perform|chain|kernel|oscopy|osopen)\b", form, re.I)
    ck("F2 it opens nothing, writes nothing and runs nothing", not bad, repr(bad[:5]))
    ck("F3 every record comes from the engine: the form calls !dict_item for parse, layout, check, build and the Len & Just text (fmtshow, fmtsplit), and never assigns a field of a record",
       all(("call !dict_item('%s'" % o) in form for o in ("parse", "layout", "check", "build", "fmtshow", "fmtsplit")) and re.search(r"\b(newrec|nr|rec)<", form) is None, "")
    ck("F4 an item the engine will not parse ends as `cannot` with the reason in words, BEFORE any form is made",
       ordered(form, "if pd # '' then", "res = 'cannot'", "newrec = ", "return", "loop\n      gosub make.form") and form.count("res = 'cannot'") == 1, "")
    ck("F5 the form ends with save, cancel or cannot and nothing else",
       sorted(set(re.findall(r"res = '(\w+)'", form))) == ["cancel", "cannot", "save"] and "bt = ev<2>" in form and "if bt = 'accept' then" in form, "")
    ck("F6 Accept ends the form only when `build` accepted every row, after a Type typed and not yet left has been taken and a bad Len & Just has been refused; otherwise the row is named in the err line and takes the focus",
       ordered(form, "on.button:", "if bt = 'accept' then", "gosub type.left", "if act # '' then return", "gosub collect", "if fmt.err # '' then", "screen focus f, 'fmt' else null",
               "call !dict_item('build', vals, rec, nr, be)", "if be = '' then", "newrec = nr", "res = 'save'", "act = 'done'", "else", "screen set f, 'err' text '! ' : be<2>", "screen focus f, fk else null"), "")
    ck("F7 a row is checked as the focus leaves it (check, then the err line; a good value is put back in its normal form); the Type goes to type.left and every other row to row.left",
       ordered(form, "on.focus:", "lfk = ev<3>", "if lfk = 'type' then", "gosub type.left", "gosub row.left")
       and ordered(form, "row.left:", "call !dict_item('check', ty, lfk, cv, ce)", "screen set f, lfk value cv", "screen set f, 'err' text '! '"), "")
    ck("F8 THE TYPE IS AN ENTRY THAT IS TYPED (the owner's layout): checked as the focus leaves it, and a good type that is another one collects what was typed BEFORE it makes the form again with that type's rows and the focus on the first",
       "screen entry f, 'type' at 26,y width 6 value vals{'type'} maxlen 2" in form and "screen radio" not in form
       and ordered(form, "type.left:", "call !dict_item('check', 'D', 'type', cv, ce)", "if cv # ty then", "tl.ty = cv", "gosub collect", "vals{'type'} = tl.ty", "focus.first = 1", "act = 'type'"), "")
    ck("F9 Esc or Cancel asks only when something was changed (the built record is not the old one, or the rows fail) and never before a Type was entered, and Keep editing leaves the form on the screen",
       ordered(form, "ask.discard:", "if ty = '' then", "res = 'cancel'", "gosub collect", "call !dict_item('build', vals, rec, nr, be)", "if be = '' and nr = rec then", "res = 'cancel'", "screen msgbox", "if bq = 1 then", "res = 'cancel'"), "")
    ck("F10 the form is 140 by 43, a text row is a memo, every other row an entry with its own width and longest text, and there are TWO buttons: Accept (the default) and Cancel (the cancel button)",
       "at 0,1 size fm.w,fh returning f" in form and "screen memo f, key" in form and "screen entry f, key at 26,y width ew value vals{key} maxlen em" in form
       and "screen button f, 'accept', '&Accept' at 26,y.btn default" in form and "screen button f, 'cancel', '&Cancel' at 40,y.btn cancel" in form and form.count("screen button f,") == 2, "")
    ck("F14 THE FORM IS IN THE COMMON FRAME (1 Nov 26: the first build covered the whole screen, the IDE's bar and foot included): it is laid out for the window, never under 140 by 43, from row 1 to the row above the status line (fh = ystat - 1, ystat = height - 3); its buttons and its hint and error rows are counted from fh; "
       "after the widgets it draws the bar on row 0, the status line in reverse on ystat, the border and the function-key row made by $tk_fkeys from a table that holds Enter accept and Esc cancel",
       ordered(form, "call $sl_window(win.w, win.h)", "if fm.w < 140 then fm.w = 140", "if fm.h < 43 then fm.h = 43", "ystat = fm.h - 3", "fh = ystat - 1", "y.hint = fh - 9", "y.err = fh - 7", "y.btn = fh - 4",
               "screen form title", "at 0,1 size fm.w,fh returning f", "screen button f, 'cancel'", "gosub draw.foot", "return")
       and ordered(form, "draw.foot:", "screen text bar.t at 0,0 attr 'bar'", "screen text fmt(st.t[1, fm.w], fm.w : 'L') at 0,ystat attr 'reverse'", "screen text str(fk.hc, fm.w) at 0,ystat + 1",
                   "call $tk_fkeys(fk.ctx, fm.keys, '', fk.text)", "screen text fk.text at 0,ystat + 2 attr 'bar'")
       and "call $tk_keys('add', fm.keys, 'enter', 'accept', 'accept', '', 1)" in form and "call $tk_keys('add', fm.keys, 'esc', 'cancel', 'cancel', '', 1)" in form, "")

    keys = set(re.findall(r"rw<-1> = '(\w+)'", others.get("dict_item", "")))
    ids = set(re.findall(r"screen (?:button|label) f, '([\w.]+)'", form))
    ck("F11 no button or label has the id of a layout row (the Text row of a PH or X item is a memo with the id `text`; in the first build a second widget of that id took a button's place)",
       len(keys) >= 10 and "text" in keys and {"accept", "cancel"} <= ids and not (ids & keys), repr((len(keys), sorted(ids & keys))))
    ck("F12 THE FORMAT IS ONE ROW, Len & Just: the engine's width, justification and decimals rows are folded into it, shown by fmtshow, split by fmtsplit when the rows are collected, and a bad one is refused with its own message",
       ordered(form, "fold.format:", "case k = 'width'", "'fmt' : @vm : 'Len & Just'", "case k = 'just' or k = 'dec'") and "case key = 'fmt'" in form and ordered(form, "collect:", "if key = 'fmt' then", "call !dict_item('fmtsplit', cv, fw, '', fe)", "fmt.err = fe")
       and "'! Len & Just: ' : fmt.err" in form, "")
    ck("F13 a new item shows only the Type row until a type is entered, and no row is numbered",
       ordered(form, "make.form:", "if ty = '' then", "rows = 'type' : @vm : 'Type'", "end else", "call !dict_item('layout', ty, rows, '', xd)", "gosub fold.format") and "rp : '. '" not in form
       and ordered(form, "screen label f, 'l.' : key, ' ' at 2,y width 22", "screen set f, 'l.' : key text rows<rp, 2> : ':'"), "")
    d = between(ide, "\ndo.dform:", "\nfields.enter:")
    ck("I1 do.dform refuses an empty editor, a tab that is not a dictionary item (12954) and a read-only tab, and keeps the editor's text first",
       ordered(d, "if nbuf = 0 then", "if bx{k} # 'dict' then", "msg = sysmsg(12954)", "gosub ro.check", "if not(ro.ok) then", "gosub stash.current", "df.rec = bx{k}"), "")
    ck("I2 it calls the form once, redraws, says why an item stays text (12955), and for save or text puts the record in the tab as the token form",
       d.count("call $dict_form(") == 1 and ordered(d, "call $dict_form(df.rec", "gosub redraw", "gosub draw.bar", "df.res = 'cannot'", "sysmsg(12955, ", "df.res = 'save' or df.res = 'text'",
                                                    "bx{k} = df.new", "gosub set.token.mode", "gosub load.current"), "")
    ck("I3 only `save` is written, by the IDE's own save, AFTER the text is in the tab; `text` and `cancel` write nothing",
       ordered(d, "gosub load.current", "if df.res = 'save' then", "gosub save.one") and d.count("gosub save.one") == 1 and d.count("save.current") == 0, "")
    ck("I4 the command dform is a case of run.cmd and the Go menu has the entry, which has no key, before Next record from the list", "case cmd = 'dform'" in ide and "gosub do.dform" in ide
       and "|Dictionary item as for&m~~dform|Next &record from the list~~nextsel" in src["go"], repr(src["go"][-60:]))
    ck("I5 the start words /form and /text are taken off the sentence before any id is read, and the sentence is read once",
       ordered(ide, "sent.in = @sentence", "text0 = @false", "'/FORM'", "'/TEXT'", "form0 = @true", "text0 = @true", "sent.in = trimb(sent.in[1, len(trimb(sent.in)) - 5])", "fn0 = field(sent.in, ' ', 2)")
       and ide.count("@sentence") == 1, repr(ide.count("@sentence")))
    ck("I6 IDE DICT file item /form opens the form after the record is open and before the main loop",
       ordered(ide, "gosub rc.untitled", "if form0 and nbuf > 0 then", "gosub redraw", "gosub do.dform", "menu.click = ''"), "")
    ck("I8 THE DEFAULT (31 Oct 26): a dictionary item named on the command line - DICT, one id, no /text - goes to dform.default when /form was not given, before the main loop",
       ordered(ide, "if form0 and nbuf > 0 then", "gosub do.dform", "end else", "if dflag0 = 'DICT' and id0 # '' and not(text0) then gosub dform.default", "menu.click = ''"), "")
    dd = between(ide, "\ndform.default:", "\ndo.dform:")
    ck("I9 dform.default does nothing and says nothing for an empty editor, a tab that is not a dictionary item or a read-only tab, and otherwise redraws and calls do.dform",
       ordered(dd, "if nbuf = 0 then return", "if bx{k} # 'dict' then return", "gosub ro.check", "if not(ro.ok) then return", "gosub redraw", "gosub do.dform", "return")
       and "sysmsg(" not in dd and "save.one" not in dd and "ro.box" not in dd, repr(dd[:300]))
    ck("I10 the form is the default for the tree's item (a tab that was not open: the tab counter moved) and for the start; NOT for a search list's row, a select list, Ctrl-O or an include",
       ordered(ide, "dq.u0 = uid", "gosub open.record", "if code[1, 2] = 'Q:' and uid > dq.u0 then gosub dform.default") and ide.count("gosub dform.default") == 2
       and ide.count("dform.default") == 3, repr((ide.count("gosub dform.default"), ide.count("dform.default"))))
    ck("I7 message 12954 says the tab is not a dictionary item; 12955 takes the item and the reason",
       "dictionary item" in src["m1"] and "%1" in src["m2"] and "%2" in src["m2"], "")

    # 3 Nov 26 (S.97): the form's AI line
    ask = between(form, "\nask.ai:", "\napply.fields:")
    app = between(form, "\napply.fields:", "\nend")
    ck("AI1 the AI line is there only when the AI is usable for the account ($tk_ai 'usable'): the entry, its label and its F6 key are each made under ai.on",
       "call $tk_ai('usable', '', ai.on, ai.pm)" in form and "if ai.on then\n      screen label f, 'ailab'" in form and ordered(form, "screen label f, 'ailab'", "screen entry f, 'ai' at 26,y.ai", "end")
       and "if ai.on then call $tk_keys('add', fm.keys, 'f6', 'box', 'nextpane', '', 1)" in form and "case ev<1> = 'key' and (ev<3> = 'f6' or ev<3> = 'shift-f6') and ai.on" in form, "")
    # 8 Nov 26 (S.176): F6 / Shift-F6 are the box keys of every page: from the rows to the line and back to the row that had the focus (on.focus keeps it)
    ck("AI1b F6 and Shift-F6 go from the rows to the AI line and from the line back to the row that had the focus last (kept by on.focus, never the line itself)",
       ordered(form, "if hn = 'ai' then", "screen focus f, fm.lastrow else null", "hn = fm.lastrow", "end else", "screen focus f, 'ai' else null", "hn = 'ai'")
       and "if hn # 'ai' then fm.lastrow = hn" in form and "fm.lastrow = ''" in form, "")
    ck("AI2 Return in the AI line (the default button pressed while the line has the focus) asks the AI and does NOT accept the form: on.button looks at the focused widget first and returns",
       ordered(form, "on.button:", "if bt = 'accept' and ai.on then", "fq.i = f{'focus'} + 0", "if fq.w{'id'} = 'ai' then", "gosub ask.ai", "return", "if bt = 'accept' then", "gosub type.left"), "")
    ck("AI3 THE WALL: the request says where the item is (actx<13> from the caller's org), and a caller that gave none makes it 'unknown', which the wall refuses (fail shut); the IDE passes ai.origin",
       ordered(ask, "ai.org = org", "if ai.org = '' then ai.org = 'unknown'", "actx<13> = ai.org", "call $tk_ai('ask', ai.ctx, actx, ai.res)")
       and ordered(between(ide, "\ndo.dform:", "\nfields.enter:"), "gosub ai.origin", "call $dict_form(df.rec, bf.name : ' ' : bf.id, df.new, df.res, ai.org)"), "")
    ck("AI4 the form offers its fields (actx<14>, the Type first, every row key of every type and the one Len & Just key) and no command (nocmd), and asks through $tk_ai only, once",
       ordered(ask, "flds = 'type:", "'loc:", "'path:", "'expr:", "'idexpr:", "'file:", "'fexpr:", "'conv:", "'head:", "'fmt:", "'sm:", "'assoc:", "'user:", "'text:", "actx<11> = 'nocmd'", "actx<14> = flds")
       and form.count("call $tk_ai('ask'") == 1 and "'width:" not in ask and "'just:" not in ask, "")
    ck("AI5 ONLY ACCEPTED VALUES, ONLY THROUGH THE FORM'S OWN RULES: the values are taken only when $tk_ai answered 'fields' (the person's Accept); the Type is checked first, a key must be a row of "
       "the item's type, Len & Just goes through fmtsplit, a one-line row through !dict_item check, and a refused value is said and not put in vals",
       ordered(ask, "case ai.res<1> = 'fields'", "gosub apply.fields") and ordered(app, "call !dict_item('check', 'D', 'type', cv, ce)", "if ce = '' then", "ty.new = cv", "call !dict_item('layout', ty.new, lr, '', xd)")
       and ordered(app, "apply.one:", "case lp = 0", "a.bad<-1>", "case key = 'fmt'", "call !dict_item('fmtsplit', cv, fw, '', ce)", "case lr<lp, 3> = 'memo'", "case index(cv, char(10), 1)", "case 1",
                   "call !dict_item('check', ty.new, key, cv, ce)", "if ce = '' then", "vals{key} = cv", "end else", "a.bad<-1>"), "")
    ck("AI6 the AI line writes nothing and ends nothing: after an ask the form is made again (act 'ai', the loop goes on) with the focus on the line, and res is never set there",
       "until act # 'type' and act # 'ai' repeat" in form and ordered(ask, "focus.ai = 1", "act = 'ai'") and "res = " not in ask.replace("ai.res = ", "") and "res = " not in app, "")
    ck("AI7 what the AI line has to say goes on the err row of the next form made (fm.note), and the request is kept in the line unless values were accepted or a follow-up was chosen",
       ordered(form, "if fm.note # '' then", "screen set f, 'err' text fm.note") and ordered(ask, "ai.keep = ai.req", "fm.note = ai.res<5>", "ai.keep = ''", "ai.keep = ''"), "")
    return rows


def load():
    src = {}
    for k, p in FILES.items():
        with open(p, encoding="latin-1") as f:
            src[k] = f.read()
    others = {}
    for n in sorted(os.listdir(GPL)):
        p = os.path.join(GPL, n)
        if n != "dict_form" and os.path.isfile(p):
            with open(p, encoding="latin-1") as f:
                others[n] = f.read()
    return src, others


def report(rows):
    bad = 0
    for name, ok, detail in rows:
        bad += 0 if ok else 1
        print("  [%s] %s%s" % ("PASS" if ok else "FAIL", name, "" if ok else "   <- " + detail))
    return bad


# (file key, name, old, new): each must match its file's text once and be caught
MUTANTS = [
    ("form", "the form writes a record", "   res = 'cancel'\n   newrec = rec\n", "   res = 'cancel'\n   newrec = rec\n   write rec to df, 'x'\n"),
    ("form", "the form assembles a record itself", "         newrec = nr\n         res = 'save'", "         newrec<2> = nr\n         res = 'save'"),
    ("form", "an item it cannot parse is shown anyway", "         res = 'cannot'\n         begin case", "         res = 'cancel'\n         begin case"),
    ("form", "Accept does not ask the engine", "      call !dict_item('build', vals, rec, nr, be)\n      if be = '' then\n         newrec = nr", "      be = ''\n      nr = rec\n      if be = '' then\n         newrec = nr"),
    ("form", "a bad row does not take the focus", "         screen focus f, fk else null", "         null"),
    ("form", "a row is not checked as the focus leaves it", "            call !dict_item('check', ty, lfk, cv, ce)", "            ce = ''"),
    ("form", "a change of type forgets what was typed", "         gosub collect\n         vals{'type'} = tl.ty", "         vals{'type'} = tl.ty"),
    ("form", "Esc always asks", "   if be = '' and nr = rec then", "   if 0 then"),
    ("form", "the form is smaller than the layout", "at 0,1 size fm.w,fh returning f", "at 0,1 size 100,30 returning f"),
    ("form", "Cancel is not the cancel button", "'&Cancel' at 40,y.btn cancel", "'&Cancel' at 40,y.btn"),
    # 31 Oct 26 (the owner's layout): own mutants of the rebuild
    ("form", "the Type is a row of radio buttons again", "screen entry f, 'type' at 26,y width 6 value vals{'type'} maxlen 2", "screen radio f, 'type', 'D,E,I,L,PH,X' at 26,y value 1 across"),
    ("form", "Width, Justification and Decimals are three rows again", "         case k = 'width'\n", "         case k = 'zzwidth'\n"),
    ("form", "an Edit as text button is back", "   screen button f, 'cancel', '&Cancel' at 40,y.btn cancel", "   screen button f, 'astext', 'Edit as &text' at 40,y.btn\n   screen button f, 'cancel', '&Cancel' at 40,y.btn cancel"),
    ("form", "a new item shows every row before a type is entered", "   if ty = '' then\n      rows = 'type'", "   if 0 then\n      rows = 'type'"),
    ("form", "the Type typed is not checked", "call !dict_item('check', 'D', 'type', cv, ce)", "ce = ''"),
    ("form", "Len & Just is read without the engine", "call !dict_item('fmtsplit', cv, fw, '', fe)\n            if fe = '' then\n               vals{'width'}", "fe = ''\n            if fe = '' then\n               vals{'width'}"),
    ("form", "the Accept button has the id of a row", "'accept', '&Accept'", "'text', '&Accept'"),
    ("form", "the label text goes through SCREEN LABEL again and loses the & of Len & Just", "      screen set f, 'l.' : key text rows<rp, 2> : ':'", "      screen label f, 'l2.' : key, rows<rp, 2> : ':' at 2,y width 22"),
    ("form", "a bad Len & Just is not refused at Accept", "      if fmt.err # '' then\n         screen set f, 'err' text '! Len & Just: ' : fmt.err", "      if 0 then\n         screen set f, 'err' text '! Len & Just: ' : fmt.err"),
    ("ide", "do.dform takes a tab that is not a dictionary item", "   if bx{k} # 'dict' then\n      msg = sysmsg(12954)", "   if 0 then\n      msg = sysmsg(12954)"),
    ("ide", "do.dform changes a read-only tab", "   gosub ro.check                       ;* a read-only tab (another session holds the record, bytes outside ASCII) is not changed", "   ro.ok = 1"),
    ("ide", "do.dform reads the tab before the editor's text is kept", "   gosub stash.current\n   df.u = bu<cb>", "   df.u = bu<cb>"),
    ("ide", "do.dform does not redraw", "   last.status = char(1)\n   gosub redraw\n   gosub draw.bar", "   last.status = char(1)\n   gosub draw.bar"),
    ("ide", "do.dform leaves the form's bar on row 0 (the IDE's menu bar is not drawn again)", "   gosub redraw\n   gosub draw.bar", "   gosub redraw"),
    ("ide", "Edit as text writes the record too", "         if df.res = 'save' then\n            sv.i = cb", "         if df.res = 'save' or df.res = 'text' then\n            sv.i = cb"),
    ("ide", "the command is not a case of run.cmd", "      case cmd = 'dform'\n         gosub do.dform ", "      case cmd = 'dformx'\n         gosub do.dform "),
    ("ide", "/form is left on the sentence", "         sent.in = trimb(sent.in[1, len(trimb(sent.in)) - 5])", "         null"),
    ("ide", "the start form runs after the main loop begins", "   if form0 and nbuf > 0 then\n      gosub redraw ", "   if 0 then\n      gosub redraw "),
    ("go", "the menu entry has a key", "|Dictionary item as for&m~~dform", "|Dictionary item as for&m~F11~dform"),
    # 31 Oct 26 (the default): own mutants of the sitting
    ("ide", "the start no longer shows the form by default", "if dflag0 = 'DICT' and id0 # '' and not(text0) then gosub dform.default", "if 0 then gosub dform.default"),
    ("ide", "/text is ignored at the start", "and id0 # '' and not(text0) then gosub dform.default", "and id0 # '' then gosub dform.default"),
    ("ide", "/text is left on the sentence", "         if sw.last = '/FORM' then form0 = @true else text0 = @true\n         sent.in = trimb(sent.in[1, len(trimb(sent.in)) - 5])",
     "         if sw.last = '/FORM' then form0 = @true else text0 = @true"),
    # 1 Nov 26 (DF5a): the Type typed is read AFTER collect has reused cv - the defect itself
    ("form", "the new Type is taken from cv after collect has overwritten it", "         tl.ty = cv                         ;* collect reads every row into cv, so the Type typed is kept apart\n         gosub collect\n         vals{'type'} = tl.ty",
     "         gosub collect\n         vals{'type'} = cv"),
    # 1 Nov 26 (the common frame): own mutants
    ("form", "the form covers the whole screen again, the bar and the foot with it", "at 0,1 size fm.w,fh returning f", "size 140,43 returning f"),
    ("form", "the foot is not drawn", "   gosub draw.foot\n   return", "   return"),
    ("form", "the status line is not in reverse video", "at 0,ystat attr 'reverse'", "at 0,ystat"),
    ("form", "the key row is made without the table", "call $tk_fkeys(fk.ctx, fm.keys, '', fk.text)", "fk.text = ''"),
    ("form", "the window is not asked: the foot is where the IDE's is not", "   call $sl_window(win.w, win.h)\n   fm.w = win.w", "   win.w = 140 ; win.h = 43\n   fm.w = win.w"),
    ("form", "the buttons are not counted from the form's height", "y.btn = fh - 4", "y.btn = 38"),
    ("ide", "the tree opens the form for an item that was already in a tab", "if code[1, 2] = 'Q:' and uid > dq.u0 then gosub dform.default", "if code[1, 2] = 'Q:' and nbuf > 0 then gosub dform.default"),
    ("ide", "the tree opens the form for a record of the data part", "if code[1, 2] = 'Q:' and uid > dq.u0 then gosub dform.default", "if uid > dq.u0 then gosub dform.default"),
    ("ide", "dform.default takes a tab that is not a dictionary item", "   if bx{k} # 'dict' then return\n   ro.i = cb", "   ro.i = cb"),
    ("ide", "dform.default takes a read-only tab", "   gosub ro.check\n   if not(ro.ok) then return\n   gosub redraw", "   gosub redraw"),
    ("ide", "a search list's row opens the form", "      gosub open.record\n      gl.n = sln<k2> + 0", "      gosub open.record\n      gosub dform.default\n      gl.n = sln<k2> + 0"),
]
M_S97 = len(MUTANTS)            # 3 Nov 26 (S.97, the form's AI line): the first mutant of the sitting, for --selftest --from=M_S97
MUTANTS += [
    ("form", "the AI line is made without the AI", "   if ai.on then\n      * 3 Nov 26 (S.97): the AI line", "   if 1 then\n      * 3 Nov 26 (S.97): the AI line"),
    ("form", "Return in the AI line accepts the form", "         if fq.w{'id'} = 'ai' then\n            gosub ask.ai", "         if 0 then\n            gosub ask.ai"),
    ("form", "the request does not say where the item is", "   actx<13> = ai.org\n", "   actx<13> = 'none'\n"),
    ("form", "a caller with no origin is let through", "   if ai.org = '' then ai.org = 'unknown'", "   if ai.org = '' then ai.org = 'none'"),
    ("form", "the form lets a command through", "   actx<11> = 'nocmd' ", "   actx<11> = '' "),
    ("form", "a value is put in a row without the form's check", "         call !dict_item('check', ty.new, key, cv, ce)\n         if ce = '' then", "         ce = ''\n         if ce = '' then"),
    ("form", "a key that is no row of the type is filled", "      case lp = 0 or key = 'width'", "      case key = 'width'"),
    ("form", "the AI's Type is taken unchecked", "         call !dict_item('check', 'D', 'type', cv, ce)\n         if ce = '' then\n            ty.new = cv", "         ce = ''\n         if ce = '' then\n            ty.new = cv"),
    ("form", "values are taken whatever the person answered", "      case ai.res<1> = 'fields'\n", "      case ai.res<1> # ''\n"),
    ("form", "the AI line ends the form", "   focus.ai = 1\n   act = 'ai'", "   focus.ai = 1\n   act = 'done'"),
    ("ide", "the IDE does not tell the form where the item is", "df.new, df.res, ai.org)", "df.new, df.res, '')"),
]
M_S176 = len(MUTANTS)           # 8 Nov 26 (S.176, F6 / Shift-F6 the box keys of every page): --selftest --from=M_S176
MUTANTS += [
    ("form", "F6 in the AI line does not come back to the rows", "               if hn = 'ai' then\n", "               if 0 then\n"),
    ("form", "the row F6 comes back to is the line itself", "   if hn # 'ai' then fm.lastrow = hn", "   fm.lastrow = hn"),
]


def selftest(first=0):
    src, others = load()
    if any(not ok for _, ok, _ in checks(src, others)):
        print("REFUSING - the unmutated source already fails", file=sys.stderr)
        return 2
    holes = 0
    print("--- self-test: each mutation must be CAUGHT and match its text once ---")
    for fk, name, old, new in MUTANTS[first:]:
        n = src[fk].count(old)
        if n != 1:
            print("  [FAIL] %s: the text matches %d times in %s, not once" % (name, n, fk))
            holes += 1
            continue
        mut = dict(src)
        mut[fk] = src[fk].replace(old, new)
        caught = [x.split(" ")[0] for x, ok, _ in checks(mut, others) if not ok]
        print("  [%s] %s%s" % ("pass" if caught else "FAIL", name, ": caught by " + ", ".join(caught[:3]) if caught else ": NOT CAUGHT"))
        holes += 0 if caught else 1
    o2 = dict(others)
    o2["zz_clash"] = "$internal\nsubroutine zz_clash\n$catalog $dict_form\nend\n"
    caught = [x.split(" ")[0] for x, ok, _ in checks(src, o2) if not ok]
    print("  [%s] another program takes the catalogue name%s" % ("pass" if caught else "FAIL", ": caught by " + ", ".join(caught) if caught else ": NOT CAUGHT"))
    holes += 0 if caught else 1
    total = len(MUTANTS[first:]) + 1
    print("\n%d of %d mutants caught, %d missed" % (total - holes, total, holes))
    return 1 if holes else 0


def main():
    missing = [p for p in FILES.values() if not os.path.isfile(p)]
    if missing:
        print("test-dictform-units: CANNOT RUN - not readable: %s" % missing, file=sys.stderr)
        return 2
    if "--selftest" in sys.argv[1:]:
        first = next((int(a.split("=", 1)[1]) for a in sys.argv[1:] if a.startswith("--from=")), 0)
        return selftest(first)
    src, others = load()
    rows = checks(src, others)
    bad = report(rows)
    print("\nNOT MEASURED HERE: that the form shows what the engine says and the IDE saves what the form built.  That is sandbox-dictform.py.")
    print("test-dictform-units: %d checks, %d failed" % (len(rows), bad))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
