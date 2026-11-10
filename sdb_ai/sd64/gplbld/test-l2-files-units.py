#!/usr/bin/env python3
"""test-l2-files-units.py - stage L2 of the full-screen plan (S.88) for five toolkit pages: TOOL.FILES, TOOL.CATALOG, TOOL.TEST, TOOL.BULK and TOOL.QUERY (`gpl.bp/tool_files`,
`tool_catalog`, `tool_test`, `tool_bulk`, `tool_query`) laid out by the layout service ($tk_layout), read off the source as text and held against the service's MODEL.  Free: no install,
no sudo, no sd.

    python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/test-l2-files-units.py [--selftest]

WHAT THIS IS, AND WHAT IT IS NOT.  ***IT RUNS NO SD, SO IT CANNOT SAY THAT A PAGE IS DRAWN AT ITS NEW SIZE***: that is `sandbox-l2-files.py` (written, not run when this check was made).  What it holds:

  D   THE DECLARATIONS.  The `d<n> = ...` / `dcl<n> = ...` lines of each page's `declare.layout` are read from the SOURCE, converted to the attributes of tk.h (TK.P.*) and laid out
      by the model of `test-tklayout-units.py` (imported, not copied): valid; AT 140 BY 43 EXACTLY THE BOXES THE PAGE DREW BEFORE L2 (OLD below, copied from the pages at `10380d19`, where
      each box was a literal `screen box at x,y size w,h`); at 180 by 55, 200 by 60 and 233 by 71 the panes tile the body (no two overlap, none outside it, their areas add up to the
      body's) and the panes that stretch have grown, so that the content reaches the last column and the last row of the body.
  A   THE ARITHMETIC.  Every number the pages derived from the box (the rows of a list, the first row of a detail, where the [?] goes, the foot lines, the mouse's rows and columns) is now
      written from the pane's rectangle; each such expression is found in the source and evaluated on the 140 by 43 rectangle, and must give the number the page had before.
  S   THE SOURCE.  No `screen box at <number>`; the panes are declared after $tk_open (and, in tool.files, after the terminal was handed to a verb and the base opened again); the key
      resize calls $tk_layout 'refresh' and takes the rectangles again BEFORE it raises the generation and draws; tool.query declares the build view and the whole-body views separately.

--selftest breaks each in the way an edit plausibly would and requires the named check to notice.

START-HISTORY:
28 Oct 26 dm  New (S.88 L2, the pages tool_files, tool_catalog, tool_test, tool_bulk, tool_query).
3 Nov 26 dm  tool.query's Saved queries view is gone ("Extend the picker": the saved queries are the toolkit's pick window): its seven expressions (SVIS, the header, the rows, the two
             foot lines, the [?], the mouse rows), the svt clamp of S3 and their two mutants are taken out.
END-HISTORY
"""

import importlib.util
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
GPL = os.path.normpath(os.path.join(HERE, "..", "sdsys", "gpl.bp"))
PAGES = ["tool_files", "tool_catalog", "tool_test", "tool_bulk", "tool_query"]


def _load():
    spec = importlib.util.spec_from_file_location("tklayout_units_for_l2", os.path.join(HERE, "test-tklayout-units.py"))
    mod = importlib.util.module_from_spec(spec)
    sys.modules["tklayout_units_for_l2"] = mod
    spec.loader.exec_module(mod)
    return mod


TL = _load()
Model, strip_bas, overlaps = TL.Model, TL.strip_bas, TL.overlaps

# the boxes as the pages drew them before L2 (x, y, w, h), in the order of the declaration; tool.query has two declarations (the build view, then the whole-body views)
OLD = {
    "tool_files": [[(1, 1, 138, 22), (1, 23, 138, 17)]],
    "tool_catalog": [[(1, 1, 138, 22), (1, 23, 138, 17)]],
    "tool_test": [[(1, 1, 138, 22), (1, 23, 138, 17)]],
    "tool_bulk": [[(1, 1, 138, 4), (1, 5, 138, 9), (1, 14, 138, 13), (1, 27, 138, 13)]],
    "tool_query": [[(1, 1, 28, 19), (29, 1, 44, 19), (73, 1, 66, 19), (1, 20, 46, 11), (47, 20, 92, 11), (1, 31, 138, 9)], [(1, 1, 138, 39)]],
}
IDS = {
    "tool_files": [["list", "detail"]], "tool_catalog": [["list", "detail"]], "tool_test": [["list", "detail"]],
    "tool_bulk": [["file", "which", "what", "result"]],
    "tool_query": [["files", "columns", "conds", "sorts", "options", "sentence"], ["whole"]],
}
SIZES = [(180, 55), (200, 60), (233, 71)]
KEYS = ["id", "band", "col", "h", "w", "gap", "vkind", "vwt", "hkind", "hwt", "minh", "minw", "prio"]     # tk.h TK.P.* in order

