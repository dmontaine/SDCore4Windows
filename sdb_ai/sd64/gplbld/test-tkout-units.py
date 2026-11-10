#!/usr/bin/env python3
# test-tkout-units.py - the toolkit's output pane, record picker and labelled form ($tk_out, $tk_pickrec, $tk_form), read off the source as text (S.88 phase 5, F0b, 30 Oct 2026).
#
#   O1  the three are $internal, catalogued once each, take five ($tk_out, $tk_form) or six ($tk_pickrec) arguments, and every call in gpl.bp passes that many
#   O2  none of them writes, deletes, opens or runs anything (the pane keeps its history in MEMORY, the picker only reads, the form validates nothing: the page does, with its own gates)
#   O3  $tk_out: a phantom returns first; the history belongs to the open of the app that made it (ctx<TK.C.EPOCH>): another open starts empty
#   O4  $tk_out draws only an open pane whose layout pane is shown, in the rectangle $tk_layout 'pane' gives, and makes the library widget again only when that rectangle changed
#   O5  $tk_out never closes the pane itself: the op key answers 'handled' only when the library did and no op but open, close and toggle changes the state; the progress total comes from the
#       argument saved before c was cleared
#   O6  $tk_pickrec is $sl_picker with the same five arguments and nothing else; its mode 'list' (2 Nov 26, S.88 U9: the home screen's type-to-find) is $sl_pickwin on the page's list,
#       in $sl_picker since 3 Nov 26 ("Extend the picker"): optional columns, and a Del that only NAMES the entry (res 'delete'; the page confirms and deletes)
#   O7  $tk_form open: a phantom returns first, a form left open is put away, the form is refused (c 'no') when the window is too small, the entries are SCREEN ENTRYs (masked ones with
#       MASK), three message rows, the default button 'ok', the cancel button 'cancel', and tf.open is 1 only at the end
#   O8  $tk_form run: waits for the form's events, a button 'ok' is 'ok' and anything else (the cancel button, Esc, the input ending) is 'cancel', every entry's text is read with SCREEN GET,
#       the entry that has the focus comes back, and the form is NOT hidden
#   O9  $tk_form say: the text is wrapped into exactly the three rows (a written empty text empties the ones not used) and the focus goes to the entry named, with an ELSE
#   O10 $tk_form close: hides the form only when it is open, and then tf.open is 0
#   O11 messages 12253 and 12254 exist, one line each, and the Cancel button has no & mark (the default button has one: two buttons with one letter would shadow the second)
#
# 9 Nov 26 (S.187): V1 and V2 (PILOT B, the output pane of tool_viewers: its open layout, the toggle, what $tk_run answered kept in the pane, Esc and PgUp / PgDn) were DROPPED with their six
# mutants: tool.viewers was removed with the pdf verb (owner: pdf only works at the machine's own display).  They were written against that page's labels and literals; the other pages with
# an output pane (tool_sessions, tool_jobs, tool_test) are built differently, so re-pointing them is a new check, not an edit.  O1-O11 are unchanged.
#
# FREE CHECK: no install, no sd.     python3 .../test-tkout-units.py        python3 .../test-tkout-units.py --selftest [--from=N]
import glob
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
BP = os.environ.get("BPDIR", os.path.normpath(os.path.join(HERE, "..", "sdsys", "gpl.bp")))
MSG = os.path.normpath(os.path.join(BP, "..", "messages"))
NAMES = ("tk_out", "tk_pickrec", "tk_form")
ARGS = {"tk_out": 5, "tk_pickrec": 6, "tk_form": 5}


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
    m = re.search(r"(?m)^%s:\n" % re.escape(name), src)
    if not m:
        return ""
    rest = src[m.end():]
    n = re.search(r"(?m)^[A-Za-z][A-Za-z0-9.]*:$|^end$", rest)
    return rest[:n.start()] if n else rest


