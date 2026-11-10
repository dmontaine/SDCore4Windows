#!/usr/bin/env python3
"""test-l2-misc-units.py - five toolkit pages on the layout service (S.88 stage L2): the holder's TOOL.GATES ($tool_mygates), TOOL.KEYS, TOOL.VOC, TOOL.DICT and the throw-away TKTEST,
and stage C for TOOL.VOC and TOOL.DICT (E hands the record to the IDE).  Free: no install, no sudo, no sd.

    python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/test-l2-misc-units.py [--selftest]

WHAT THIS IS, AND WHAT IT IS NOT.  It reads each page's BASIC as text, with comments removed, takes the pane DECLARATION out of the page's own `declare.layout`, lays it out with the geometry model of
test-tklayout-units.py (a copy of $tk_layout's equations; that file is shared and not edited here) and holds the result against what the page drew before L2.  ***IT RUNS NOTHING, SO IT CANNOT SAY
THAT A PAGE IS DRAWN IN A BIGGER WINDOW***: that is `sandbox-l2-misc.py`, which opens each page on a pseudo-terminal at 140 by 43, grows it to 180 by 55 while it runs and starts it at 200 by 60, and
reads the boxes off the screen against this file's rectangles.  What a text check is for:

  L2-0  NULL CASE: the model loaded, the four declaring pages were found with the panes the tables here expect (3, 7, 2, 2), and the tables know every page.
  L2-1  every declaration is accepted by the model's version of $tk_layout 'declare' (ids, bands, columns, sizes, the reference body 138 by 39).
  L2-2  AT 140 BY 43 THE DECLARATION GIVES EXACTLY THE BOXES THE PAGE DREW BEFORE L2 (REF below: the literal `screen box at x,y size w,h` of each page at the commit before L2), in the order declared, every pane
        shown, mode full, the declared sizes being those boxes.  L2-2b: while the committed page still holds the literal boxes, every box of REF is one of them.
  L2-3  the names the page derives from its rectangles (get.rects: the row counts, the text widths, the column of "Points at") are at 140 by 43 the numbers the page used as literals, and so is every
        row and column it draws at or tests the mouse against (EXPRS: the expression as the page writes it, looked for in the page and evaluated here).
  L2-4  at 150 by 45, 180 by 55, 200 by 60, 233 by 71 and 500 by 300 every pane is shown, at least its 140-by-43 size, inside the body, no two overlap, the panes of a band fill the body's width and the
        bands its height less the rows the page has always left empty, every row and column a text uses stays inside its box (for the first and the last row), and every row count and text width follows
        the box it is tied to.  L2-4b worked values at 180 by 55 (a pin on the declared weights).
  L2-5  the panes the page asks $tk_layout for are the panes it declared, each rectangle is taken whole, and every pane is drawn as a box from it; the screen is cleared first (the keys page cleared nothing).
  L2-6  the order: the layout is declared after $tk_open and before the first read; a resize is refresh, the rectangles again, the scroll kept inside the list, the generation, the redraw; a page that hands the
        terminal over declares again when it has the screen back.
  L2-7  no number that is really the window's is left in the drawing and the mouse code: no 128, 134, 136, 138 or 139, no `at <number>,`, no `for r = 1 to <number>`, no `ctx<TK.C.H> - 5`.
  L2-8  the floor each page declares stays 140 by 43: $tk_open is called with its four arguments.
  L2-9  STAGE C: TOOL.VOC's E runs `ide voc <id>` and TOOL.DICT's `ide dict <file> <id>` (the same character checks before, the same hand-over after), the one list of commands TOOL.DICT hands the terminal
        to is `ide list.index`, no text the page shows names SED, and the IDE starts on exactly those two forms and refuses nothing the page sends (its floor, 140 by 43 since its window lock of 28 Oct 26, is the pages' own and no higher).
  L2-10 TKTEST declares no pane on purpose (its table stands at column 0, its forms at the places the library's suite measures) but follows a resize: refresh and a new generation of the frame.

--selftest breaks each invariant in the way an edit plausibly would and requires the named check to notice; a mutant that nothing catches is a failure of the self-test.

START-HISTORY:
28 Oct 26 dm  New (S.88 L2, TOOL.VIEWERS, TOOL.GATES for the holder, TOOL.KEYS, TOOL.VOC, TOOL.DICT, TKTEST; stage C for TOOL.VOC and TOOL.DICT).
9 Nov 26 (S.187): TOOL.VIEWERS (the Bypass programs page) was REMOVED from Core with the pdf verb (owner, 9 Nov 2026: pdf only works at the machine's own display), so tool_viewers is gone
              from every table (REF, RECTVARS, CONSTS, TIED, SPARE, WORKED, EXPRS, MARKS, the $tk_open and resize lists) and its eleven mutants with it.  L2-8's mutant now declares a floor
              on TOOL.KEYS.  The model mutant ("grows from what the panes need") was DROPPED: only the viewers left rows empty (SPARE 3), so on the four pages left the two growth rules
              give the same boxes and no check can tell them apart; L2-2 keeps its page mutants.  L2-4b keeps its worked values for the four pages and its TOOL.GATES mutant.
END-HISTORY
"""

import importlib.util
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SDSYS = os.path.normpath(os.path.join(HERE, "..", "sdsys"))
GPL = os.path.join(SDSYS, "gpl.bp")
HELP = os.path.join(SDSYS, "helptext")
PAGE_NAMES = ["tool_mygates","tool_keys", "tool_voc", "tool_dict"]
SIZES = [(150, 45), (180, 55), (200, 60), (233, 71), (500, 300)]
RTW = 134                                     # the text width of a pane in the reference layout (140 by 43): 138 less 4