LIST_DETAIL = [
    ("VIS = lh - 6", "list", lambda x, y, w, h: h - 6, 16),
    ("at lx + 2,ly + lh - 4 attr 'bold' width tw", "list", lambda x, y, w, h: (x + 2, y + h - 4, w - 4), (3, 19, 134)),
    ("at lx + 2,ly + lh - 3 width tw", "list", lambda x, y, w, h: (x + 2, y + h - 3), (3, 20)),
    ("at lx + 2,ly + 1 attr 'header' width tw", "list", lambda x, y, w, h: (x + 2, y + 1, w - 4), (3, 2, 134)),
    ("call $tk_help('mark', lx + lw - 5, ly + 1, 0, 0)", "list", lambda x, y, w, h: (x + w - 5, y + 1), (134, 2)),
    ("mx >= lx + 2 and mx <= lx + lw - 3 and my >= ly + 2 and my <= ly + 1 + VIS", "list", lambda x, y, w, h: (x + 2, x + w - 3, y + 2), (3, 136, 3)),
    ("for r = 1 to dh - 2", "detail", lambda x, y, w, h: h - 2, 15),
    ("at dx + 2,dy + r width tw", "detail", lambda x, y, w, h: (x + 2, y + 1), (3, 24)),
]
ENTRIES = {
    "tool_files": LIST_DETAIL,
    "tool_catalog": LIST_DETAIL,
    "tool_test": LIST_DETAIL + [("VISO = dh - 2", "detail", lambda x, y, w, h: h - 2, 15), ("vlines<kk>[1, tw - 8]", "list", lambda x, y, w, h: w - 4 - 8, 126)],
    "tool_bulk": [
        ("VP = rh - 6", "result", lambda x, y, w, h: h - 6, 7),
        ("call $tk_help('mark', fx + fw - 5, fy + 1, 0, 0)", "file", lambda x, y, w, h: (x + w - 5, y + 1), (134, 2)),
        ("at fx + 2,fy + 1 attr 'bold' width tw - 6", "file", lambda x, y, w, h: (x + 2, y + 1, w - 4 - 6), (3, 2, 128)),
        ("at fx + 2,fy + 2 width tw", "file", lambda x, y, w, h: (x + 2, y + 2), (3, 3)),
        ("at sx + 2,sy + 1 width tw", "which", lambda x, y, w, h: (x + 2, y + 1), (3, 6)),
        ("at sx + 2,sy + 2 attr 'header' width tw", "which", lambda x, y, w, h: (x + 2, y + 2), (3, 7)),
        ("at sx + 2,sy + 2 + yr attr", "which", lambda x, y, w, h: y + 2 + 1, 8),
        ("at sx + 2,sy + sh - 2 attr 'bold' width tw", "which", lambda x, y, w, h: y + h - 2, 12),
        ("at ox + 2,oy + 1 attr 'header' width tw", "what", lambda x, y, w, h: (x + 2, y + 1), (3, 15)),
        ("at ox + 2,oy + 1 + yr attr", "what", lambda x, y, w, h: y + 1 + 1, 16),
        ("at rx + 2,ry + 1 attr 'bold' width tw", "result", lambda x, y, w, h: (x + 2, y + 1), (3, 28)),
        ("at rx + 2,ry + 4 attr 'header' width tw", "result", lambda x, y, w, h: y + 4, 31),
        ("at rx + 2,ry + 4 + yr width tw", "result", lambda x, y, w, h: y + 4 + 1, 32),
        ("my >= sy + 3 and my <= sy + 2 + NCOND", "which", lambda x, y, w, h: (y + 3, y + 2 + 4), (8, 11)),
        ("my >= oy + 2 and my <= oy + 1 + NOPS", "what", lambda x, y, w, h: (y + 2, y + 1 + 10), (16, 25)),
        ("mx >= fx + 2 and mx <= fx + fw - 3", "file", lambda x, y, w, h: (x + 2, x + w - 3), (3, 136)),
    ],
    "tool_query": [
        ("VISF = fb.h - 3", "files", lambda x, y, w, h: h - 3, 16),
        ("VISC = cb.h - 3", "columns", lambda x, y, w, h: h - 3, 16),
        ("at fb.x + 1,fb.y + dr attr ra width fb.w - 2", "files", lambda x, y, w, h: (x + 1, y + 1, w - 2), (2, 2, 26)),
        ("at fb.x + 1,fb.y + fb.h - 2 attr 'bold' width fb.w - 2", "files", lambda x, y, w, h: y + h - 2, 18),
        ("at cb.x + 1,cb.y + 1 attr 'header' width cb.w - 2", "columns", lambda x, y, w, h: (x + 1, y + 1, w - 2), (30, 2, 42)),
        ("at cb.x + 1,cb.y + 1 + dr attr ra width cb.w - 2", "columns", lambda x, y, w, h: y + 1 + 1, 3),
        ("at nb.x + 1,nb.y + 1 attr 'header' width nb.w - 8", "conds", lambda x, y, w, h: (x + 1, y + 1, w - 8), (74, 2, 58)),
        ("at nb.x + 1,nb.y + 1 + dr attr ra width nb.w - 4", "conds", lambda x, y, w, h: (x + 1, y + 1 + 1, w - 4), (74, 3, 62)),
        ("[1, nb.w - 42]", "conds", lambda x, y, w, h: w - 42, 24),
        ("at nb.x + 2,nb.y + 8 + dr width nb.w - 4", "conds", lambda x, y, w, h: (x + 2, y + 8 + 1, w - 4, y + h - 2), (75, 10, 62, 18)),
        ("hx = nb.x + nb.w - 5 ; hy = nb.y + 1", "conds", lambda x, y, w, h: (x + w - 5, y + 1), (134, 2)),
        ("at sb.x + 1,sb.y + 1 attr 'header' width sb.w - 2", "sorts", lambda x, y, w, h: (x + 1, y + 1, w - 2), (2, 21, 44)),
        ("at sb.x + 1,sb.y + 1 + dr attr ra width sb.w - 2", "sorts", lambda x, y, w, h: y + 1 + 1, 22),
        ("at sb.x + 2,sb.y + sb.h - 4 width sb.w - 4", "sorts", lambda x, y, w, h: (x + 2, y + h - 4, w - 4), (3, 27, 42)),
        ("at sb.x + 2,sb.y + sb.h - 2 width sb.w - 4", "sorts", lambda x, y, w, h: y + h - 2, 29),
        ("at ob.x + 1,ob.y + dr attr ra width ob.w - 2", "options", lambda x, y, w, h: (x + 1, y + 1, w - 2), (48, 21, 90)),
        ("at ob.x + 2,ob.y + ob.h - 3 width ob.w - 4", "options", lambda x, y, w, h: (x + 2, y + h - 3, w - 4), (49, 28, 88)),
        ("at ob.x + 2,ob.y + ob.h - 2 width ob.w - 4", "options", lambda x, y, w, h: y + h - 2, 29),
        ("at tb.x + 2,tb.y + dr attr", "sentence", lambda x, y, w, h: (x + 2, y + 1, w - 4), (3, 32, 134)),
        ("at tb.x + 2,tb.y + tb.h - 3 width tw", "sentence", lambda x, y, w, h: y + h - 3, 37),
        ("at tb.x + 2,tb.y + tb.h - 2 attr 'disabled' width tw", "sentence", lambda x, y, w, h: y + h - 2, 38),
        ("call $tk_wrap(sent, tw - 4, pieces)", "sentence", lambda x, y, w, h: w - 4 - 4, 130),
        ("RVIS = wb.h - 6", "whole", lambda x, y, w, h: h - 6, 33),
        ("at wb.x + 2,wb.y + 4 attr 'header' width tw - 6", "whole", lambda x, y, w, h: (x + 2, y + 4, w - 4 - 6), (3, 5, 128)),
        ("at wb.x + 2,wb.y + 4 + dr width tw", "whole", lambda x, y, w, h: y + 4 + 1, 6),
        ("hx = wb.x + wb.w - 7 ; hy = wb.y + 4", "whole", lambda x, y, w, h: (x + w - 7, y + 4), (132, 5)),
        ("mx >= fb.x and mx <= fb.x + fb.w - 1 and my >= fb.y and my <= fb.y + fb.h - 1", "files", lambda x, y, w, h: (x, x + w - 1, y, y + h - 1), (1, 28, 1, 19)),
        ("mx >= cb.x and mx <= cb.x + cb.w - 1 and my >= cb.y and my <= cb.y + cb.h - 1", "columns", lambda x, y, w, h: (x, x + w - 1, y, y + h - 1), (29, 72, 1, 19)),
        ("mx >= nb.x and mx <= nb.x + nb.w - 1 and my >= nb.y and my <= nb.y + nb.h - 1", "conds", lambda x, y, w, h: (x, x + w - 1, y, y + h - 1), (73, 138, 1, 19)),
        ("mx >= sb.x and mx <= sb.x + sb.w - 1 and my >= sb.y and my <= sb.y + sb.h - 1", "sorts", lambda x, y, w, h: (x, x + w - 1, y, y + h - 1), (1, 46, 20, 30)),
        ("mx >= ob.x and mx <= ob.x + ob.w - 1 and my >= ob.y and my <= ob.y + ob.h - 1", "options", lambda x, y, w, h: (x, x + w - 1, y, y + h - 1), (47, 138, 20, 30)),
        ("my >= fb.y + 1 and my <= fb.y + VISF and ft + my - fb.y <= nfs then fc = ft + my - fb.y", "files", lambda x, y, w, h: (y + 1, y + 16), (2, 17)),
        ("my >= cb.y + 2 and my <= cb.y + 1 + VISC", "columns", lambda x, y, w, h: (y + 2, y + 1 + 16), (3, 18)),
        ("my >= nb.y + 2 and my <= nb.y + 1 + MAXCOND", "conds", lambda x, y, w, h: (y + 2, y + 1 + 6), (3, 8)),
        ("my >= sb.y + 2 and my <= sb.y + 1 + MAXSORT", "sorts", lambda x, y, w, h: (y + 2, y + 1 + 4), (22, 25)),
        ("my >= ob.y + 1 and my <= ob.y + 7 then oc = my - ob.y", "options", lambda x, y, w, h: (y + 1, y + 7), (21, 27)),
    ],
}