def op(src, name):
    m = re.search(r"(?m)^      case op = '%s'\n" % re.escape(name), src)
    if not m:
        return ""
    rest = src[m.end():]
    n = re.search(r"(?m)^      case op = |^   end case", rest)
    return rest[:n.start()] if n else rest


def load():
    s = {n: read(os.path.join(BP, n)) for n in NAMES}
    s["sl_picker"] = read(os.path.join(BP, "sl_picker"))
    s["calls"] = {os.path.basename(p): code(read(p)) for p in glob.glob(os.path.join(BP, "*")) if os.path.isfile(p) and not p.endswith(".h")}
    for n in ("12253", "12254"):
        p = os.path.join(MSG, n)
        s["m" + n] = read(p) if os.path.exists(p) else None
    return s


WRITERS = r"(?m)^\s*(execute|os\.execute|write|writev|writeu|delete|deletelist|open|openseq|openpath|read|readv|readu|readseq|writeseq|chain|perform)(?=\s)|\bkernel\("


def checks(s):
    rows = []

    def ck(name, ok, detail=""):
        rows.append((name, bool(ok), detail))

    out = code(s["tk_out"])
    pk = code(s["tk_pickrec"])
    fm = code(s["tk_form"])

    wrong = []
    for nm, n in ARGS.items():
        for fn, src in s["calls"].items():
            for m in re.finditer(r"\$%s\(([^)]*)\)" % nm, src):
                if fn != nm and len(m.group(1).split(",")) != n:
                    wrong.append((fn, nm, m.group(1)))
    decl = all(("$internal\nsubroutine %s(" % nm in code(s[nm])) and sum(1 for src in s["calls"].values() if "$catalog $%s\n" % nm in src + "\n") == 1 for nm in NAMES)
    hdr = ("subroutine tk_out(op, ctx, a, b, c)" in out and "subroutine tk_pickrec(ctx, mode, file, id, res, newtext)" in pk and "subroutine tk_form(op, ctx, a, b, c)" in fm)
    ck("O1 the three are $internal, catalogued once each, take five / six / five arguments, and every call passes that many", decl and hdr and not wrong, repr(wrong))

    bad = [nm for nm, src in (("tk_out", out), ("tk_pickrec", pk), ("tk_form", fm)) if re.search(WRITERS, src)]
    ck("O2 none writes, deletes, opens or runs anything and none asks the kernel: the pane's history is memory only, the picker reads through the library, the form validates nothing", not bad, repr(bad))

    ck("O3 $tk_out: a phantom returns first; the history belongs to one open of the app (ctx<TK.C.EPOCH>): another open starts with a new, empty collection",
       ordered(out, "tot = c", "c = ''", "if system(25) then return", "if out.epoch # ctx<TK.C.EPOCH> + 0 or jtype(out.w) # 'collection' then", "out.w = collection()", "out.epoch = ctx<TK.C.EPOCH> + 0", "begin case"), out[:400])

    od = op(out, "draw")
    ck("O4 draw: only an open pane whose layout pane is shown, in the rectangle $tk_layout 'pane' gives; the library widget is made again only when the rectangle changed (or never made)",
       ordered(od, "if out.w{'open'} + 0 then", "if pid = '' then pid = 'output'", "call $tk_layout('pane', ctx, pid, rc)", "if rc<1, 5> + 0 then", "if out.w{'ax'} # rc<1, 1> + 0 or", "out.w{'type'} = ''",
               "call $sl_out('init', out.w, scr, '', r)", "call $sl_out('draw', out.w, scr, '', r)", "c = 1"), od[:300])

    ok_ = op(out, "key")
    changers = [o for o in ("add", "draw", "key", "mouse", "focus", "progress", "poll", "clear", "state") if re.search(r"\$sl_out\('(open|close)'", op(out, o))]
    ck("O5 $tk_out never closes the pane itself: only open, close and toggle change the state; key answers 'handled' only when the library did; the progress total is the argument saved before c was cleared",
       not changers and ordered(ok_, "c = 'unhandled'", "if out.w{'open'} + 0 then", "call $sl_out('key', out.w, scr, a, r)", "if r<1> = 'handled' then c = 'handled'")
       and "(if a = '' then '' else a : @fm : b : @fm : tot)" in op(out, "progress"), repr(changers))

    spk = re.sub(r"\s+", " ", label(code(s["sl_picker"]), "pick.list"))
    ck("O6 $tk_pickrec is $sl_picker with the same five arguments and nothing else; mode 'list' (S.88 U9, in $sl_picker since 3 Nov 26) is $sl_pickwin on the list the page gives, with no file "
       "source, cancel unless Enter chose or Del named an entry, the title in and the entry's number out, Del only with mode<4> 'delete', columns only from mode<2> and <3>, and nothing opened",
       re.sub(r"\s+", " ", pk) == "$internal subroutine tk_pickrec(ctx, mode, file, id, res, newtext) $catalog $tk_pickrec call $sl_picker(mode, file, id, res, newtext) return end"
       and "if mode<1> = 'list' then gosub pick.list return end" in re.sub(r"\s+", " ", code(s["sl_picker"]))
       and spk.strip() == "res = 'cancel' ltitle = id ldef = newtext id = '' newtext = '' if system(25) or file = '' then return if not(num(ldef)) or ldef < 1 then ldef = 1 "
       "lhot = '' if mode<4> = 'delete' then lhot = 'del' lcols = '' if mode<2> # '' then lcols = mode<2> : @fm : mode<3> ltyped = '' lcur = '' "
       "call $sl_pickwin(file, ltitle, 0, ldef, pr, ps, '', '', lhot, ltyped, lcols, lcur) begin case case ps = 0 and pr > 0 id = pr res = 'ok' "
       "case ps = 2 and pr = 'del' and lcur > 0 id = lcur res = 'delete' end case return", pk + " || " + spk)

    of = label(fm, "open.form")
    ck("O7 $tk_form open: a phantom returns first, a form left open is put away, the form is refused when the window is too small, the entries are SCREEN ENTRYs (a masked one with MASK), three message rows, "
       "the default button 'ok', the cancel button, and tf.open is 1 only at the end",
       ordered(of, "c = 'no'", "if system(25) then return", "if tf.open + 0 then gosub close.form", "if nf < 1 then return", "if bw < 40 or bh > sh - 2 then return", "screen form title ttl at bx,by size bw,bh returning tf.f",
               "if fd<1, 5> + 0 = 1 then", "mask maxlen ml", "end else", "maxlen ml", "for j = 1 to 3", "'m' : j", "screen button tf.f, 'ok', eff at 2,nf + 6 default",
               "screen button tf.f, 'cancel', sysmsg(12254) at 2 + len(eff) + 6,nf + 6 cancel", "tf.open = 1", "c = ''"), of[:300])

    rf = label(fm, "run.form")
    ck("O8 $tk_form run: waits for events; the button 'ok' is 'ok', anything else (Cancel, Esc, the input ending) is 'cancel'; every entry is read with SCREEN GET; the focused entry comes back; the form is not hidden",
       ordered(rf, "if not(tf.open + 0) then return", "screen wait tf.f returning ev then", "case ev<1> = 'focus'", "null", "case ev<1> = 'button'", "res = (if ev<2> = 'ok' then 'ok' else 'cancel')", "case ev<1> = 'cancel'",
               "end else", "res = 'cancel'", "repeat", "screen get tf.f, tf.ids<1, i> returning v", "a = res", "fx = tf.f{'focus'} + 0", "c = last", "c = fw{'id'}") and "screen hide" not in rf, rf[:300])

    sf = label(fm, "say.text")
    ck("O9 $tk_form say: the text is wrapped to the message width into exactly three rows (each set, so a written empty one empties it) and the focus goes to the entry named, with an ELSE",
       ordered(sf, "if not(tf.open + 0) then return", "call $tk_wrap(a, tf.msgw, pieces)", "for j = 1 to 3", "screen set tf.f, 'm' : j text pieces<j>[1, tf.msgw]", "next j", "if b # '' then", "screen focus tf.f, b else null"), sf[:300])

    cf = label(fm, "close.form")
    ck("O10 $tk_form close: hides the form only when it is open, and then tf.open is 0", ordered(cf, "if tf.open + 0 then", "screen hide tf.f", "tf.open = 0"), cf[:200])

    # V1 and V2 (tool_viewers' output pane) went with the page, 9 Nov 26 (S.187): see the header

    m8, m9 = s["m12253"], s["m12254"]
    ck("O11 messages 12253 and 12254 exist, one line each, and the Cancel button has no & mark (the default button has one in its caller: two buttons with one letter would shadow the second)",
       m8 is not None and m9 is not None and len(m8.rstrip("\n").split("\n")) == 1 and len(m9.rstrip("\n").split("\n")) == 1 and "&" not in m9, repr((m8, m9)))
    return rows