# The boxes each page drew at 140 by 43 before L2 (x, y, w, h), in the order the page declares its panes, with the title the box carries.
REF = {
    "tool_mygates": [("gates", "What this account may do", (1, 1, 138, 22)), ("cell", "The row under the cursor", (1, 23, 138, 11)), ("note", "Where this comes from", (1, 34, 138, 6))],
    "tool_keys": [("terminal", "Terminal", (1, 1, 45, 12)), ("lastkeys", "Last keys", (1, 13, 45, 27)), ("seen", "Keys seen", (47, 1, 46, 17)), ("styles", "Styles", (47, 18, 46, 22)),
                  ("mouse", "Mouse", (94, 1, 45, 10)), ("boxes", "Box drawing", (94, 11, 45, 14)), ("help", "Help", (94, 25, 45, 15))],
    "tool_voc": [("list", "The VOC of ", (1, 1, 138, 22)), ("detail", "The entry under the cursor", (1, 23, 138, 17))],
    "tool_dict": [("list", "Dictionary of ", (1, 1, 138, 22)), ("detail", "The item under the cursor", (1, 23, 138, 17))],
}
# The variables a page names a pane's rectangle with: (x, y, w, h), as get.rects writes them
RECTVARS = {
    "tool_mygates": {"gates": ("g.x", "g.y", "g.w", "g.h"), "cell": ("c.x", "c.y", "c.w", "c.h"), "note": ("s.x", "s.y", "s.w", "s.h")},
    "tool_keys": {"terminal": ("t.x", "t.y", "t.w", "t.h"), "lastkeys": ("k.x", "k.y", "k.w", "k.h"), "seen": ("s.x", "s.y", "s.w", "s.h"), "styles": ("st.x", "st.y", "st.w", "st.h"),
                  "mouse": ("mo.x", "mo.y", "mo.w", "mo.h"), "boxes": ("bx.x", "bx.y", "bx.w", "bx.h"), "help": ("hp.x", "hp.y", "hp.w", "hp.h")},
    "tool_voc": {"list": ("lx", "ly", "lw", "lh"), "detail": ("dx", "dy", "dw", "dh")},
    "tool_dict": {"list": ("lx", "ly", "lw", "lh"), "detail": ("dx", "dy", "dw", "dh")},
}
# What the page derives from its rectangles, at 140 by 43, as the literal it used before: (name as the evaluator spells it, value)
CONSTS = {
    "tool_mygates": [("VIS", 17), ("g_tw", 134), ("c_tw", 134), ("s_tw", 134)],
    "tool_keys": [("LOGN", 25), ("t_tw", 41), ("k_tw", 41), ("st_tw", 42), ("mo_tw", 41), ("hp_tw", 41)],
    "tool_voc": [("VIS", 16), ("tw", 134), ("pcol", 58)],
    "tool_dict": [("VIS", 16), ("tw", 134)],
}
# The names that follow a box: the rows or the width of text tied to the height or the width of a pane (it grows by what the pane grew by)
TIED = {
    "tool_mygates": {"VIS": ("gates", "h"), "g_tw": ("gates", "w"), "c_tw": ("cell", "w"), "s_tw": ("note", "w")},
    "tool_keys": {"LOGN": ("lastkeys", "h"), "t_tw": ("terminal", "w"), "k_tw": ("lastkeys", "w"), "st_tw": ("styles", "w"), "mo_tw": ("mouse", "w"), "hp_tw": ("help", "w")},
    "tool_voc": {"VIS": ("list", "h"), "tw": ("list", "w"), "pcol": ("list", "w")},
    "tool_dict": {"VIS": ("list", "h"), "tw": ("list", "w")},
}
# Rows the page has always left empty at the foot of the body at 140 by 43 (they stay empty at every size)
SPARE = {"tool_mygates": 0, "tool_keys": 0, "tool_voc": 0, "tool_dict": 0}
# Worked values at 180 by 55 (body 178 by 51: 40 columns and 12 rows more than the reference): the declared weights, in rectangles
WORKED = {
    "tool_mygates": [(1, 1, 178, 34), (1, 35, 178, 11), (1, 46, 178, 6)],
    "tool_keys": [(1, 1, 59, 12), (1, 13, 59, 39), (61, 1, 59, 17), (61, 18, 59, 34), (121, 1, 58, 10), (121, 11, 58, 14), (121, 25, 58, 27)],
    "tool_voc": [(1, 1, 178, 34), (1, 35, 178, 17)],
    "tool_dict": [(1, 1, 178, 34), (1, 35, 178, 17)],
}


def X(expr, pane, axis, want, var=None, lo=1, hi=None, span=0):
    """One row or column a page draws at or tests the mouse against: the expression as the page writes it, the pane it lies in, its axis (x or y), the literal the page used before at 140 by 43
    (with `var` at `lo`), the name of the loop variable and the expression of its largest value, and the cells the text or box covers after its start less one"""
    return (expr, pane, axis, want, var, lo, hi, span)


EXPRS = {
    "tool_mygates": [X("g.x + 2", "gates", "x", 3), X("g.y + 1", "gates", "y", 2), X("g.y + 1 + r", "gates", "y", 3, "r", 1, "VIS"), X("g.y + g.h - 3", "gates", "y", 20),
                     X("g.y + g.h - 2", "gates", "y", 21), X("g.x + g.w - 5", "gates", "x", 134), X("g.y + 2", "gates", "y", 3), X("g.y + 1 + VIS", "gates", "y", 19), X("g.x + g.w - 3", "gates", "x", 136),
                     X("c.x + 2", "cell", "x", 3), X("c.y + r", "cell", "y", 24, "r", 1, "c.h - 2"), X("s.x + 2", "note", "x", 3), X("s.y + r", "note", "y", 35, "r", 1, "s.h - 2")],
    "tool_keys": [X("t.x + 2", "terminal", "x", 3), X("t.y + i", "terminal", "y", 2, "i", 1, 10), X("k.x + 2", "lastkeys", "x", 3), X("k.y + i", "lastkeys", "y", 14, "i", 1, "LOGN"),
                  X("s.x + 2 + gx * 11", "seen", "x", 49, "gx", 0, 3, 9), X("s.y + 1 + gy", "seen", "y", 2, "gy", 0, 12),
                  X("st.x + 2", "styles", "x", 49), X("st.y + i", "styles", "y", 19, "i", 1, 16), X("st.y + 18", "styles", "y", 36), X("st.y + 19", "styles", "y", 37),
                  X("bx.x + 2", "boxes", "x", 96, None, 1, None, 19), X("bx.y + 2", "boxes", "y", 13, None, 1, None, 9), X("bx.x + 24", "boxes", "x", 118, None, 1, None, 18),
                  X("bx.x + 4", "boxes", "x", 98, None, 1, None, 13), X("bx.y + 8", "boxes", "y", 19, None, 1, None, 3), X("bx.y + 12", "boxes", "y", 23),
                  X("mo.x + 2", "mouse", "x", 96), X("mo.y + 1", "mouse", "y", 2), X("mo.y + 3", "mouse", "y", 4), X("mo.y + 4", "mouse", "y", 5), X("mo.y + 6", "mouse", "y", 7), X("mo.y + 7", "mouse", "y", 8),
                  X("hp.x + 2", "help", "x", 96), X("hp.y + i", "help", "y", 26, "i", 1, 10)],
    "tool_voc": [X("lx + 2", "list", "x", 3), X("ly + 1", "list", "y", 2), X("ly + 1 + r", "list", "y", 3, "r", 1, "VIS"), X("ly + lh - 4", "list", "y", 19), X("ly + lh - 3", "list", "y", 20),
                 X("ly + lh - 2", "list", "y", 21), X("lx + lw - 5", "list", "x", 134), X("lx + lw - 3", "list", "x", 136), X("ly + 2", "list", "y", 3), X("ly + 1 + VIS", "list", "y", 18),
                 X("dx + 2", "detail", "x", 3), X("dy + r", "detail", "y", 24, "r", 1, "dh - 2")],
    "tool_dict": [X("lx + 2", "list", "x", 3), X("ly + 1", "list", "y", 2), X("ly + 1 + r", "list", "y", 3, "r", 1, "VIS"), X("ly + lh - 4", "list", "y", 19), X("ly + lh - 3", "list", "y", 20),
                  X("ly + lh - 2", "list", "y", 21), X("lx + lw - 5", "list", "x", 134), X("lx + lw - 3", "list", "x", 136), X("ly + 2", "list", "y", 3), X("ly + 1 + VIS", "list", "y", 18),
                  X("dx + 2", "detail", "x", 3), X("dy + r", "detail", "y", 24, "r", 1, "dh - 2")],
}
BAD_LITERALS = [r"\b128\b", r"\b134\b", r"\b136\b", r"\b138\b", r"\b139\b", r"\bat [1-9]\d*,", r"for r = 1 to \d+\b", r"TK\.C\.H> - 5", r"'134L'"]