# ---------------------------------------------------------------------------------------------------------------------------------------------------------------- reading the pages
def load():
    raw = {}
    for p in PAGES:
        try:
            with open(os.path.join(GPL, p), encoding="latin-1") as f:
                raw[p] = f.read()
        except OSError:
            raw[p] = ""
    return raw


def squeeze(t):
    return re.sub(r"\s+", " ", t).strip()


def token(t):
    t = t.strip()
    if t == "''":
        return None
    if len(t) >= 2 and t[0] == t[-1] == "'":
        return t[1:-1]
    return int(t)


def declarations(src):
    """the declarations of a page, read from its source: a list of declarations, each a list of attribute dicts (a new one starts at each `d<1>` / `dcl<1>`)"""
    out = []
    for line in strip_bas(src).split("\n"):
        m = re.match(r"^\s*(?:d|dcl)<(\d+)> = ('(?:[^']*)' : @vm : .+)$", line)
        if not m:
            continue
        toks = [token(t) for t in m.group(2).split(" : @vm : ")]
        a = dict(zip(KEYS, toks + [None] * (len(KEYS) - len(toks))))
        if int(m.group(1)) == 1:
            out.append([])
        out[-1].append(a)
    return out


def rects_at(decl, w, h):
    M = Model()
    r, mode = M.layout(decl, M.frame(w, h))
    return r, mode


