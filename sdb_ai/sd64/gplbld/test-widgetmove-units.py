#!/usr/bin/env python3
# test-widgetmove-units.py - S.88 p3.3a (2 Nov 2026): moving and sizing a widget that a form already has, and the IDE's resize that uses it.  FREE CHECK, text only (comment lines and
# ;* tails removed), no install, no sudo, no sd.
#
#   python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/test-widgetmove-units.py
#   python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/test-widgetmove-units.py --selftest      (mutants; each must turn a row red)
#
#   W0  NULL CASE: every file and routine read here is there
#   W1  $sl_widget_move is $internal, takes six arguments, decides every refusal (not a form, no widget, a place or size that is not a number, a kind that takes no
#       size, a label or entry asked for a height other than 1) BEFORE it changes anything, and never calls a kind's init
#   W2  it hands a memo, a table and a tree their own op 'size'; a label and an entry get a width; SCREEN MOVE (!screen_move) still takes a size for a container,
#       viewport or frame only (sandbox-viewport.py needs a label to answer ELSE)
#   W3  $sl_memo's op 'size' is after 'mouse' (test-memoundo slices 'init' to 'draw'), sets the size, works the rectangle out again (geom), brings the view to
#       the cursor and stores - and does not clear the undo steps, the mark or the find text; the bpon read is in geom, which every call runs
#   W4  $sl_table's and $sl_tree's 'size': the table keeps its order, marks and column widths (no order.rows, no picked = ''), the tree its open nodes (no opn = '')
#   W5  the IDE's relayout moves the form it has (move.form) and makes one only when it has none; move.form makes no widget but a separator label, takes the
#       form off the screen without putting back what was under it (f{'shown'} 0, f{'under'} ''), and gives the form fw by fh
#   W6  DRIFT: every widget new.form makes is moved by move.form, to the same place and size, expression for expression (the table below); the column lists of
#       the two tables are the same text
# NOT SAID HERE: that the editor keeps its undo steps on a screen - that is sandbox-ide-resize.py section resize (red on the IDE that made the form again).
import os
import re
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
BP = os.path.normpath(os.path.join(HERE, "..", "sdsys", "gpl.bp"))
NAMES = ("sl_widget_move", "sl_memo", "sl_table", "sl_tree", "screen_move", "ide")
F = {k: os.environ.get("WM_" + k.upper(), os.path.join(BP, k)) for k in NAMES}
passed = failed = 0