# ---------------------------------------------------------------------------------------------------------------------------------------------------------------- loading
def load_model():
    spec = importlib.util.spec_from_file_location("tklayout_units_for_l2misc", os.path.join(HERE, "test-tklayout-units.py"))
    mod = importlib.util.module_from_spec(spec)
    sys.modules["tklayout_units_for_l2misc"] = mod
    spec.loader.exec_module(mod)
    return mod


def read(path):
    try:
        with open(path, encoding="latin-1") as f:
            return f.read()
    except OSError:
        return ""


def load():
    raw = {n: read(os.path.join(GPL, n)) for n in PAGE_NAMES + ["tool_tktest", "ide"]}
    raw["help.voc"] = read(os.path.join(HELP, "tool.voc.page"))
    raw["help.dict"] = read(os.path.join(HELP, "tool.dict.page"))
    return raw


def strip_bas(src):
    out = []
    for line in src.split("\n"):
        s = line.lstrip()
        if s.startswith("*") or s.startswith("!"):
            out.append("")
            continue
        cut = line.find(";*")
        out.append((line if cut < 0 else line[:cut]).rstrip())
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


def block(text, label):
    """The text of an internal subroutine: from its label to the next label at the start of a line (or to END)."""
    m = re.search(r"^" + re.escape(label) + r":\s*$", text, re.M)
    if not m:
        return ""
    rest = text[m.end():]
    n = re.search(r"^[A-Za-z][A-Za-z0-9.]*:\s*$|^end\s*$", rest, re.M)
    return rest[:n.start()] if n else rest


def py_expr(e):
    """a BASIC arithmetic expression as Python: prefix.x becomes prefix_x"""
    return re.sub(r"\b([A-Za-z]\w*)\.(\w+)\b", r"\1_\2", e)


def parse_decl(code):
    """The declaration of declare.layout as the model takes it (a dict for each pane), or None"""
    body = block(code, "declare.layout")
    panes = []
    for m in re.finditer(r"^\s*d<(\d+)> = (.*)$", body, re.M):
        toks = [t.strip() for t in m.group(2).split(" : @vm : ")]
        vals = []
        for t in toks:
            if t.startswith("'") and t.endswith("'"):
                vals.append(t[1:-1])
            elif re.fullmatch(r"-?\d+", t):
                vals.append(int(t))
            else:
                return None
        vals += [""] * (13 - len(vals))
        keys = ["id", "band", "col", "h", "w", "gap", "vkind", "vwt", "hkind", "hwt", "minh", "minw", "prio"]
        panes.append({k: (None if v == "" else v) for k, v in zip(keys, vals)})
    return panes or None


def get_rects_env(code, decl, rects):
    """The variables get.rects sets, evaluated here from the page's own formulas against the model's rectangles.  A line that is not arithmetic (a header built with FMT, a loop that trims a list) is skipped;
    None when a pane is asked for that was not declared."""
    ids = [a["id"] for a in decl]
    env = {"rtw": RTW}
    cur = None
    for ln in block(code, "get.rects").split("\n"):
        ln = ln.strip()
        if not ln:
            continue
        m = re.match(r"call \$tk_layout\('pane', ctx, '([a-z]+)', rc\)$", ln)
        if m:
            cur = m.group(1)
            continue
        for part in ln.split(" ; "):
            m = re.match(r"([A-Za-z]\w*(?:\.\w+)?) = (.*)$", part.strip())
            if not m:
                continue
            name, expr = m.group(1), m.group(2)
            mm = re.fullmatch(r"rc<1, (\d)>", expr)
            if mm:
                if cur not in ids:
                    return None
                env[name.replace(".", "_")] = rects[ids.index(cur)][int(mm.group(1)) - 1]
                continue
            try:
                env[name.replace(".", "_")] = eval(py_expr(expr), {}, dict(env))
            except Exception:
                pass
    return env


def ev(expr, env, extra=None):
    e = dict(env)
    e.update(extra or {})
    return eval(py_expr(expr), {}, e)


def head_literals(page):
    """the literal boxes of the page as committed (git HEAD), or None when git cannot say"""
    try:
        r = subprocess.run(["git", "-C", os.environ.get("SDREGRESS_REPO") or HERE, "show", "HEAD:sdb_ai/sd64/sdsys/gpl.bp/" + page], capture_output=True, text=True, errors="replace", timeout=30)
    except (OSError, subprocess.SubprocessError):
        return None
    if r.returncode != 0:
        return None
    return [tuple(int(v) for v in m.groups()) for m in re.finditer(r"screen box at (\d+),(\d+) size (\d+),(\d+)", r.stdout)]


def overlaps(a, b):
    return a[0] < b[0] + b[2] and b[0] < a[0] + a[2] and a[1] < b[1] + b[3] and b[1] < a[1] + a[3]


def pane_of(n, pid):
    return [r[0] for r in REF[n]].index(pid)


# The panes that carry the [?] button (the help page of the box), in the order the page draws and tests them; at 140 by 43 the button is at the column and row it always was
MARKS = {"tool_mygates": [("gates", 134, 2)], "tool_keys": [], "tool_voc": [("list", 134, 2)], "tool_dict": [("list", 134, 2)]}