def sub(src, old, new):
    if src.count(old) != 1:
        raise SystemExit("selftest: the old text occurs %d times, not once:\n%s" % (src.count(old), old[:120]))
    return src.replace(old, new)


MUTANTS = [
    ("tk_out loses an argument", "tk_out", "subroutine tk_out(op, ctx, a, b, c)", "subroutine tk_out(op, ctx, a, b)", "O1"),
    ("the pane writes its history to a file", "tk_out", "         call $sl_out('add', out.w, '', a : @fm : b, r)\n", "         call $sl_out('add', out.w, '', a : @fm : b, r)\n         write b on fh, 'out'\n", "O2"),
    ("the form asks the kernel", "tk_form", "   c = 'no'\n   if system(25) then return", "   c = 'no'\n   x = kernel(K$AI.STATUS, 0)\n   if system(25) then return", "O2"),
    ("the history survives another open", "tk_out", "   if out.epoch # ctx<TK.C.EPOCH> + 0 or jtype(out.w) # 'collection' then\n", "   if 0 then\n", "O3"),
    ("a phantom draws", "tk_out", "   if system(25) then return                     ;* a phantom", "   null                                          ;* a phantom", "O3"),
    ("the pane is drawn closed", "tk_out", "      case op = 'draw'\n         if out.w{'open'} + 0 then", "      case op = 'draw'\n         if 1 then", "O4"),
    ("the pane is drawn where the layout collapsed it", "tk_out", "            if rc<1, 5> + 0 then\n", "            if 1 then\n", "O4"),
    ("the widget is made again on every draw", "tk_out", " or out.w{'type'} = '' then", " or 1 then", "O4"),
    ("a key closes the pane", "tk_out", "            call $sl_out('key', out.w, scr, a, r)\n", "            call $sl_out('key', out.w, scr, a, r)\n            if a = 'esc' then call $sl_out('close', out.w, scr, '', r)\n", "O5"),
    ("the pane takes every key", "tk_out", "            if r<1> = 'handled' then c = 'handled'\n         end\n      case op = 'mouse'", "            c = 'handled'\n         end\n      case op = 'mouse'", "O5"),
    ("the progress total is lost", "tk_out", "a : @fm : b : @fm : tot)", "a : @fm : b : @fm : c)", "O5"),
    ("the picker writes", "tk_pickrec", "   call $sl_picker(mode, file, id, res, newtext)\n", "   call $sl_picker(mode, file, id, res, newtext)\n   write id on file, id\n", "O6"),
    ("the picker is asked for a file only", "tk_pickrec", "call $sl_picker(mode, file, id, res, newtext)", "call $sl_picker('file', file, id, res, newtext)", "O6"),
    ("a form that is too small is drawn", "tk_form", "   if bw < 40 or bh > sh - 2 then return\n", "", "O7"),
    ("a masked entry shows its text", "tk_form", "value ini mask maxlen ml", "value ini maxlen ml", "O7"),
    ("the form is open before it is drawn", "tk_form", "   tf.open = 1\n   c = ''", "   c = ''", "O7"),
    ("Cancel is not the cancel button", "tk_form", " at 2 + len(eff) + 6,nf + 6 cancel", " at 2 + len(eff) + 6,nf + 6", "O7"),
    ("run hides the form", "tk_form", "   a = res\n   fx = tf.f", "   screen hide tf.f\n   a = res\n   fx = tf.f", "O8"),
    ("any button is ok", "tk_form", "res = (if ev<2> = 'ok' then 'ok' else 'cancel')", "res = 'ok'", "O8"),
    ("the end of the input is ok", "tk_form", "      end else\n         res = 'cancel'                              ;* the input ended", "      end else\n         res = 'ok'                              ;* the input ended", "O8"),
    ("say leaves the old rows", "tk_form", "   for j = 1 to 3\n      screen set tf.f, 'm' : j text pieces<j>[1, tf.msgw]", "   for j = 1 to 1\n      screen set tf.f, 'm' : j text pieces<j>[1, tf.msgw]", "O9"),
    ("say does not move the focus", "tk_form", "      screen focus tf.f, b else null\n", "      null\n", "O9"),
    ("close hides a form that is not open", "tk_form", "close.form:\n   if tf.open + 0 then\n      screen hide tf.f\n      tf.open = 0\n   end", "close.form:\n   screen hide tf.f\n   tf.open = 0", "O10"),
    ("Cancel has a mnemonic", "m12254", "Cancel", "&Cancel", "O11"),
    # 2 Nov 26 (S.88 U9): the list mode of $tk_pickrec - marker M_U9 for --from= (the first of these)
    # 3 Nov 26 ("Extend the picker"): the list mode moved into $sl_picker; the same two mutants there, and three for Del and the facade - M_PICK is the first of these
    ("a list pick answers ok on Esc", "sl_picker", "      case ps = 0 and pr > 0\n", "      case pr > 0\n", "O6"),
    ("a list pick is given a file to read", "sl_picker", "call $sl_pickwin(file, ltitle, 0, ldef, pr, ps, '', '', lhot, ltyped, lcols, lcur)", "call $sl_pickwin('', ltitle, 0, ldef, pr, ps, file, '', lhot, ltyped, lcols, lcur)", "O6"),
    ("Del is offered to every list", "sl_picker", "   if mode<4> = 'delete' then lhot = 'del'\n", "   lhot = 'del'\n", "O6"),
    ("Del answers an entry when none is shown", "sl_picker", "      case ps = 2 and pr = 'del' and lcur > 0\n", "      case ps = 2 and pr = 'del'\n", "O6"),
    ("the list mode is left in the facade", "tk_pickrec", "   call $sl_picker(mode, file, id, res, newtext)\n   return\n", "   if mode = 'list' then return\n   call $sl_picker(mode, file, id, res, newtext)\n   return\n", "O6"),
]
M_U9 = len(MUTANTS) - 5
M_PICK = M_U9


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
        over = {key: s0[key].replace(old, new)}
        if key in NAMES:
            over["calls"] = dict(s0["calls"])
            over["calls"][key] = code(over[key])
        failed = [n.split()[0] for n, ok, _ in run(over) if not ok]
        hit = want in failed
        print("  [%s] selftest: %s is caught by %s (failed: %s)" % ("PASS" if hit else "FAIL", name, want, " ".join(failed) or "none"))
        bad += 0 if hit else 1
    print("selftest: %s" % ("every mutant was caught" if bad == 0 else "%d problem(s)" % bad))
    return 0 if bad == 0 else 1


def main(argv):
    for n in NAMES:
        if not os.path.exists(os.path.join(BP, n)):
            print("test-tkout-units: no such program %s" % n)
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
    print("test-tkout-units: %d checks, %d failed" % (len(rows), bad))
    return 0 if bad == 0 else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