# widget id: (what new.form says, what move.form says), each squeezed to single blanks
DRIFT = [
    ("tree", "screen tree f, 'tree', nodes at 1,1 size tw - 1,ih", "call $sl_widget_move(f, 'tree', 1, 1, (tw - 1) : @vm : ih, r)"),
    ("sep", "screen label f, 'sep' : r, vch at tw,r width 1 attr 'window'", "call $sl_widget_move(f, 'sep' : r, tw, r, '', mr)"),
    ("tabbar", "screen label f, 'tabbar', ' ' at ex,1 width ew attr 'tab'", "call $sl_widget_move(f, 'tabbar', ex, 1, ew : @vm : 1, r)"),
    ("tabs", "screen tabs f, 'tabs', labels at ex,1 value tab.n", "call $sl_widget_move(f, 'tabs', ex, 1, '', r)"),
    ("ed", "screen memo f, 'ed', ed.text at ex,2 size ew,mh syntax ed.syn lnum", "call $sl_widget_move(f, 'ed', ex, 2, ew : @vm : mh, r)"),
    ("errbar", "screen label f, 'errbar', sysmsg(12236) at ex,err.y width ew attr 'window'", "call $sl_widget_move(f, 'errbar', ex, err.y, ew : @vm : 1, r)"),
    ("err", "screen table f, 'err', cols, err.rows at ex,err.y + 1 size ew,eh - 1 - ai.rows", "call $sl_widget_move(f, 'err', ex, err.y + 1, ew : @vm : (eh - 1 - ai.rows), r)"),
    ("ailab", "screen label f, 'ailab', sysmsg(12641) at ex,ai.y width 4 attr 'window'", "call $sl_widget_move(f, 'ailab', ex, ai.y, '', r)"),
    ("ai", "screen entry f, 'ai' at ex + 4,ai.y width ew - 4 maxlen 300", "call $sl_widget_move(f, 'ai', ex + 4, ai.y, (ew - 4) : @vm : 1, r)"),
    ("fld", "sysmsg(12140) : @sm : (ew - 26) : 'L', '' at ex,2 size ew,mh - 1", "call $sl_widget_move(f, 'fld', ex, 2, ew : @vm : (mh - 1), r)"),
    ("fpath", "screen label f, 'fpath', ' ' at ex,mh + 1 width ew attr 'window'", "call $sl_widget_move(f, 'fpath', ex, mh + 1, ew : @vm : 1, r)"),
    ("ixtree", "screen label f, 'ixtree', ind.want<1> at tw - 4,0 width 3 attr 'window'", "call $sl_widget_move(f, 'ixtree', tw - 4, 0, '', r)"),
    ("ixtabs", "screen label f, 'ixtabs', ind.want<2> at ex + ew - 3,1 width 3 attr 'tab'", "call $sl_widget_move(f, 'ixtabs', ex + ew - 3, 1, '', r)"),
    ("ixed", "screen label f, 'ixed', ind.want<3> at ex + ew - 4,0 width 3 attr 'window'", "call $sl_widget_move(f, 'ixed', ex + ew - 4, 0, '', r)"),
    ("ixerr", "screen label f, 'ixerr', ind.want<4> at ex + ew - 3,err.y width 3 attr 'window'", "call $sl_widget_move(f, 'ixerr', ex + ew - 3, err.y, '', r)"),
]
ERR_COLS = "sysmsg(12226) : @sm : '6R' : @vm : sysmsg(12227) : @sm : (ew - 11) : 'L'"
FLD_COLS = "sysmsg(12138) : @sm : '10L' : @vm : sysmsg(12139) : @sm : '10L' : @vm : sysmsg(12140) : @sm : (ew - 26) : 'L'"


def row(name, ok, detail=""):
    global passed, failed
    if ok:
        passed += 1
        print("  [PASS] " + name)
    else:
        failed += 1
        print("  [FAIL] " + name + ("   <- " + detail[:400] if detail else ""))


def bas(key):
    out = []
    for ln in open(F[key], encoding="latin-1").read().split("\n"):
        if ln.lstrip().startswith("*"):
            continue
        out.append(re.sub(r"\s;\*.*$", "", ln).rstrip())
    return "\n".join(out)


def sq(s):
    return re.sub(r"\s+", " ", s).strip()


def label(src, name):
    """from 'name:' to the first line that is only 'return'"""
    m = re.search(r"^" + re.escape(name) + r":\n(.*?)\n[ \t]*return[ \t]*$", src, re.S | re.M)
    return m.group(1) if m else ""


def case(src, op, nxt):
    """the body of `case op = '<op>'` up to `case op = '<nxt>'` (or `end case`)"""
    a = src.find("case op = '%s'" % op)
    if a < 0:
        return ""
    b = src.find("case op = '%s'" % nxt, a + 1) if nxt else -1
    if b < 0:
        b = src.find("end case", a)
    return src[a:b]