def marks_bad(n, code, ids, rects, env, at140):
    """the [?] mark and the click on it: the page asks $tk_help for the same place in both, the last-but-four column of the box's first row, the old place at 140 by 43"""
    bad = []
    marks = re.findall(r"call \$tk_help\('mark', ([^,]+), ([^,]+), 0, 0\)", code)
    hits = re.findall(r"call \$tk_help\('hit', mev, ([^,]+), ([^,]+), hit\.\w+\)", code)
    want = MARKS[n]
    if len(marks) != len(want) or len(hits) != len(want):
        return ["%s: %d marks and %d clicks, wanted %d of each" % (n, len(marks), len(hits), len(want))]
    for (pid, ox, oy), mk, ht in zip(want, marks, hits):
        rc = rects[ids.index(pid)]
        for kind, (ex, ey) in (("mark", mk), ("click", ht)):
            try:
                gx, gy = ev(ex, env), ev(ey, env)
            except Exception as exc:
                bad.append("%s: the %s of %s cannot be evaluated (%s)" % (n, kind, pid, exc))
                continue
            if (gx, gy) != (rc[0] + rc[2] - 5, rc[1] + 1) or (at140 and (gx, gy) != (ox, oy)):
                bad.append("%s: the %s of %s is at %r, wanted %r" % (n, kind, pid, (gx, gy), (ox, oy) if at140 else (rc[0] + rc[2] - 5, rc[1] + 1)))
    return bad