def byid(decl, rects):
    return {a["id"]: tuple(r[:4]) for a, r in zip(decl, rects)}


# ---------------------------------------------------------------------------------------------------------------------------------------------------------------- the checks
def checks(raw):
    rows = []

    def ck(i, what, ok, detail=""):
        rows.append((i, what, bool(ok), detail))

    M = Model()
    code = {p: strip_bas(raw[p]) for p in PAGES}
    sq = {p: squeeze(code[p]) for p in PAGES}
    decls = {p: declarations(raw[p]) for p in PAGES}

    ck("D0", "NULL CASE: the five pages were found and declare 1, 1, 1, 1 and 2 layouts of 2, 2, 2, 4 and 6 + 1 panes (the model is test-tklayout-units.py's, the reference body %d by %d)" % M.ref(),
       all(len(raw[p]) > 20000 for p in PAGES) and [len(decls[p]) for p in PAGES] == [1, 1, 1, 1, 2]
       and [[len(d) for d in decls[p]] for p in PAGES] == [[2], [2], [2], [4], [6, 1]], repr({p: [len(d) for d in decls[p]] for p in PAGES}))
    bad = []
    for p in PAGES:
        for k, d in enumerate(decls[p]):
            v = M.validate(d)
            if v is not None:
                bad.append("%s #%d: %r" % (p, k + 1, v))
            if [a["id"] for a in d] != IDS[p][k]:
                bad.append("%s #%d ids %r" % (p, k + 1, [a["id"] for a in d]))
    ck("D1", "every declaration is valid for the service (ids, bands, sizes, fits the reference body) and has the panes the page names", not bad, "; ".join(bad))
    bad = []
    for p in PAGES:
        for k, d in enumerate(decls[p]):
            r, mode = rects_at(d, 140, 43)
            got = [t[:4] for t in r]
            if got != OLD[p][k] or mode != "full" or not all(t[4] for t in r):
                bad.append("%s #%d: got %r want %r" % (p, k + 1, got, OLD[p][k]))
    ck("D2", "AT 140 BY 43 every declaration gives EXACTLY THE BOXES THE PAGE DREW BEFORE L2 (x, y, w, h of each box, the table OLD copied from the pages at 10380d19)", not bad, "; ".join(bad))
    bad = []
    for p in PAGES:
        for k, d in enumerate(decls[p]):
            for (ww, hh) in SIZES:
                fr = M.frame(ww, hh)
                r, mode = M.layout(d, fr)
                if mode != "full" or not all(t[4] for t in r):
                    bad.append("%s #%d %dx%d mode %s" % (p, k + 1, ww, hh, mode))
                    continue
                area = 0
                for i, t in enumerate(r):
                    area += t[2] * t[3]
                    if t[0] < fr["XBODY"] or t[1] < fr["YBODY"] or t[0] + t[2] > fr["XBODY"] + fr["BODYW"] or t[1] + t[3] > fr["YBODY"] + fr["BODYH"]:
                        bad.append("%s #%d %dx%d %r outside the body" % (p, k + 1, ww, hh, t))
                    for j in range(i + 1, len(r)):
                        if overlaps(t, r[j]):
                            bad.append("%s #%d %dx%d %r overlaps %r" % (p, k + 1, ww, hh, t, r[j]))
                if area != fr["BODYW"] * fr["BODYH"]:
                    bad.append("%s #%d %dx%d the panes cover %d cells of the body's %d (a gap)" % (p, k + 1, ww, hh, area, fr["BODYW"] * fr["BODYH"]))
    ck("D3", "at 180x55, 200x60 and 233x71 the panes of every declaration tile the body: inside it, no two overlapping, their areas add up to the body's (no gap)", not bad, "; ".join(bad[:6]))
    bad = []
    for p in PAGES:
        for k, d in enumerate(decls[p]):
            r0, _ = rects_at(d, 140, 43)
            for (ww, hh) in SIZES:
                fr = M.frame(ww, hh)
                r, _ = rects_at(d, ww, hh)
                right = max(t[0] + t[2] for t in r)
                bottom = max(t[1] + t[3] for t in r)
                if right != fr["XBODY"] + fr["BODYW"] or bottom != fr["YBODY"] + fr["BODYH"]:
                    bad.append("%s #%d %dx%d content ends at column %d / row %d, the body at %d / %d" % (p, k + 1, ww, hh, right - 1, bottom - 1, fr["XBODY"] + fr["BODYW"] - 1, fr["YBODY"] + fr["BODYH"] - 1))
                if not any(t[2] > t0[2] for t, t0 in zip(r, r0)):
                    bad.append("%s #%d %dx%d nothing grew in width" % (p, k + 1, ww, hh))
                if not any(t[3] > t0[3] for t, t0 in zip(r, r0)):
                    bad.append("%s #%d %dx%d nothing grew in height" % (p, k + 1, ww, hh))
    ck("D4", "above 140 by 43 the content reaches the last column and the last row of the body and something grows in both directions, on every declaration", not bad, "; ".join(bad[:6]))
    r, _ = rects_at(decls["tool_files"][0], 180, 55)
    q, _ = rects_at(decls["tool_query"][0], 180, 55)
    b, _ = rects_at(decls["tool_bulk"][0], 180, 55)
    ck("D5", "worked values at 180 by 55 (body 178 by 51): tool.files list 1,1 178x34 and detail 1,35 178x17; tool.bulk gives the 12 rows to Result (1,27 178x25); tool.query's build view gives "
             "the 12 rows to the File, Columns and Conditions boxes (19+12 = 31) and the 40 columns to Conditions (106) and Options (132)",
       [t[:4] for t in r] == [(1, 1, 178, 34), (1, 35, 178, 17)] and [t[:4] for t in b] == [(1, 1, 178, 4), (1, 5, 178, 9), (1, 14, 178, 13), (1, 27, 178, 25)]
       and [t[:4] for t in q] == [(1, 1, 28, 31), (29, 1, 44, 31), (73, 1, 106, 31), (1, 32, 46, 11), (47, 32, 132, 11), (1, 43, 178, 9)], repr((r, b, q)))

    # ---- A: the arithmetic
    bad = []
    n = 0
    for p in PAGES:
        d_all = decls[p]
        for (snip, pane, fn, want) in ENTRIES[p]:
            n += 1
            if snip not in code[p]:
                bad.append("%s: %r is not in the page" % (p, snip))
                continue
            pool = None
            for k, d in enumerate(d_all):
                if pane in IDS[p][k]:
                    pool = byid(d, rects_at(d, 140, 43)[0])
                    break
            if pool is None:
                bad.append("%s: no pane %s" % (p, pane))
                continue
            got = fn(*pool[pane])
            if got != want:
                bad.append("%s %r: %r, the page had %r" % (p, snip[:50], got, want))
    ck("A1", "every number the pages derived from a box is now written from the pane's rectangle, found in the source and evaluated on the 140 by 43 rectangle: %d expressions, each gives what the page had before" % n,
       not bad and n >= 78, "; ".join(bad[:6]))           # 85 until 3 Nov 26: tool.query's Saved view (seven) is gone
    bad = []
    for p in PAGES:
        lits = re.findall(r"screen box at \d", code[p])
        nums = re.findall(r"\b(?:134|136|138|139)\b", re.sub(r"(?:d|dcl)<\d+> = .*", "", code[p]))
        if lits or nums:
            bad.append("%s: %r %r" % (p, lits, nums[:4]))
    ck("A2", "no page draws a box at a literal place and none keeps a 134, 136, 138 or 139 outside its declaration (the window's width is the rectangle's, never a number)", not bad, "; ".join(bad))

    # ---- S: the source
    bad = []
    for p in ("tool_files", "tool_catalog", "tool_test", "tool_bulk"):
        s = sq[p]
        res = re.search(r"case nm = 'resize' (.*?) case nm = 'mouse'", s)
        res = res.group(1) if res else ""
        if not (0 <= res.find("call $tk_layout('refresh', ctx, '', chg)") < res.find("gosub get.rects") < res.find("ctx<TK.C.GEN> = gen") < res.find("gosub draw.all")):
            bad.append("%s resize: %s" % (p, res[:160]))
        if not (0 <= s.find("call $tk_open(") < s.find("gosub declare.layout") < s.find("gosub draw.all")):
            bad.append("%s declares before it opens or draws before it declares" % p)
        if "call $tk_layout('declare', ctx, " not in s or "perr" not in s:
            bad.append("%s declare" % p)
    q = sq["tool_query"]
    res = re.search(r"case nm = 'resize' (.*?) case nm = 'mouse'", q)
    res = res.group(1) if res else ""
    if not (0 <= res.find("call $tk_layout('refresh', ctx, '', chg)") < res.find("gosub get.rects") < res.find("gosub clamp.tops") < res.find("ctx<TK.C.GEN> = gen") < res.find("gosub draw.all")):
        bad.append("tool_query resize: %s" % res[:160])
    if not (0 <= q.find("draw.all: gosub sync.layout") and "sync.layout: want.view = (if view = 'build' then 'build' else 'whole') if want.view # lay.view then gosub declare.layout" in q
            and "declare.layout: lay.view = want.view" in q and "if lay.view = 'build' then" in q):
        bad.append("tool_query declares by view")
    ck("S1", "the key resize takes the layout again (REFRESH, then the rectangles, then the generation, then the drawing); each page declares its panes after $tk_open and before the first drawing; "
             "tool.query declares the view it draws (the build view, or the whole-body pane of the Results) from draw.all", not bad, "; ".join(bad))
    f = sq["tool_files"]
    ds = re.search(r"do\.show: (.*?) do\.new:", f)
    ds = ds.group(1) if ds else ""
    ck("S2", "tool.files hands the terminal to a verb and opens the base again: the new context has no panes, so the declaration is made again before the drawing",
       0 <= ds.find("call $tk_open('tool.files'") < ds.find("gosub declare.layout") < ds.find("gosub draw.all"), ds[:200])
    ck("S3", "the lists keep their cursor in view after a resize: the tops of the lists are held to what is listed now (tool.files, tool.catalog, tool.test: ta; tool.test: ot; tool.bulk: ra; tool.query: clamp.tops)",
       all("if ta > ns - VIS then ta = ns - VIS" in sq[p] for p in ("tool_files", "tool_catalog", "tool_test")) and "if ot > nv - VISO then ot = nv - VISO" in sq["tool_test"]
       and "if ra > npv - VP + 1 then ra = npv - VP + 1" in sq["tool_bulk"] and all(s in q for s in ("if ft > nfs - VISF then ft = nfs - VISF", "if ct > nd - VISC then ct = nd - VISC",
                                                                                                  "if rtop > rl.cnt - RVIS then rtop = rl.cnt - RVIS")), "")
    ck("S4", "text longer than its box is wrapped when the box is wider than it was and cut as it always was at the reference width: tool.files, tool.catalog and tool.test wrap the detail lines and the foot note "
             "only when tw > rtw (rtw = TK.MINW - 2 * TK.XBODY - 4) with $tk_wrap; tool.query wraps the sentence and the Results header at the box's width and the Conditions notes (the paragraphs) only when the box is wider than 62",
       all(("dlines = lines if tw > rtw then dlines = ''" in sq[p] and "call $tk_wrap(lines<q>, tw, " in sq[p] and "rtw = TK.MINW - 2 * TK.XBODY - 4" in sq[p]
            and re.search(r"if tw > rtw then call \$tk_wrap\(note, tw, w?pieces\)", sq[p])) for p in ("tool_files", "tool_catalog", "tool_test"))
       and "if nt.w > nt.rw then" in q and "nt.rw = 62" in q and "call $tk_wrap(sent, tw - 4, pieces)" in q and "call $tk_wrap('Ran: ' : rl.sent, tw - 4, pieces)" in q, "")
    paras = ["Enter edits the row: the item, the operator, the value.", "J switches and / or.  D clears the row.",
             "A value is plain text, typed as the query processor reads it for the item (see the query documentation).",
             "like / unlike take a pattern: 0X any text, 1A a letter, 3N three digits.  0X on both sides finds text inside.",
             "The sentence in the box at the foot is what will run.", "A value holds no quote, backslash, backquote or ;"]
    ref = re.findall(r"nt\.ref(?:<\d+>)? = '([^']*)'", code["tool_query"])
    par = re.findall(r"nt\.par(?:<\d+>)? = '([^']*)'", code["tool_query"])
    # the reference lines joined back into paragraphs (the two that were one sentence cut in two) are the paragraphs the box wraps in a wider window
    joined = [ref[0], ref[1], ref[2] + " " + ref[3], ref[4] + " " + ref[5], ref[6], ref[7]] if len(ref) == 8 else []
    ck("S5", "tool.query's Conditions notes: the 8 lines of the reference width joined two and two give exactly the 6 paragraphs that are wrapped in a wider box (no word is lost or added either way)",
       len(ref) == 8 and len(par) == 6 and joined == par == paras and all(len(x) <= 62 for x in ref), repr((len(ref), len(par))))
    ck("S6", "tool.bulk keeps and shows as many changed records as the Result box has rows (at least 20): pvcap = NPREV raised to VP at the dry run, used for the kept previews, the count and the header",
       "pvcap = NPREV" in sq["tool_bulk"] and "if VP > pvcap then pvcap = VP" in sq["tool_bulk"] and "if n.chg <= pvcap then" in sq["tool_bulk"] and "if npv > pvcap then npv = pvcap" in sq["tool_bulk"]
       and "' records that would change)'" in sq["tool_bulk"] and ": pvcap :" in sq["tool_bulk"] and "NPREV :" not in sq["tool_bulk"] and "pvl = pvl[1, tw - 2]" in sq["tool_bulk"], "")
    ck("S7", "no floor is lowered and no message is added: each page opens the base with the arguments it had ($tk_open(name, '', ctx, err) - no floor arguments) and none calls sysmsg() with a new number",
       all(re.search(r"call \$tk_open\('tool\.[a-z]+', '', ctx, err\)", code[p]) for p in PAGES) and not any(re.search(r"sysmsg\(117[3-9]\d\)", code[p]) for p in PAGES), "")
    return rows