def run():
    S = {k: bas(k) for k in NAMES}
    wm, memo, tab, tree, smv, ide = (S[k] for k in NAMES)
    nf = label(ide, "new.form")
    mf = label(ide, "move.form")
    rl = label(ide, "relayout")
    row("W0 NULL CASE: the six files and the routines new.form, move.form, relayout are there",
        all(len(S[k]) > 500 for k in NAMES) and len(nf) > 2000 and len(mf) > 500 and len(rl) > 50, repr({k: len(v) for k, v in S.items()}))

    # ---- W1 W2 $sl_widget_move ---------------------------------------------------------------------------------------------------------
    first_change = min([i for i in (wm.find("w{'x'} ="), wm.find("w{'y'} ="), wm.find("w{'w'} ="), wm.find("call $sl_memo")) if i >= 0] or [-1])
    before = wm[:first_change] if first_change > 0 else ""
    row("W1 $sl_widget_move is $internal, catalogued, with six arguments",
        "$internal" in wm and re.search(r"subroutine sl_widget_move\(f, id, x, y, sz, ret\)", wm) and "$catalog $sl_widget_move" in wm, wm[:300])
    row("W1 ... every refusal is decided before the first change (not a form, no widget, not numbers, a kind with no size, a height other than 1)",
        first_change > 0 and "ret = 1" in before and "if jtype(f) # 'collection' then return" in before and "if n = 0 then return" in before
        and "not(num(x))" in before and "not(num(sw))" in before and "case 1\n            return" in before and "if sh # '' and sh + 0 # 1 then return" in before
        and "ret = 0" not in before, before[-600:])
    row("W1 ... it never calls a kind's init", "'init'" not in wm)
    row("W2 a memo, a table and a tree get their own op 'size'; a label and an entry (not a combo's: fw) a width",
        all("call $sl_%s('size', w, '', sw : @fm : sh, r)" % k in wm for k in ("memo", "table", "tree"))
        and "case wt = 'label' or (wt = 'entry' and w{'fw'} = '')" in wm and "w{'w'} = sw + 0" in wm
        and "if x # '' then w{'x'} = x + 0" in wm and "if y # '' then w{'y'} = y + 0" in wm, "")
    row("W2 SCREEN MOVE still takes a size for a container, viewport or frame only",
        "if (sw # '' or sh # '') and not(ctr or wt = 'frame') then return" in smv and "sl_widget_move" not in smv)

    # ---- W3 W4 the 'size' ops ------------------------------------------------------------------------------------------------------------
    ms = case(memo, "size", "bptoggle")
    order = [memo.find("case op = '%s'" % o) for o in ("init", "snap", "draw", "mouse", "size", "bptoggle")]
    row("W3 $sl_memo's 'size' is after 'mouse' and before 'bptoggle' (and init, snap, draw keep their order)", all(o >= 0 for o in order) and order == sorted(order), repr(order))
    row("W3 ... it sets the size, works the rectangle out again, follows the cursor and stores",
        re.search(r"w\{'w'\} = key<1> \+ 0.*w\{'h'\} = key<2> \+ 0.*gosub geom.*w\{'w'\} = mw.*w\{'h'\} = mh \+ hb.*gosub count.*gosub scroll.*gosub store", ms, re.S) is not None, ms)
    row("W3 ... and keeps the undo steps, the mark and the find text (no snap.clear, no mx / my / fnd reset, no lastop reset)",
        ms != "" and "snap.clear" not in ms and not re.search(r"\b(mx|my|fnd)\s*=", ms) and "lastop" not in ms and "gosub paint" not in ms, ms)
    g = label(memo, "geom")
    head = memo[:memo.find("begin case")]
    row("W3 ... geom holds the rectangle (hbar, gutter, bpon, tw) and every call runs it before the case list",
        "bpon = w{'bpon'} + 0" in g and "hb = 1" in g and "tw = mw - 1 - gut" in g and "gosub geom" in head and "bpon = w{'bpon'}" not in head, g)
    ts = case(tab, "size", "filter")
    row("W4 $sl_table's 'size' keeps the order, the marks and the column widths, and follows the current row",
        re.search(r"gosub widths.*th = w\{'h'\} \+ 0 - 1.*gosub scroll.*gosub store", ts, re.S) is not None and "order.rows" not in ts and "picked = ''" not in ts
        and "cwid = ''" not in ts and "ord = ''" not in ts, ts)
    rs = case(tree, "size", "")
    row("W4 $sl_tree's 'size' keeps the open nodes and follows the current node",
        re.search(r"w\{'w'\} = tw0.*w\{'h'\} = th.*gosub rows.*gosub scroll.*gosub store", rs, re.S) is not None and "opn = ''" not in rs and "top = 1" not in rs, rs)

    # ---- W5 the IDE ----------------------------------------------------------------------------------------------------------------------
    row("W5 relayout moves the form it has and makes one only when there is none, or when move.form was refused for a widget (2 Nov 26 review: mv.bad)",
        re.search(r"screen clear\n\s*mv\.bad = 0[^\n]*\n\s*if have\.form then\n\s*gosub move\.form\n\s*end else\n\s*gosub new\.form\n\s*end\n\s*if have\.form and mv\.bad > 0 then", rl) is not None
        and "mv.bad += r" in mf and "if mv.bad > 0 then return" in mf, rl)
    made = re.findall(r"screen (form|tree|memo|table|entry|tabs|label|check|button|list) ", mf)
    row("W5 move.form makes no widget but the separator's labels, and takes the form off the screen without putting anything back",
        made == ["label"] and "screen label f, 'sep' : r" in mf and "f{'shown'} = 0" in mf and "f{'under'} = ''" in mf and "f{'w'} = fw" in mf and "f{'h'} = fh" in mf
        and "screen clear" not in mf and "gosub new.form" not in mf, repr(made))
    row("W5 ... the separator loses the labels of rows the form no longer has", re.search(r"r = ih \+ 1\n\s*loop\n.*'sep' : r.*while sn > 0\n\s*call \$sl_form\('delete'", mf, re.S) is not None, mf[:300])

    # ---- W6 drift ----------------------------------------------------------------------------------------------------------------------------
    snf, smf = sq(nf), sq(mf)
    for wid, a, b in DRIFT:
        row("W6 %s: new.form and move.form put it in the same place at the same size" % wid, sq(a) in snf and sq(b) in smf, "%s / %s" % (sq(a) in snf, sq(b) in smf))
    row("W6 ed: both of new.form's memo lines (read-only and not) are at ex,2 size ew,mh", snf.count("ed.text at ex,2 size ew,mh syntax ed.syn lnum") == 2)
    ids_new = set(re.findall(r"screen (?:tree|memo|table|entry|tabs|label) f, '(\w+)'", nf))
    ids_move = set(re.findall(r"call \$sl_widget_move\(f, '(\w+)'", mf)) | {"sep"}
    row("W6 every widget new.form makes, move.form moves (and nothing else)", ids_new | {"sep"} == ids_move, repr(sorted(ids_new ^ (ids_move - {"sep"}))))
    row("W6 the messages table's and the fields table's columns are the same text in both",
        ("cols = " + ERR_COLS) in snf and ("tbw{'cols'} = " + ERR_COLS) in smf and sq(FLD_COLS) in snf and ("tbw{'cols'} = " + FLD_COLS) in smf, "")
    print("test-widgetmove-units: %d passed, %d failed" % (passed, failed))
    return 0 if failed == 0 else 1