# ---------------------------------------------------------------------------------------------------------------------------------------------------------------- the checks
def checks(raw, model=None, head=True):
    rows = []

    def ck(i, what, ok, detail=""):
        rows.append((i, what, bool(ok), detail))

    T = model or load_model()
    M = T.Model()
    code = {n: strip_bas(raw[n]) for n in PAGE_NAMES + ["tool_tktest"]}
    sq = {n: squeeze(code[n]) for n in code}
    decl = {n: parse_decl(code[n]) for n in PAGE_NAMES}

    ck("L2-0", "NULL CASE: the model of $tk_layout loaded, the four declaring pages and TKTEST were found, each declaration has the panes the tables expect (3, 7, 2, 2) and the tables know every page",
       hasattr(T, "Model") and all(len(raw[n]) > 6000 for n in PAGE_NAMES) and len(raw["tool_tktest"]) > 6000 and len(raw["ide"]) > 20000
       and all(decl[n] and len(decl[n]) == len(REF[n]) for n in PAGE_NAMES) and [len(REF[n]) for n in PAGE_NAMES] == [3, 7, 2, 2]
       and all(set(RECTVARS[n]) == {r[0] for r in REF[n]} for n in PAGE_NAMES) and all(n in EXPRS and n in CONSTS and n in TIED and n in WORKED and n in SPARE for n in PAGE_NAMES),
       " ".join("%s:%s" % (n, len(decl[n]) if decl[n] else None) for n in PAGE_NAMES))
    if not all(decl[n] for n in PAGE_NAMES):
        return rows

    bad = []
    for n in PAGE_NAMES:
        v = M.validate(decl[n])
        if v is not None:
            bad.append("%s: %r" % (n, v))
    ck("L2-1", "every declaration is accepted by $tk_layout's check (ids, bands, columns, sizes, the reference body 138 by 39)", not bad, "; ".join(bad))

    bad = []
    r140 = {}
    for n in PAGE_NAMES:
        rects, mode = M.layout(decl[n], M.frame(140, 43))
        r140[n] = rects
        want = [r[2] for r in REF[n]]
        got = [tuple(r[:4]) for r in rects]
        ids = [a["id"] for a in decl[n]]
        if got != want or mode != "full" or not all(r[4] for r in rects) or ids != [r[0] for r in REF[n]]:
            bad.append("%s: got %r want %r mode %s ids %r" % (n, got, want, mode, ids))
        sizes = [(a["w"], a["h"]) for a in decl[n]]
        if sizes != [(r[2][2], r[2][3]) for r in REF[n]]:
            bad.append("%s: declared sizes %r are not the boxes" % (n, sizes))
    ck("L2-2", "AT 140 BY 43 EVERY DECLARATION GIVES EXACTLY THE BOXES THE PAGE DREW BEFORE L2 (nothing grows at the reference; every pane shown, mode full), in the same order and with the boxes' own sizes",
       not bad, "; ".join(bad)[:900])

    msgs = []
    done = 0
    if head:
        for n in PAGE_NAMES:
            lit = head_literals(n)
            if lit and any(r[2] in lit for r in REF[n]):          # the committed page still holds the literal boxes: every box of the table must be one of them
                done += 1
                miss = [r[2] for r in REF[n] if r[2] not in lit]
                if miss:
                    msgs.append("%s: HEAD has %r, REF has %r that it does not" % (n, lit, miss))
    ck("L2-2b", "while the committed page still holds the literal boxes (%d of 5 do), every box of the table REF is one of them" % done if head else "(not asked)", not msgs, "; ".join(msgs)[:600])

    bad = []
    env140 = {}
    for n in PAGE_NAMES:
        env = get_rects_env(code[n], decl[n], r140[n])
        if env is None:
            bad.append("%s: get.rects cannot be read" % n)
            continue
        env140[n] = env
        for name, want in CONSTS[n]:
            if env.get(name) != want:
                bad.append("%s: %s is %r, was %r" % (n, name, env.get(name), want))
        for (expr, pid, axis, want, var, lo, hi, span) in EXPRS[n]:
            if expr not in code[n]:
                bad.append("%s: `%s` is not in the page" % (n, expr))
                continue
            try:
                got = ev(expr, env, {var: lo} if var else None)
            except Exception as exc:
                bad.append("%s: `%s` cannot be evaluated (%s)" % (n, expr, exc))
                continue
            if got != want:
                bad.append("%s: `%s` is %r at 140x43, was %r" % (n, expr, got, want))
        bad += marks_bad(n, code[n], [a["id"] for a in decl[n]], r140[n], env, True)
    ck("L2-3", "at 140 by 43 the names the page derives from its rectangles (%s) and every row and column it draws or tests the mouse at are the literals it used before; each expression is looked for in the page and evaluated"
       % ", ".join("%d for %s" % (len(EXPRS[n]), n[5:]) for n in PAGE_NAMES), not bad, "; ".join(bad)[:900])

    bad = []
    for n in PAGE_NAMES:
        if n not in env140:
            continue
        ids = [a["id"] for a in decl[n]]
        for (ww, hh) in SIZES:
            fr = M.frame(ww, hh)
            rects, mode = M.layout(decl[n], fr)
            tag = "%s %dx%d" % (n, ww, hh)
            if mode != "full" or not all(r[4] for r in rects):
                bad.append("%s: mode %s, a pane hidden" % (tag, mode))
                continue
            for a, r0 in zip(rects, r140[n]):
                if a[2] < r0[2] or a[3] < r0[3]:
                    bad.append("%s: %r smaller than %r" % (tag, a, r0))
                if a[0] < fr["XBODY"] or a[1] < fr["YBODY"] or a[0] + a[2] > fr["XBODY"] + fr["BODYW"] or a[1] + a[3] > fr["YBODY"] + fr["BODYH"]:
                    bad.append("%s: %r outside the body" % (tag, a))
            for i in range(len(rects)):
                for j in range(i + 1, len(rects)):
                    if overlaps(rects[i], rects[j]):
                        bad.append("%s: %r overlaps %r" % (tag, rects[i], rects[j]))
            # the bands fill the body: a band's panes (its columns, with their gaps) fill the width, the bands fill the height less the rows the page leaves empty
            bands = {}
            for a, rc in zip(decl[n], rects):
                bands.setdefault(a["band"], []).append((a, rc))
            hsum = 0
            for b, lst in sorted(bands.items()):
                cols = {}
                for a, rc in lst:
                    cols.setdefault(a["col"] or 1, []).append((a, rc))
                used = 0
                bh = 0
                for c, cl in sorted(cols.items()):
                    used += int(cl[0][0]["gap"] or 0) + cl[0][1][2]
                    bh = max(bh, sum(rc[3] for a, rc in cl))
                if used != fr["BODYW"]:
                    bad.append("%s band %s fills %d of %d columns" % (tag, b, used, fr["BODYW"]))
                for c, cl in sorted(cols.items()):
                    if sum(rc[3] for a, rc in cl) != bh:
                        bad.append("%s band %s column %s is %d rows, the band %d" % (tag, b, c, sum(rc[3] for a, rc in cl), bh))
                hsum += bh
            if hsum != fr["BODYH"] - SPARE[n]:
                bad.append("%s: the bands fill %d rows, wanted %d (the body %d less the %d the page leaves empty)" % (tag, hsum, fr["BODYH"] - SPARE[n], fr["BODYH"], SPARE[n]))
            env = get_rects_env(code[n], decl[n], rects)
            if env is None:
                bad.append("%s: get.rects cannot be read" % tag)
                continue
            for (expr, pid, axis, want, var, lo, hi, span) in EXPRS[n]:
                if expr not in code[n]:
                    continue
                rc = rects[ids.index(pid)]
                a0, a1 = (rc[0] + 1, rc[0] + rc[2] - 2) if axis == "x" else (rc[1] + 1, rc[1] + rc[3] - 2)
                vals = [lo] if var else [None]
                if var and hi is not None:
                    vals.append(ev(str(hi), env))
                for v in vals:
                    got = ev(expr, env, {var: v} if var else None)
                    if not (a0 <= got and got + span <= a1):
                        bad.append("%s: `%s`%s is %d (+%d), outside %d..%d of %s" % (tag, expr, (" with %s=%s" % (var, v)) if var else "", got, span, a0, a1, pid))
            bad += ["%s: %s" % (tag, b) for b in marks_bad(n, code[n], ids, rects, env, False)]
            # the lists show more rows when the box is taller, and the text widths follow the boxes: every name tied to a pane is its 140-by-43 value plus what the pane grew by
            for name, (pid, dim) in TIED[n].items():
                k = 3 if dim == "w" else 4
                grew = rects[ids.index(pid)][k - 1] - r140[n][ids.index(pid)][k - 1]
                want = dict(CONSTS[n])[name] + grew
                if env.get(name) != want:
                    bad.append("%s: %s is %r, wanted %d (the %s of %s grew by %d)" % (tag, name, env.get(name), want, dim, pid, grew))
    ck("L2-4", "LARGER (%s): every pane shown, at least its 140-by-43 size, inside the body, no two overlapping; the panes of a band fill the body's width, the bands its height less the rows the page leaves empty; "
       "every row and column a text uses is inside its box for the first and the last row; every row count and text width tied to a box is its 140-by-43 value plus what the box grew by"
       % ", ".join("%dx%d" % s for s in SIZES), not bad, "; ".join(bad)[:1100])

    bad = []
    for n in PAGE_NAMES:
        rects, mode = M.layout(decl[n], M.frame(180, 55))
        got = [tuple(r[:4]) for r in rects]
        if got != WORKED[n]:
            bad.append("%s: %r, wanted %r" % (n, got, WORKED[n]))
    ck("L2-4b", "worked values at 180 by 55 (40 columns, 12 rows more): the holder's gates take the rows in the list, the keys page "
       "gives each of its columns a third of the columns and its three tall boxes the rows, the VOC and dictionary lists take the rows", not bad, "; ".join(bad)[:900])

    bad = []
    for n in PAGE_NAMES:
        gr = block(code[n], "get.rects")
        asked = re.findall(r"call \$tk_layout\('pane', ctx, '([a-z]+)', rc\)", gr)
        ids = [a["id"] for a in decl[n]]
        da = block(code[n], "draw.all")
        if asked != ids:
            bad.append("%s: asks for %r, declares %r" % (n, asked, ids))
        for pid, (vx, vy, vw, vh) in RECTVARS[n].items():
            if not re.search(r"\b%s = rc<1, 1> ; %s = rc<1, 2> ; %s = rc<1, 3> ; %s = rc<1, 4>" % tuple(re.escape(v) for v in (vx, vy, vw, vh)), gr):
                bad.append("%s: %s does not take x y w h from the rectangle" % (n, pid))
            if not re.search(r"screen box at %s,%s size %s,%s title" % tuple(re.escape(v) for v in (vx, vy, vw, vh)), da):
                bad.append("%s: %s is not drawn as a box from its rectangle" % (n, pid))
        if not re.match(r"\s*(lastsz = [^\n]*\n\s*)?screen clear at 0,ctx<TK\.C\.YBODY> size ctx<TK\.C\.W>,ctx<TK\.C\.BODYH>\n", da):
            bad.append("%s: draw.all does not begin by clearing the body" % n)
    ck("L2-5", "the panes each page asks $tk_layout for are the panes it declared, in order, each rectangle is taken whole (x y w h), every pane is drawn as a box from it, and draw.all begins by clearing the body "
       "(the keys page cleared nothing: a resize left the old boxes where they were)", not bad, "; ".join(bad)[:700])

    bad = []
    pre = {"tool_mygates": "call $tk_open('tool.gates', '', ctx, err)", "tool_keys": "call $tk_open('tool.keys', '', ctx, err)",
           "tool_voc": "call $tk_open('tool.voc', '', ctx, err)", "tool_dict": "call $tk_open('tool.dict', '', ctx, err)"}
    for n in PAGE_NAMES:
        c = sq[n]
        first = {"tool_mygates": "gosub read.all", "tool_keys": "gosub draw.all", "tool_voc": "gosub read.all", "tool_dict": "gosub read.files"}[n]
        if n == "tool_mygates":
            pass
        p_open = c.find(pre[n])
        p_decl = c.find("gosub declare.layout", p_open)
        p_first = c.find(first, p_open)
        if not (0 <= p_open < p_decl < p_first):
            bad.append("%s: the layout is not declared between $tk_open and the first %s" % (n, first))
        if c.count("call $tk_layout('declare', ctx, d, perr)") != 1:
            bad.append("%s: declares more or less than once" % n)
    rs = {
        "tool_mygates": ("case nm = 'resize' call $tk_layout('refresh', ctx, '', chg) gosub get.rects gen += 1 ctx<TK.C.GEN> = gen gosub draw.all", ),
        "tool_keys": ("if nm = 'resize' then call $tk_layout('refresh', ctx, '', chg) gosub get.rects gosub redraw.all", ),
        "tool_voc": ("case nm = 'resize' call $tk_layout('refresh', ctx, '', chg) gosub get.rects if ta > ns - VIS then ta = ns - VIS if ta < 0 then ta = 0 gen += 1 ctx<TK.C.GEN> = gen gosub draw.all", ),
        "tool_dict": ("case nm = 'resize' call $tk_layout('refresh', ctx, '', chg) gosub get.rects gen += 1 ctx<TK.C.GEN> = gen gosub draw.all", ),
    }
    for n in PAGE_NAMES:
        if rs[n][0] not in sq[n]:
            bad.append("%s: the resize is not refresh, rectangles, (scroll,) generation, redraw" % n)
    for n, tkp in (("tool_voc", "call $tk_open('tool.voc', '', ctx, err)"), ("tool_dict", "call $tk_open('tool.dict', '', ctx, err)")):
        hv = squeeze(block(code[n], "hand.over"))
        if not ordered(hv, "call $tk_close(ctx)", "execute sent", tkp, "gosub declare.layout", "gen += 1"):
            bad.append("%s: hand.over does not declare the layout again after $tk_open" % n)
    dl = squeeze(block(code["tool_dict"], "draw.list"))
    if "if tp > cn - VIS then tp = cn - VIS" not in dl or not ordered(dl, "if cp > tp + VIS then tp = cp - VIS", "if tp > cn - VIS then tp = cn - VIS", "if tp < 0 then tp = 0"):
        bad.append("tool_dict: a taller list does not fill its rows again")
    gl = squeeze(block(code["tool_mygates"], "draw.list"))
    if not ordered(gl, "if ci > ta + VIS then ta = ci - VIS", "if ta > NG - VIS then ta = NG - VIS", "if ta < 0 then ta = 0"):
        bad.append("tool_mygates: a taller list does not fill its rows again")
    gk = squeeze(block(code["tool_keys"], "get.rects"))
    if not ordered(gk, "LOGN = k.h - 2", "loop while dcount(logl, @fm) > LOGN do", "del logl<LOGN + 1>", "repeat"):
        bad.append("tool_keys: Last keys is not cut to its rows when the window gets smaller")
    ck("L2-6", "the order: declared after $tk_open and before the first read (once); a resize is refresh, the rectangles, the scroll kept inside the list, the generation, the redraw; the pages that hand the terminal "
       "over declare again after $tk_open; a taller list fills its rows again; Last keys is cut to its rows", not bad, "; ".join(bad)[:700])

    bad = []
    for n in PAGE_NAMES + ["tool_tktest"]:
        body = "\n".join(l for l in code[n].split("\n") if not l.lstrip().startswith(("d<", "o<")))     # o<: the declaration with the output pane open (tool_viewers, 30 Oct 26: it holds the reference sizes too)
        if n == "tool_tktest":
            continue
        for pat in BAD_LITERALS:
            m = re.search(pat, body)
            if m:
                bad.append("%s: `%s` is left (line %d)" % (n, m.group(0), body[:m.start()].count("\n") + 1))
    ck("L2-7", "no number that is really the window's is left in the drawing and mouse code of the four pages (no 128, 134, 136, 138 or 139, no `at <number>,`, no `for r = 1 to <number>`, no `ctx<TK.C.H> - 5`, "
       "no '134L'); the declarations hold the reference sizes and nothing else does", not bad, "; ".join(bad)[:700])

    bad = []
    for n, call in list(pre.items()) + [("tool_tktest", "call $tk_open('tktest', aud, ctx, err)")]:
        if call not in sq[n] or "floorw" in sq[n] or sq[n].count("$tk_open(") != (2 if n in ("tool_voc", "tool_dict") else 1):
            bad.append("%s: $tk_open is not called with its four arguments only (%d calls)" % (n, sq[n].count("$tk_open(")))
    ck("L2-8", "the floor each page declares stays 140 by 43: $tk_open is called with its four arguments, no floor (TOOL.VOC and TOOL.DICT call it a second time when the terminal comes back)", not bad, "; ".join(bad))

    # ---- stage C
    bad = []
    vc, dc = code["tool_voc"], code["tool_dict"]
    ev_ = squeeze(block(vc, "do.edit"))
    ed_ = squeeze(block(dc, "do.edit"))
    if not (ordered(ev_, "gosub check.name", "sent = 'ide voc ' : vid", "gosub hand.over") and "type ide voc " in ev_ and not re.search(r"\bsed\b", ev_, re.I)):
        bad.append("tool_voc: E is not `ide voc <id>` after the character check")
    if not (ordered(ed_, "gosub check.word", "gosub check.word", "sent = 'ide dict ' : fn : ' ' : iid", "gosub hand.over") and ed_.count("type ide dict ") == 2 and not re.search(r"\bsed\b", ed_, re.I)):
        bad.append("tool_dict: E is not `ide dict <file> <id>` after both character checks")
    if re.findall(r"\bshow\.allow = '([^']*)'", dc) != ["ide list.index"]:
        bad.append("tool_dict: show.allow is %r" % re.findall(r"\bshow\.allow = '([^']*)'", dc))
    for n in ("tool_voc", "tool_dict"):
        strs = re.findall(r"'[^'\n]*'", code[n])
        sed_s = [s for s in strs if re.search(r"\bSED\b|\bsed\b", s)]
        if sed_s:
            bad.append("%s: a string still names SED: %r" % (n, sed_s[:3]))
        if len(re.findall(r"^\s*execute\b", code[n], re.M)) != 1:
            bad.append("%s: not exactly one execute statement" % n)
    for h in ("help.voc", "help.dict"):
        if re.search(r"\bSED\b", raw[h]):
            bad.append("%s: the help text still names SED" % h)
        if "the IDE" not in raw[h]:
            bad.append("%s: the help text does not name the IDE" % h)
    ide = squeeze(strip_bas(raw["ide"]))
    if not (ordered(ide, "fn0 = field(sent.in, ' ', 2)", "id0 = field(sent.in, ' ', 3)", "if upcase(fn0) = 'DICT' then", "dflag0 = 'DICT'", "fn0 = field(sent.in, ' ', 3)", "id0 = field(sent.in, ' ', 4)")
            and "LAYW = 140" in ide and "LAYH = 43" in ide and "call $sl_need('IDE', LAYW, LAYH, need.msg, '')" in ide):
        bad.append("ide: the start forms `ide dict file id` and `ide voc id`, or its floor 140 by 43, are not what the pages count on")
    ck("L2-9", "STAGE C: TOOL.VOC's E runs `ide voc <id>` and TOOL.DICT's `ide dict <file> <id>` after the same character checks, TOOL.DICT's hand-over list is `ide list.index`, each page has its one execute statement, "
       "no string they show and no help text names SED, and the IDE starts on exactly those forms with a floor (140 by 43, since its window lock; it was 42) no higher than the pages' own (140 by 43)", not bad, "; ".join(bad)[:700])

    # ---- tktest
    tk = sq["tool_tktest"]
    bad = []
    if "declare.layout" in tk or "$tk_layout('declare'" in tk:
        bad.append("tktest declares panes")
    if not ordered(tk, "tgen = 0", "if k = 'resize' then call $tk_layout('refresh', ctx, '', chg) tgen += 1 ctx<TK.C.GEN> = tgen end call $tk_keys('action', keys, k, pane, act, '', '')"):
        bad.append("tktest: a resize is not refresh and a new generation before the key is looked up")
    if "w{'ax'} = 0" not in tk or "w{'ay'} = 1" not in tk or "w{'w'} = 70" not in tk or "w{'h'} = 20" not in tk:
        bad.append("tktest: the table of pane T is not where the library's suite measures it (0,1 size 70,20)")
    ck("L2-10", "TKTEST declares no pane on purpose (its table stands at column 0, its forms at the places sandbox-tk-base.py measures) but a resize is $tk_layout 'refresh' and a new generation of the frame, before the key "
       "is looked up; its table is still at 0,1 size 70,20", not bad, "; ".join(bad))
    return rows