# ---------------------------------------------------------------------------------------------------------------------------------------------------------------- the self-test
def sub(page, old, new):
    def f(raw):
        r = dict(raw)
        if old not in r[page]:
            raise KeyError("%s: %r is not in the page, so the mutant cannot be made" % (page, old[:70]))
        r[page] = r[page].replace(old, new, 1)
        return r
    return f


MUTANTS = [
    ("the list box is a row taller", "D2", sub("tool_files", "d<1> = 'list' : @vm : 1 : @vm : 1 : @vm : 22 :", "d<1> = 'list' : @vm : 1 : @vm : 1 : @vm : 23 :")),
    ("the detail box moves a row", "D2", sub("tool_catalog", "d<2> = 'detail' : @vm : 2 : @vm : 1 : @vm : 17 :", "d<2> = 'detail' : @vm : 2 : @vm : 1 : @vm : 16 :")),
    ("the second box of tool.test is declared a column narrower", "D2", sub("tool_test", "d<2> = 'detail' : @vm : 2 : @vm : 1 : @vm : 17 : @vm : 138 :", "d<2> = 'detail' : @vm : 2 : @vm : 1 : @vm : 17 : @vm : 137 :")),
    ("tool.bulk's Result box is declared 14 rows", "D1", sub("tool_bulk", "dcl<4> = 'result' : @vm : 4 : @vm : 1 : @vm : 13 :", "dcl<4> = 'result' : @vm : 4 : @vm : 1 : @vm : 40 :")),
    ("tool.bulk's Which box is declared a row shorter", "D2", sub("tool_bulk", "dcl<2> = 'which' : @vm : 2 : @vm : 1 : @vm : 9 :", "dcl<2> = 'which' : @vm : 2 : @vm : 1 : @vm : 8 :")),
    ("tool.query's Conditions box is declared as wide as the window of 140", "D1", sub("tool_query", "dcl<3> = 'conds' : @vm : 1 : @vm : 3 : @vm : 19 : @vm : 66 :", "dcl<3> = 'conds' : @vm : 1 : @vm : 3 : @vm : 19 : @vm : 120 :")),
    ("tool.query's Sort box starts a column early", "D2", sub("tool_query", "dcl<4> = 'sorts' : @vm : 2 : @vm : 1 : @vm : 11 : @vm : 46 :", "dcl<4> = 'sorts' : @vm : 2 : @vm : 1 : @vm : 11 : @vm : 45 :")),
    ("tool.query's whole-body pane does not stretch in height", "D4", sub("tool_query", "dcl<1> = 'whole' : @vm : 1 : @vm : 1 : @vm : 39 : @vm : 138 : @vm : '' : @vm : 'stretch' : @vm : 1", "dcl<1> = 'whole' : @vm : 1 : @vm : 1 : @vm : 39 : @vm : 138 : @vm : '' : @vm : '' : @vm : ''")),
    ("tool.files' list does not stretch in height", "D4", sub("tool_files", "d<1> = 'list' : @vm : 1 : @vm : 1 : @vm : 22 : @vm : 138 : @vm : '' : @vm : 'stretch' : @vm : 1", "d<1> = 'list' : @vm : 1 : @vm : 1 : @vm : 22 : @vm : 138 : @vm : '' : @vm : '' : @vm : ''")),
    ("tool.bulk's File box does not stretch in width (a gap beside it)", "D3", sub("tool_bulk", "dcl<1> = 'file' : @vm : 1 : @vm : 1 : @vm : 4 : @vm : 138 : @vm : '' : @vm : '' : @vm : '' : @vm : 'stretch' : @vm : 1", "dcl<1> = 'file' : @vm : 1 : @vm : 1 : @vm : 4 : @vm : 138 : @vm : '' : @vm : '' : @vm : '' : @vm : '' : @vm : ''")),
    ("the file rows of tool.files are the list height less 5", "A1", sub("tool_files", "VIS = lh - 6", "VIS = lh - 5")),
    ("the summary line of tool.catalog is a row lower", "A1", sub("tool_catalog", "at lx + 2,ly + lh - 4 attr 'bold' width tw", "at lx + 2,ly + lh - 3 attr 'bold' width tw")),
    ("the [?] of tool.test is a column out", "A1", sub("tool_test", "call $tk_help('mark', lx + lw - 5, ly + 1, 0, 0)", "call $tk_help('mark', lx + lw - 4, ly + 1, 0, 0)")),
    ("the output rows of tool.test are the detail height less 1", "A1", sub("tool_test", "VISO = dh - 2", "VISO = dh - 1")),
    ("the mouse of tool.bulk reads the conditions a row early", "A1", sub("tool_bulk", "my >= sy + 3 and my <= sy + 2 + NCOND", "my >= sy + 2 and my <= sy + 2 + NCOND")),
    ("the preview rows of tool.bulk are the Result height less 5", "A1", sub("tool_bulk", "VP = rh - 6", "VP = rh - 5")),
    ("the Sort notes of tool.query are a row lower", "A1", sub("tool_query", "at sb.x + 2,sb.y + sb.h - 4 width sb.w - 4", "at sb.x + 2,sb.y + sb.h - 3 width sb.w - 4")),
    ("the sentence of tool.query wraps at the box's width", "A1", sub("tool_query", "call $tk_wrap(sent, tw - 4, pieces)", "call $tk_wrap(sent, tw, pieces)")),
    ("a box of tool.files is drawn at a literal place again", "A2", sub("tool_files", "screen box at dx,dy size dw,dh title 'The file under the cursor'", "screen box at 1,23 size dw,dh title 'The file under the cursor'")),
    ("tool.query keeps a 138 outside its declaration", "A2", sub("tool_query", "hx = wb.x + wb.w - 7 ; hy = wb.y + 4", "hx = 132 ; hy = wb.y + 4 ; gw = 138")),
    ("tool.catalog does not take the layout again on a resize", "S1", sub("tool_catalog", "            call $tk_layout('refresh', ctx, '', chg)\n", "")),
    ("tool.bulk draws before it takes the rectangles", "S1", sub("tool_bulk", "            call $tk_layout('refresh', ctx, '', chg)\n            gosub get.rects\n", "            gosub draw.all\n            call $tk_layout('refresh', ctx, '', chg)\n            gosub get.rects\n")),
    ("tool.query declares the view only once", "S1", sub("tool_query", "   if want.view # lay.view then gosub declare.layout", "   if lay.view = '' then gosub declare.layout")),
    ("tool.test declares before it opens the base", "S1", sub("tool_test", "   gosub declare.layout\n", "")),
    ("tool.files forgets its panes after a report", "S2", sub("tool_files", "   gosub declare.layout                                          ;* the new context has no panes\n", "")),
    ("tool.test lets the top of the list pass the end after a resize", "S3", sub("tool_test", "            if ta > ns - VIS then ta = ns - VIS\n", "")),
    ("tool.bulk lets the preview top pass the end", "S3", sub("tool_bulk", "            if ra > npv - VP + 1 then ra = npv - VP + 1\n", "")),
    ("tool.files wraps at the reference width too", "S4", sub("tool_files", "   if tw > rtw then\n      dlines = ''", "   if tw > 0 then\n      dlines = ''")),
    ("tool.query wraps the notes at the reference width", "S4", sub("tool_query", "   if nt.w > nt.rw then", "   if nt.w > 0 then")),
    ("a note of tool.query loses a word", "S5", sub("tool_query", "nt.par<3> = 'A value is plain text, typed as the query processor reads it for the item", "nt.par<3> = 'A value is plain text, typed as the processor reads it for the item")),
    ("tool.bulk keeps 20 previews whatever the box", "S6", sub("tool_bulk", "   if VP > pvcap then pvcap = VP\n", "")),
    ("a floor is declared by tool.test", "S7", sub("tool_test", "call $tk_open('tool.test', '', ctx, err)", "call $tk_open('tool.test', '', ctx, err, 100, 30)")),
]


def report(rows):
    bad = 0
    for i, what, ok, detail in rows:
        print("  [%s] %s %s%s" % ("PASS" if ok else "FAIL", i, what, "" if ok or not detail else "   <- " + str(detail)[:400]))
        bad += 0 if ok else 1
    return bad


def selftest(raw):
    base = [r[0] for r in checks(raw) if not r[2]]
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
        failed = sorted({r[0] for r in checks(m) if not r[2]})
        hit = want in failed
        print("  [%s] selftest: %s is caught by %s (failed: %s)" % ("PASS" if hit else "FAIL", name, want, " ".join(failed) or "none"))
        holes += 0 if hit else 1
    print("selftest: %d mutants, %d not caught" % (len(MUTANTS), holes))
    return 1 if holes else 0


def main(argv):
    raw = load()
    print("test-l2-files-units: tree %s" % GPL)
    if not all(raw[p] for p in PAGES):
        print("test-l2-files-units: CANNOT RUN - a page is not there")
        return 2
    rows = checks(raw)
    bad = report(rows)
    print("\ntest-l2-files-units: %d passed, %d failed" % (len(rows) - bad, bad))
    rc = 1 if bad else 0
    if "--selftest" in argv:
        rc = (selftest(raw) or rc)
    return rc


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