def selftest():
    import shutil
    t = tempfile.mkdtemp()
    caught = missed = 0
    real = {k: open(v, encoding="latin-1").read() for k, v in F.items()}

    def mutant(name, which, old, new):
        nonlocal caught, missed
        if real[which].count(old) != 1:
            print("  [MISSED] %s: the text to change is found %d times, not once" % (name, real[which].count(old)))
            missed += 1
            return
        f = os.path.join(t, re.sub(r"\W", "_", name))
        open(f, "w", encoding="latin-1").write(real[which].replace(old, new, 1))
        env = dict(os.environ)
        env["WM_" + which.upper()] = f
        r = subprocess.run([sys.executable, os.path.abspath(__file__)], env=env, capture_output=True, text=True)
        if r.returncode != 0:
            print("  [caught] %s" % name)
            caught += 1
        else:
            print("  [MISSED] %s: the check still passed" % name)
            missed += 1

    print("selftest: the real files first (must pass), then mutants (each must not)")
    r = subprocess.run([sys.executable, os.path.abspath(__file__)], capture_output=True, text=True)
    if r.returncode != 0:
        print("  [FAIL] the real files do not pass:\n" + r.stdout[-1500:])
        return 1
    print("  [ok] the real files pass")
    mutant("relayout makes the form again", "ide", "   if have.form then\n      gosub move.form\n", "   if have.form then\n      gosub new.form\n")
    mutant("move.form keeps the stale region", "ide", "   f{'under'} = ''\n", "")
    mutant("new.form moves the editor, move.form does not follow", "ide", "ed.text at ex,2 size ew,mh syntax ed.syn lnum readonly", "ed.text at ex,3 size ew,mh syntax ed.syn lnum readonly")
    mutant("move.form forgets the AI entry", "ide", "      call $sl_widget_move(f, 'ai', ex + 4, ai.y, (ew - 4) : @vm : 1, r)\n", "")
    mutant("the separator keeps rows it lost", "ide", "      call $sl_form('delete', f, scr, 'sep' : r, dn)\n", "      null\n")
    mutant("the messages columns drift", "ide", "tbw{'cols'} = sysmsg(12226) : @sm : '6R' : @vm : sysmsg(12227) : @sm : (ew - 11) : 'L'", "tbw{'cols'} = sysmsg(12226) : @sm : '6R' : @vm : sysmsg(12227) : @sm : (ew - 12) : 'L'")
    mutant("the memo's size starts the widget again", "sl_memo", "         gosub geom\n         w{'w'} = mw\n", "         gosub geom\n         gosub snap.clear\n         w{'w'} = mw\n")
    mutant("the memo's size clears the mark", "sl_memo", "         w{'h'} = mh + hb\n         gosub count\n         gosub scroll\n", "         w{'h'} = mh + hb\n         mx = 0 ; my = 0\n         gosub count\n         gosub scroll\n")
    mutant("the memo's size does not store", "sl_memo", "         gosub scroll\n         gosub store\n         ret = 'handled'\n\n      case op = 'bptoggle'", "         gosub scroll\n         ret = 'handled'\n\n      case op = 'bptoggle'")
    mutant("the memo no longer works its rectangle out per call", "sl_memo", "   ob0 = lines                                   ;* the text the marks are kept for: store moves them when the number of lines is not the same as at the end of this call\n   gosub geom\n",
           "   ob0 = lines                                   ;* the text the marks are kept for: store moves them when the number of lines is not the same as at the end of this call\n")
    mutant("the table's size re-sorts", "sl_table", "         gosub widths\n         th = w{'h'} + 0 - 1\n         gosub scroll\n         gosub store\n", "         gosub widths\n         gosub order.rows\n         th = w{'h'} + 0 - 1\n         gosub scroll\n         gosub store\n")
    mutant("the tree's size closes every node", "sl_tree", "         w{'h'} = th\n         gosub rows\n", "         w{'h'} = th\n         opn = ''\n         gosub rows\n")
    mutant("widget move forgets x", "sl_widget_move", "   if x # '' then w{'x'} = x + 0\n", "")
    mutant("widget move changes x before a refusal (moved up)", "sl_widget_move", "   * Decide everything before anything changes", "   if x # '' then w{'x'} = x + 0\n   * Decide everything before anything changes")
    mutant("widget move calls init", "sl_widget_move", "call $sl_tree('size', w, '', sw : @fm : sh, r)", "call $sl_tree('init', w, '', sw : @fm : sh, r)")
    mutant("widget move sizes any kind", "sl_widget_move", "         case 1\n            return\n", "         case 1\n            kind.op = 'width'\n")
    mutant("screen move takes a size for a label", "screen_move", "if (sw # '' or sh # '') and not(ctr or wt = 'frame') then return", "if (sw # '' or sh # '') and not(ctr or wt = 'frame' or wt = 'label') then return")
    shutil.rmtree(t, ignore_errors=True)
    print("selftest: %d of %d mutants caught, %d missed" % (caught, caught + missed, missed))
    return 0 if missed == 0 else 1


if __name__ == "__main__":
    sys.exit(selftest() if "--selftest" in sys.argv else run())