# ---------------------------------------------------------------------------------------------------------------------------------------------------------------- the self-test
def sub(key, old, new):
    def f(raw):
        r = dict(raw)
        if old not in r[key]:
            raise KeyError("%s: %r is not in the file, so the mutant cannot be made" % (key, old[:70]))
        r[key] = r[key].replace(old, new, 1)
        return r
    return f


def model(**kw):
    def f(raw):
        r = dict(raw)
        r["__model"] = kw
        return r
    return f


def mk_checks(raw):
    if "__model" in raw:
        T = load_model()
        saved = T.Model
        kw = raw["__model"]
        try:
            T.Model = lambda: saved(**kw)
            return checks({k: v for k, v in raw.items() if k != "__model"}, model=T, head=False)
        finally:
            T.Model = saved
    return checks(raw, head=False)


MUTANTS = [
    # 9 Nov 26 (S.187): the model mutant and the eleven tool_viewers mutants went with the page (see START-HISTORY); L2-8's mutant is now on tool_keys
    ("keys: a floor is declared", "L2-8", sub("tool_keys", "call $tk_open('tool.keys', '', ctx, err)", "call $tk_open('tool.keys', '', ctx, err, 100, 30)")),
    # tool_mygates
    ("gates: the matrix box is a row short", "L2-2", sub("tool_mygates", "d<1> = 'gates' : @vm : 1 : @vm : 1 : @vm : 22 :", "d<1> = 'gates' : @vm : 1 : @vm : 1 : @vm : 21 :")),
    ("gates: no box grows", "L2-4b", sub("tool_mygates", "d<1> = 'gates' : @vm : 1 : @vm : 1 : @vm : 22 : @vm : 138 : @vm : '' : @vm : 'stretch' : @vm : 1 :", "d<1> = 'gates' : @vm : 1 : @vm : 1 : @vm : 22 : @vm : 138 : @vm : '' : @vm : '' : @vm : '' :")),
    ("gates: the summary line is a row up", "L2-3", sub("tool_mygates", "at g.x + 2,g.y + g.h - 3 attr", "at g.x + 2,g.y + g.h - 4 attr")),
    ("gates: the click tests the old rows", "L2-3", sub("tool_mygates", "if my >= g.y + 2 and my <= g.y + 1 + VIS", "if my >= 3 and my <= 2 + VIS")),
    ("gates: a taller list is not refilled", "L2-6", sub("tool_mygates", "   if ta > NG - VIS then ta = NG - VIS ", "   null ")),
    # tool_keys
    ("keys: Last keys is a row short", "L2-2", sub("tool_keys", "d<2> = 'lastkeys' : @vm : 1 : @vm : 1 : @vm : 27 :", "d<2> = 'lastkeys' : @vm : 1 : @vm : 1 : @vm : 26 :")),
    ("keys: Keys seen starts a column late", "L2-2", sub("tool_keys", "d<3> = 'seen' : @vm : 1 : @vm : 2 : @vm : 17 : @vm : 46 : @vm : 1 :", "d<3> = 'seen' : @vm : 1 : @vm : 2 : @vm : 17 : @vm : 46 : @vm : 2 :")),
    ("keys: Last keys holds a key too many", "L2-3", sub("tool_keys", "LOGN = k.h - 2 ", "LOGN = k.h - 1 ")),
    ("keys: the grid is a column off", "L2-3", sub("tool_keys", "at s.x + 2 + gx * 11,", "at s.x + 3 + gx * 11,")),
    ("keys: a sample box is a column off", "L2-3", sub("tool_keys", "screen box at bx.x + 24,bx.y + 2 size 19,10 title 'x'", "screen box at bx.x + 25,bx.y + 2 size 19,10 title 'x'")),
    ("voc: the [?] is a row down", "L2-3", sub("tool_voc", "call $tk_help('mark', lx + lw - 5, ly + 1, 0, 0)", "call $tk_help('mark', lx + lw - 5, ly + 2, 0, 0)")),
    ("keys: the screen is not cleared first", "L2-5", sub("tool_keys", "   screen clear at 0,ctx<TK.C.YBODY> size ctx<TK.C.W>,ctx<TK.C.BODYH>\n", "")),
    ("keys: a resize does not ask the layout again", "L2-6", sub("tool_keys", "         call $tk_layout('refresh', ctx, '', chg) ", "         null ")),
    ("keys: Last keys is not cut when the window shrinks", "L2-6", sub("tool_keys", "   loop while dcount(logl, @fm) > LOGN do\n      del logl<LOGN + 1>\n   repeat\n", "")),
    ("keys: the mouse text is cut at the old width", "L2-7", sub("tool_keys", "at mo.x + 2,mo.y + 6 width mo.tw", "at mo.x + 2,mo.y + 6 width 134")),
    # tool_voc
    ("voc: the list box is a row short", "L2-2", sub("tool_voc", "d<1> = 'list' : @vm : 1 : @vm : 1 : @vm : 22 :", "d<1> = 'list' : @vm : 1 : @vm : 1 : @vm : 21 :")),
    ("voc: the Points at column does not grow", "L2-4", sub("tool_voc", "pcol = 58 + tw - rtw ", "pcol = 58 ")),
    ("voc: a resize does not keep the scroll inside the list", "L2-6", sub("tool_voc", "            if ta > ns - VIS then ta = ns - VIS\n", "")),
    ("voc: the hand-over does not declare the layout again", "L2-6", sub("tool_voc", "   gosub declare.layout                                         ;* the new context", "   null                                                         ;* the new context")),
    ("voc: E is SED again", "L2-9", sub("tool_voc", "sent = 'ide voc ' : vid", "sent = 'sed voc ' : vid")),
    ("voc: E hands over without the character check", "L2-9", sub("tool_voc", "   gosub check.name\n   if not(okname) then\n      msg = 'this id has a character the page does not give to a command: type  ide voc '", "   okname = 1\n   if not(okname) then\n      msg = 'this id has a character the page does not give to a command: type  ide voc '")),
    ("voc: the hint names SED", "L2-9", sub("tool_voc", "more fields; E shows them all in the IDE)", "more fields; E shows them all in SED)")),
    ("voc: the help text names SED", "L2-9", sub("help.voc", "E edits the entry in the IDE", "E edits the entry in SED")),
    # tool_dict
    ("dict: the detail box is a row short", "L2-2", sub("tool_dict", "d<2> = 'detail' : @vm : 2 : @vm : 1 : @vm : 17 :", "d<2> = 'detail' : @vm : 2 : @vm : 1 : @vm : 16 :")),
    ("dict: the descriptions wrap at the old width", "L2-7", sub("tool_dict", "call $tk_wrap(ct, tw - 6, pieces)", "call $tk_wrap(ct, 128, pieces)")),
    ("dict: the row count is the old 16", "L2-4", sub("tool_dict", "VIS = lh - 6 ", "VIS = 16 ")),
    ("dict: a taller list is not refilled", "L2-6", sub("tool_dict", "   if tp > cn - VIS then tp = cn - VIS ", "   null ")),
    ("dict: E is SED again", "L2-9", sub("tool_dict", "sent = 'ide dict ' : fn : ' ' : iid", "sent = 'sed dict ' : fn : ' ' : iid")),
    ("dict: the hand-over list names SED", "L2-9", sub("tool_dict", "show.allow = 'ide list.index'", "show.allow = 'sed list.index'")),
    ("dict: the hand-over does not declare the layout again", "L2-6", sub("tool_dict", "   gosub declare.layout                                                ;* the new context", "   null                                                                ;* the new context")),
    ("dict: the help text names SED", "L2-9", sub("help.dict", "hands the terminal to the IDE on a new item", "hands the terminal to SED on a new item")),
    # the IDE
    ("ide: the dictionary form is lost", "L2-9", sub("ide", "if upcase(fn0) = 'DICT' then", "if upcase(fn0) = 'DICTS' then")),
    ("ide: the floor rises above the pages'", "L2-9", sub("ide", "LAYH = 43 ", "LAYH = 44 ")),
    # tktest
    ("tktest: a resize is not followed", "L2-10", sub("tool_tktest", "         call $tk_layout('refresh', ctx, '', chg)        ;* the frame", "         null        ;* the frame")),
    ("tktest: the frame is not written again", "L2-10", sub("tool_tktest", "         ctx<TK.C.GEN> = tgen\n", "         null\n")),
    ("tktest: the table moves to the body", "L2-10", sub("tool_tktest", "      w{'ax'} = 0\n", "      w{'ax'} = 1\n")),
    ("tktest: it declares panes", "L2-10", sub("tool_tktest", "   tgen = 0 ", "   call $tk_layout('declare', ctx, d, perr)\n   tgen = 0 ")),
]


def report(rows):
    bad = 0
    for i, what, ok, detail in rows:
        print("  [%s] %s %s%s" % ("PASS" if ok else "FAIL", i, what, "" if ok or not detail else "   <- " + str(detail)[:500]))
        bad += 0 if ok else 1
    return bad


def selftest(raw):
    base = [r[0] for r in mk_checks(raw) if not r[2]]
    if base:
        print("selftest: the unchanged tree fails %s, so a mutant's own failure cannot be told from the tree's; run the plain check first" % base)
        return 1
    holes = 0
    for name, want, mut in MUTANTS:
        try:
            m = mut(raw)
        except KeyError as exc:
            print("  [FAIL] selftest: %s  <- %s" % (name, exc))
            holes += 1
            continue
        failed = sorted({r[0] for r in mk_checks(m) if not r[2]})
        hit = want in failed
        print("  [%s] selftest: %s is caught by %s (failed: %s)" % ("PASS" if hit else "FAIL", name, want, " ".join(failed) or "none"))
        holes += 0 if hit else 1
    print("selftest: %d mutants, %d not caught" % (len(MUTANTS), holes))
    return 1 if holes else 0


def main(argv):
    raw = load()
    print("test-l2-misc-units: tree %s" % SDSYS)
    if not raw["tool_mygates"] or not raw["tool_keys"] or not raw["tool_dict"]:
        print("test-l2-misc-units: CANNOT RUN - gpl.bp/tool_mygates, tool_keys or tool_dict is not there")
        return 2
    rows = checks(raw)
    bad = report(rows)
    print("\ntest-l2-misc-units: %d passed, %d failed" % (len(rows) - bad, bad))
    rc = 1 if bad else 0
    if "--selftest" in argv:
        rc = (selftest(raw) or rc)
    return rc


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
