#!/usr/bin/env python3
"""test-l2-home-units.py - the home screen on the toolkit's layout service (S.88 L2, ~/Documents/Audits/TUI/Opus_TUI_Plan.txt section 12 and 3.1), read off the source as text,
with a MODEL of its geometry.  Free: no install, no sudo, no sd.

    python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/test-l2-home-units.py [--selftest]

WHAT THIS IS, AND WHAT IT IS NOT.  ***IT RUNS NO SD, SO IT CANNOT SAY THAT THE PAGE IS DRAWN WHERE THE MODEL PUTS IT***: that is `sandbox-l2-home.py` (a private SD on a
pseudo-terminal: the page at 140 by 43 compared cell for cell with the page as it was before L2, then at 180 by 55 and 200 by 60, grown and shrunk).  What it holds:

  D   THE DECLARATION.  tool_home's declare.panes, PARSED from the source (the pd<n> lines), is laid out by test-tklayout-units.py's Model (the copy of $tk_layout's equations):
      at 140 by 43 it must give EXACTLY the rectangles the page drew before L2 (tool_home at 10380d19: the header on rows 1 to 3 and a blank row 4, the panel from PANEL.TOP 5 to
      lh - 5 = 38, the hint row at lh - 4 = 39), and at 180 by 55, 200 by 60 and the other sizes the three panes must tile the body - full width, one under another from the body's
      first row to its last, no overlap and no gap - with the hint row on YSTAT - 1 (where $tk_ai draws the AI line).
  G   THE TILE GRID.  A Python copy of the page's `columns`, `band.cols`, `layout` and `place.header` (their constants and margins PARSED from the source) against a copy of the
      layout BEFORE L2 (the fixed X.COL 3 25 49 71 95 117, tiles 21 and 43 wide, header tiles at 95 and 117, Back at 3, the identity at 3 or 25, the header cleared 94 wide): at 140 by
      43 every tile, heading and header tile of the administrator's page, an account holder's, one with programs pinned and one with the Recent group is where it was.  Above it: no
      two tiles overlap, every tile is inside the panel, no further column would fit (the grid reaches across the panel), a group alone in its band spreads over every column, the
      header tiles stand on the last two columns, the header's clear stops before them and the identity is right of the Back tile.  The tile table is PARSED from build.page.
  T   THE TEXT.  What ties the model to the BASIC: no X.COL, PANEL.TOP, `lh - 4`, `size 94,3` or $sl_window is left; the formulas of `columns` and `band.cols` are the model's; the
      resize is $tk_layout 'refresh' and then geometry, set.title, layout, a clear and draw.all; the declaration is made after BOTH $tk_open calls and a refused one is not drawn
      on; $tk_open is still asked for no floor (140 by 43: plan section 12, a page keeps it until its own suite proves less); the hint, the AI line's click and the scroll bar use
      the rectangles.

--selftest breaks each invariant in the way an edit plausibly would (the BASIC, and the model's copy of the OLD page) and requires the named check to notice.

START-HISTORY:
28 Oct 26 dm  New (S.88 L2, the home screen).
END-HISTORY
"""

import importlib.util
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
GPL = os.path.normpath(os.path.join(HERE, "..", "sdsys", "gpl.bp"))


def _load(name, fname):
    spec = importlib.util.spec_from_file_location(name, os.path.join(HERE, fname))
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return mod


TL = _load("test_tklayout_model_for_l2home", "test-tklayout-units.py")         # the model of $tk_layout (Model), strip_bas, label

# THE PAGE BEFORE L2 (tool_home at 10380d19): the literals the declaration and the grid must reproduce at 140 by 43
OLD = dict(xcol=[3, 25, 49, 71, 95, 117], tw=21, wide=43, switch=95, signout=117, back=3, hdy=1, idx=(3, 25), hclear=94, panel_top=5, panel_bot_from_h=5, hint_from_h=4)
REF_RECTS = {"header": (1, 1, 138, 4, 1), "panel": (1, 5, 138, 34, 1), "hint": (1, 39, 138, 1, 1)}
SIZES = [(140, 43), (141, 44), (150, 45), (162, 50), (180, 55), (200, 60), (233, 71), (500, 300)]


# ------------------------------------------------------------------------------------------------------------------------------------------------ reading the source
def load():
    raw = {}
    try:
        with open(os.path.join(GPL, "tool_home"), encoding="latin-1") as f:
            raw["tool_home"] = f.read()
    except OSError:
        raw["tool_home"] = ""
    raw["old"] = dict(OLD)
    return raw


def code(raw):
    return TL.strip_bas(raw["tool_home"])


def block(src, name):
    """the lines of one label of the (comment-stripped) program, up to the next label"""
    m = re.search(r"^%s:\n(.*?)(?=^[a-z][a-z0-9.]*:\s*$)" % re.escape(name), src, re.M | re.S)
    return m.group(1) if m else ""


def declaration(src):
    """the pd<n> lines of declare.panes as $tk_layout attribute dicts, in order"""
    out = []
    names = ["id", "band", "col", "h", "w", "gap", "vkind", "vwt", "hkind", "hwt", "minh", "minw", "prio"]
    for m in re.finditer(r"^\s*pd<(\d+)> = (.*)$", block(src, "declare.panes"), re.M):
        vals = [v.strip() for v in m.group(2).split(": @vm :")]
        vals = [v[1:-1] if len(v) >= 2 and v[0] == v[-1] == "'" else v for v in vals]
        d = dict(zip(names, vals + [""] * (len(names) - len(vals))))
        out.append({k: (None if v == "" else (int(v) if re.fullmatch(r"\d+", v) else v)) for k, v in d.items()})
    return out


def params(src):
    """the grid's constants and margins, as the source has them (None when not found)"""
    def num(pat):
        m = re.search(pat, src, re.M)
        return int(m.group(1)) if m else None
    return dict(TW=num(r"^\$define HT\.TW\s+(\d+)"), GAP=num(r"^\$define HT\.GAP\s+(\d+)"), PGAP=num(r"^\$define HT\.PGAP\s+(\d+)"), BASE=num(r"^\$define HT\.BASECOLS\s+(\d+)"),
                right=num(r"^\s*avail = pnw - (\d+)\s*$"), left=num(r"^\s*xcol<k> = pnx \+ (\d+) \+"))


def table(src):
    """the groups of build.page as the source declares them: (name, band, cols, admin-only, pins-group, [tile sizes])"""
    bp = block(src, "build.page")
    groups = []
    bnd = 0
    admin = pins = False
    for ln in bp.split("\n"):
        s = ln.strip()
        if ln.startswith("   if is.admin then"):
            admin = True
        elif ln.startswith("   if pins.on then"):
            pins = True
        elif ln.rstrip() == "   end":
            admin = pins = False
        if re.match(r"bnd \+= 1\b", s):
            bnd += 1
        m = re.match(r"gr<g> = ('([^']*)'|gname) : @vm : bnd : @vm : (\d+)", s)
        if m:
            groups.append(dict(name=m.group(2) or "Tools", band=bnd, cols=int(m.group(3)), admin=admin, pins=pins, tiles=[]))
            continue
        for t in re.finditer(r"id = ('[^']*'|'pin' : pn) ; grp = (g|0) ;", s):
            if t.group(2) != "g" or not groups:
                continue
            sz = re.search(r"size = '(\w)'", s)
            idv = t.group(1)
            if idv == "'pin' : pn":
                groups[-1]["tiles"].append(("pin", "n", "pinloop"))
            else:
                groups[-1]["tiles"].append((idv.strip("'"), sz.group(1) if sz else "n", ""))
    return groups


def page(groups, is_admin, npins=0, nrecent=0, off=()):
    """the page's gr and tl as the BASIC builds them: groups numbered from 1, tiles (id, group, size); the groups named in `off` keep their place in gr but every tile of theirs
    is off (SET.TILE: home_off leaves the tiles out of tl, not the group out of gr)"""
    gr, tl = [], []
    for g in groups:
        if g["admin"] and not is_admin:
            continue
        if g["pins"] and not (is_admin or npins > 0):   # home_pins: the administrator always has the switch on, so "My programs" and its tile stay with no pins
            continue
        gr.append(dict(name=g["name"], band=g["band"], cols=g["cols"]))
        for tid, size, kind in g["tiles"]:
            if g["name"] in off:
                continue
            if kind == "pinloop":
                for p in range(1, npins + 1):
                    tl.append(dict(id="pin%d" % p, group=len(gr), size="n"))
            else:
                tl.append(dict(id=tid, group=len(gr), size=size))
    if nrecent:
        for t in tl:
            t["group"] += 1
        gr = [dict(name="Recent", band=0, cols=6)] + gr
        tl = [dict(id="r:%d" % i, group=1, size="n") for i in range(nrecent)] + tl
    return gr, tl


# ------------------------------------------------------------------------------------------------------------------------------------------------ the two layouts
def old_layout(gr, tl, old):
    """tool_home's layout BEFORE L2 (10380d19): the fixed X.COL, tiles 21 and 43 wide"""
    X = old["xcol"]
    out = {}
    heads = {}
    nb = max([g["band"] for g in gr] + [0])
    b0 = min([g["band"] for g in gr] + [1])
    ys = 1
    for b in range(b0, nb + 1):
        c0 = 0
        bandend = ys
        for k, g in enumerate(gr, 1):
            n = sum(1 for t in tl if t["group"] == k)
            if g["band"] == b and n > 0:
                heads[k] = (X[c0], ys)
                cc, ry, rowh = 0, ys + 1, 0
                for i, t in enumerate(tl):
                    if t["group"] == k:
                        w = 2 if t["size"] == "w" else 1
                        th = 3 if t["size"] == "s" else 5
                        if cc + w > g["cols"]:
                            cc, ry, rowh = 0, ry + rowh + 1, 0
                        out[i] = (X[c0 + cc], ry, old["wide"] if w == 2 else old["tw"], th)
                        cc += w
                        rowh = max(rowh, th)
                bandend = max(bandend, ry + rowh)
                c0 += g["cols"]
        if c0 > 0:
            ys = bandend + 1
    return out, heads, ys


def columns(pnx, pnw, p):
    """tool_home's `columns`: ncol, the tile width tw.n and xcol (a list, column 1 first)"""
    TW, GAP, PGAP = p["TW"], p["GAP"], p["PGAP"]

    def need(n):
        return n * TW + (n - 1) * GAP + ((n - 1) // 2) * (PGAP - GAP)
    avail = pnw - p["right"]
    ncol = 1
    while need(ncol + 1) <= avail:
        ncol += 1
    tw = TW + (avail - need(ncol)) // ncol
    xcol = [pnx + p["left"] + (k - 1) * (tw + GAP) + ((k - 1) // 2) * (PGAP - GAP) for k in range(1, ncol + 1)]
    return ncol, tw, xcol


def band_cols(gr, gtiles, b, ncol, base):
    """tool_home's `band.cols`: the columns each group of band b is given (by group number); a panel of `base` (HT.BASECOLS) columns or fewer shares nothing out"""
    gcw = {k: g["cols"] for k, g in enumerate(gr, 1)}
    inb = [k for k, g in enumerate(gr, 1) if g["band"] == b and gtiles.get(k, 0) > 0]
    bsum = sum(gr[k - 1]["cols"] for k in inb)
    if bsum < 1:
        return gcw
    if ncol <= base:
        return gcw
    unit = 2 if len(inb) > 1 else 1
    bx = (ncol - bsum) // unit if ncol >= bsum else 0           # (a band wider than the panel: nothing to share; the BASIC's idiv is then 0 or less and it returns)
    if bx < 1:
        return gcw
    given = 0
    for k in inb:
        a = (bx * gr[k - 1]["cols"]) // bsum
        gcw[k] += a * unit
        given += a
    rest = bx - given
    while rest > 0:
        for k in inb:
            if rest > 0:
                gcw[k] += unit
                rest -= 1
    return gcw


def new_layout(gr, tl, ncol, tw, xcol, base):
    """tool_home's `layout` since L2"""
    xcol = list(xcol) + [0] * 64                                     # xcol<k> past the last column is '' (0) in BASIC: such a tile lands on column 0 and fails the rows
    out = {}
    heads = {}
    nb = max([g["band"] for g in gr] + [0])
    b0 = min([g["band"] for g in gr] + [1])
    gtiles = {}
    for t in tl:
        gtiles[t["group"]] = gtiles.get(t["group"], 0) + 1
    ys = 1
    for b in range(b0, nb + 1):
        c0 = 0
        bandend = ys
        gcw = band_cols(gr, gtiles, b, ncol, base)
        for k, g in enumerate(gr, 1):
            if g["band"] == b and gtiles.get(k, 0) > 0:
                gcols = gcw[k]
                heads[k] = (xcol[c0], ys)
                cc, ry, rowh = 0, ys + 1, 0
                for i, t in enumerate(tl):
                    if t["group"] == k:
                        w = 2 if t["size"] == "w" else 1
                        th = 3 if t["size"] == "s" else 5
                        if cc + w > gcols:
                            cc, ry, rowh = 0, ry + rowh + 1, 0
                        x = xcol[c0 + cc]
                        out[i] = (x, ry, (xcol[c0 + cc + 1] + tw - x) if w == 2 else tw, th)
                        cc += w
                        rowh = max(rowh, th)
                bandend = max(bandend, ry + rowh)
                c0 += gcols
        if c0 > 0:
            ys = bandend + 1
    return out, heads, ys


def header(ncol, tw, xcol, hdy):
    """place.header, the identity's column (set.title) and the header's clear width (draw.header)"""
    return dict(switch=(xcol[ncol - 2], hdy, tw, 3), signout=(xcol[ncol - 1], hdy, tw, 3), back=(xcol[0], hdy, tw, 3), idx=(xcol[0], xcol[1]), hclear=xcol[ncol - 2] - 1)


PAGES = [("administrator", True, 0, 0), ("account holder", False, 0, 0), ("holder, 5 programs pinned", False, 5, 0), ("administrator, Recent 4", True, 0, 4), ("holder, pins 2 and Recent 6", False, 2, 6)]


# ------------------------------------------------------------------------------------------------------------------------------------------------ the checks
def checks(raw):
    rows = []

    def ck(i, what, ok, detail=""):
        rows.append((i, what, bool(ok), detail))

    src = code(raw)
    M = TL.Model()
    decl = declaration(src)
    p = params(src)
    groups = table(src)
    old = raw["old"]

    ck("D0", "the source was found and parsed (the null case): three panes declared, the grid's five numbers, and a tile table of at least six groups and twenty tiles",
       len(src) > 20000 and len(decl) == 3 and None not in p.values() and len(groups) >= 6 and sum(len(g["tiles"]) for g in groups) >= 20,
       "%d chars, %d panes, %r, %d groups" % (len(src), len(decl), p, len(groups)))
    if len(decl) != 3 or None in p.values() or not groups:
        return rows

    ids = [d["id"] for d in decl]
    ck("D1", "the declaration passes $tk_layout's own check (the model's copy of check.decl and the fit at 140 by 43)", M.validate(decl) is None and ids == ["header", "panel", "hint"],
       "%r %r" % (M.validate(decl), ids))

    fr = M.frame(140, 43)
    rects, mode = M.layout(decl, fr)
    got = dict(zip(ids, rects))
    ck("D2", "AT 140 BY 43 the panes are EXACTLY the page before L2: header 1,1 138x4 (tiles rows 1-3), panel 1,5 138x34 (PANEL.TOP 5 to lh - 5), hint 1,39 138x1 (lh - 4)",
       got == REF_RECTS and mode == "full" and REF_RECTS["panel"][1] == old["panel_top"] and REF_RECTS["panel"][1] + REF_RECTS["panel"][3] - 1 == 43 - old["panel_bot_from_h"]
       and REF_RECTS["hint"][1] == 43 - old["hint_from_h"], "%r" % got)

    bad = []
    for (W, H) in SIZES:
        fr = M.frame(W, H)
        rs, md = M.layout(decl, fr)
        g = dict(zip(ids, rs))
        y = fr["YBODY"]
        for pid in ids:
            x0, y0, w0, h0, s0 = g[pid]
            if (x0, w0, s0) != (fr["XBODY"], fr["BODYW"], 1) or y0 != y or h0 < REF_RECTS[pid][3]:
                bad.append("%dx%d %s %r" % (W, H, pid, g[pid]))
            y += h0
        if y != fr["YBODY"] + fr["BODYH"]:
            bad.append("%dx%d the panes end on row %d, the body on %d" % (W, H, y, fr["YBODY"] + fr["BODYH"]))
        if g["hint"][1] != fr["YSTAT"] - 1 or g["hint"][3] != 1 or g["header"][3] != 4:
            bad.append("%dx%d hint %r header %r" % (W, H, g["hint"], g["header"]))
    ck("D3", "at every size of %s the three panes tile the body - full width, one under another from its first row to its last, no overlap, no gap - the panel takes every row "
       "beyond the reference, the header stays 4 rows and the hint row is YSTAT - 1 (the AI line's row)" % ", ".join("%dx%d" % s for s in SIZES), not bad, "; ".join(bad[:6]))

    # ---- the tile grid
    ncol, tw, xcol = columns(1, 138, p)
    hd = header(ncol, tw, xcol, 1)
    ck("G1", "AT 140 BY 43 the columns are the old X.COL (3 25 49 71 95 117) and the tiles 21 wide; the header tiles at 95 and 117 (Back at 3) on row 1, the identity at 3 or 25, "
       "the header cleared 94 wide", xcol == old["xcol"] and tw == old["tw"] and (hd["switch"][0], hd["signout"][0], hd["back"][0]) == (old["switch"], old["signout"], old["back"])
       and hd["switch"][2] == old["tw"] and hd["idx"] == old["idx"] and hd["hclear"] == old["hclear"], "ncol %d tw %d xcol %r %r" % (ncol, tw, xcol, hd))

    bad = []
    for name, adm, npins, nrec in PAGES:
        gr, tl = page(groups, adm, npins, nrec)
        o, oh, och = old_layout(gr, tl, old)
        n, nh, nch = new_layout(gr, tl, ncol, tw, xcol, p["BASE"])
        if o != n or oh != nh or och != nch:
            diff = [(tl[i]["id"], o.get(i), n.get(i)) for i in sorted(set(o) | set(n)) if o.get(i) != n.get(i)]
            bad.append("%s: %r heads %r/%r height %d/%d" % (name, diff[:4], oh, nh, och, nch))
    ck("G2", "AT 140 BY 43 every tile, heading and the page's height are where the page before L2 put them, on %s" % "; ".join(n for n, _, _, _ in PAGES), not bad, " | ".join(bad))

    # a group of a band whose tiles are all off (SET.TILE) leaves the band's other groups where they were: the columns it would have had are not shared out at 140 by 43
    bad = []
    nvar = 0
    for name, adm, npins, nrec in PAGES:
        for g0 in page(groups, adm, npins, nrec)[0]:
            if g0["name"] == "Recent" or sum(1 for g1 in page(groups, adm, npins, nrec)[0] if g1["band"] == g0["band"]) < 2:
                continue
            nvar += 1
            gr, tl = page(groups, adm, npins, nrec, off=(g0["name"],))
            o, oh, och = old_layout(gr, tl, old)
            n, nh, nch = new_layout(gr, tl, ncol, tw, xcol, p["BASE"])
            if o != n or oh != nh or och != nch:
                diff = [(tl[i]["id"], o.get(i), n.get(i)) for i in sorted(set(o) | set(n)) if o.get(i) != n.get(i)]
                bad.append("%s, %s off: %r heads %r/%r height %d/%d" % (name, g0["name"], diff[:3], oh, nh, och, nch))
    ck("G2b", "AT 140 BY 43 a group whose tiles are ALL off leaves the other groups of its band where the page before L2 put them (%d pages: every group that has a band-mate, off in turn, on every page of G2)" % nvar,
       nvar >= 3 and not bad, " | ".join(bad) if bad else "%d variants" % nvar)

    bad = []
    for (W, H) in SIZES[1:]:
        fr = M.frame(W, H)
        rs, _ = M.layout(decl, fr)
        g = dict(zip(ids, rs))
        pnx, py0, pnw, ph, _ = g["panel"]
        hx, hy, hw, _, _ = g["header"]
        nc, w, xc = columns(pnx, pnw, p)
        pitch_end = xc[-1] + w - 1
        if pitch_end > pnx + pnw - 1:
            bad.append("%dx%d the last column ends at %d" % (W, H, pitch_end))
        nxt = nc + 1
        need = nxt * p["TW"] + (nxt - 1) * p["GAP"] + ((nxt - 1) // 2) * (p["PGAP"] - p["GAP"])
        if need <= pnw - p["right"]:
            bad.append("%dx%d a %dth column would fit" % (W, H, nxt))
        if (pnx + pnw - 1) - pitch_end >= w + p["PGAP"]:
            bad.append("%dx%d %d columns left empty at the right" % (W, H, (pnx + pnw - 1) - pitch_end))
        if w < p["TW"]:
            bad.append("%dx%d tiles %d wide" % (W, H, w))
        h2 = header(nc, w, xc, hy)
        if h2["signout"][0] + w - 1 > hx + hw - 1 or h2["switch"][0] + w > h2["signout"][0] or h2["hclear"] >= h2["switch"][0] or h2["idx"][1] <= h2["back"][0] + w - 1:
            bad.append("%dx%d header %r" % (W, H, h2))
        for name, adm, npins, nrec in PAGES:
            gr, tl = page(groups, adm, npins, nrec)
            n, nh, nch = new_layout(gr, tl, nc, w, xc, p["BASE"])
            boxes = list(n.values())
            for i, bx in n.items():
                if bx[0] < pnx or bx[0] + bx[2] - 1 > pnx + pnw - 1:
                    bad.append("%dx%d %s: %s outside the panel %r" % (W, H, name, tl[i]["id"], bx))
            for a in range(len(boxes)):
                for b2 in range(a + 1, len(boxes)):
                    if TL.overlaps(boxes[a], boxes[b2]):
                        bad.append("%dx%d %s: two tiles overlap %r %r" % (W, H, name, boxes[a], boxes[b2]))
            # a group alone in its band spreads over every column
            for k, gg in enumerate(gr, 1):
                if sum(1 for g3 in gr if g3["band"] == gg["band"]) == 1:
                    ks = [i for i, t in enumerate(tl) if t["group"] == k]
                    if len(ks) >= nc and max(n[i][0] for i in ks) != xc[-1]:
                        bad.append("%dx%d %s: group %s does not reach the last column" % (W, H, name, gg["name"]))
    ck("G3", "above 140 by 43 (%s) the grid spreads: as many columns as fit and no more, less than a column left empty at the right, tiles at least 21 wide, none outside the panel or over "
       "another, a group alone in its band reaches the last column; the header tiles on the last two columns inside the header, its clear stops before them, the identity right of Back"
       % ", ".join("%dx%d" % s for s in SIZES[1:]), not bad, "; ".join(bad[:6]))

    # ---- the text
    ck("T1", "nothing of the old fixed geometry is left: no X.COL, PANEL.TOP, `lh - 4`, `lh - 5`, `size 94,3`, `hx = 95`, `$sl_window` or a ctx<TK.C.YSTAT/YBORD/YKEYS/W/H> written by the page",
       not re.search(r"X\.COL|PANEL\.TOP|lh - [45]\b|size 94,3|hx = 95|\$sl_window|ctx<TK\.C\.(YSTAT|YBORD|YKEYS|W|H)> =", src), "")
    cb = block(src, "columns")
    ck("T2", "`columns` is the model's: the room is pnw - right, the need of n columns n * HT.TW + (n - 1) * HT.GAP + idiv(n - 1, 2) * (HT.PGAP - HT.GAP), the leftover shared by idiv, "
       "xcol<k> = pnx + left + (k - 1) * (tw.n + HT.GAP) + idiv(k - 1, 2) * (HT.PGAP - HT.GAP)",
       TL.ordered(TL.squeeze(cb), "avail = pnw -", "ncol = 1", "loop", "nx = ncol + 1", "need = nx * HT.TW + (nx - 1) * HT.GAP + idiv(nx - 1, 2) * (HT.PGAP - HT.GAP)",
                  "while need <= avail do", "ncol = nx", "repeat", "used = ncol * HT.TW + (ncol - 1) * HT.GAP + idiv(ncol - 1, 2) * (HT.PGAP - HT.GAP)", "tw.n = HT.TW + idiv(avail - used, ncol)",
                  "for k = 1 to ncol", "xcol<k> = pnx +", "+ (k - 1) * (tw.n + HT.GAP) + idiv(k - 1, 2) * (HT.PGAP - HT.GAP)"), cb[:300])
    bc = TL.squeeze(block(src, "band.cols"))
    ck("T3", "`band.cols` is the model's: a group's HG.COLS, the band's extra columns in pairs when it has more than one group, shared by idiv on HG.COLS, the rest one unit at a time from the first",
       TL.ordered(bc, "gcw<k> = gr<k, HG.COLS>", "bsum += gr<k, HG.COLS>", "nbg += 1", "if bsum < 1 then return", "if ncol <= HT.BASECOLS then return", "unit = 1", "if nbg > 1 then unit = 2", "bx = idiv(ncol - bsum, unit)",
                  "if bx < 1 then return", "gadd = idiv(bx * gr<k, HG.COLS>, bsum)", "gcw<k> = gcw<k> + gadd * unit", "rest = bx - given", "gcw<k> = gcw<k> + unit"), bc[:300])
    ly = TL.squeeze(block(src, "layout"))
    ck("T4", "`layout` places the header first, gives every band its columns (band.cols) and every tile a column of xcol, tw.n wide, a wide one to the end of the next column",
       TL.ordered(ly, "gosub place.header", "for b = b0 to nb", "gosub band.cols", "gcols = gcw<k>", "gr<k, HG.X> = xcol<c0 + 1>", "tl<i, HT.X> = xcol<c0 + cc + 1>", "tl<i, HT.W> = tw.n",
                  "if tw = 2 then tl<i, HT.W> = xcol<c0 + cc + 2> + tw.n - xcol<c0 + cc + 1>"), ly[:300])
    rl = TL.squeeze(block(src, "relayout"))
    ck("T5", "a resize is $tk_layout 'refresh', then a new generation, the AI line MOVED (p3.3a: its text and focus are kept, no init), geometry, set.title, layout, the rows above the status line cleared, and draw.all",
       TL.ordered(rl, "call $tk_layout('refresh', ctx, '',", "gen += 1", "ctx<TK.C.GEN> = gen", "call $tk_ai('move', ctx, '', '')", "gosub geometry", "gosub set.title", "gosub layout",
                  "screen clear at 0,hdy size lw,ctx<TK.C.YSTAT> - hdy", "gosub draw.all") and "case nm = 'resize' gosub relayout" in TL.squeeze(src)
       and "$tk_ai('init'" not in rl and "aif = 0" not in rl, rl[:300])
    sq = TL.squeeze(src)
    ck("T6", "the declaration is made after BOTH $tk_open calls (the start and reopen) and a refused one stops the page before it draws; $tk_open is asked for no floor (140 by 43 stays: plan section 12)",
       sq.count("call $tk_open('home', '', ctx, err)") == 2 and "$tk_open('home', '', ctx, err," not in sq
       and TL.ordered(sq, "call $tk_open('home', '', ctx, err)", "gosub declare.panes", "if perr # '' then call $tk_close(ctx) display perr stop", "gosub geometry", "gosub set.title")
       and TL.ordered(TL.squeeze(block(src, "reopen")), "call $tk_open('home', '', ctx, err)", "gosub declare.panes", "if perr # '' then call $tk_close(ctx) display perr outcome = 'closed' done = 1 return", "gosub geometry"), "")
    gm = TL.squeeze(block(src, "geometry"))
    ck("T7", "geometry reads the three rectangles from the service and works out the columns: py0, ph and py1 from the panel, hdy from the header, hny from the hint row",
       TL.ordered(gm, "lw = ctx<TK.C.W>", "lh = ctx<TK.C.H>", "call $tk_layout('pane', ctx, 'header', prect)", "hdy = prect<1, 2>", "call $tk_layout('pane', ctx, 'panel', prect)", "pnx = prect<1, 1>",
                  "py0 = prect<1, 2>", "pnw = prect<1, 3>", "ph = prect<1, 4>", "py1 = py0 + ph - 1", "call $tk_layout('pane', ctx, 'hint', prect)", "hny = prect<1, 2>", "gosub columns")
       and "call $tk_layout('declare', ctx, pd, perr)" in sq, gm[:300])
    ck("T8", "the hint row, its text, the AI line's click and the scroll bar use the rectangles and the layout's width: at 0,hny; at hnx + 2,hny; my = hny; at lw - 1,py0 + r - 1",
       "screen text '' at 0,hny width lw" in sq and "at hnx + 2,hny attr 'desktop'" in sq and "ctx<TK.C.AI> and my = hny" in sq and "at lw - 1,py0 + r - 1 attr 'scroll'" in sq, "")
    ph_ = TL.squeeze(block(src, "place.header"))
    ck("T9", "the header is the model's: place.header puts Switch account on xcol<ncol - 1>, Sign out on xcol<ncol>, Back on xcol<1>, on the header's row, tw.n wide; draw.header clears up to "
       "xcol<ncol - 1> - 1; set.title puts the identity on xcol<2> on a sub-menu page and xcol<1> otherwise",
       TL.ordered(ph_, "if tl<i, HT.FIXED> then", "case tl<i, HT.ID> = 'switch'", "tl<i, HT.X> = xcol<ncol - 1>", "case tl<i, HT.ID> = 'signout'", "tl<i, HT.X> = xcol<ncol>", "case 1",
                  "tl<i, HT.X> = xcol<1>", "tl<i, HT.Y> = hdy", "tl<i, HT.W> = tw.n")
       and "screen clear at 0,hdy size xcol<ncol - 1> - 1,3" in sq and "idx = (if cur.menu # '' then xcol<2> else xcol<1>)" in sq, ph_[:300])
    return rows


# ------------------------------------------------------------------------------------------------------------------------------------------------ the self-test
def sub(old, new):
    def f(raw):
        r = dict(raw)
        if raw["tool_home"].count(old) != 1:
            raise KeyError("%r is in tool_home %d times, not once" % (old[:70], raw["tool_home"].count(old)))
        r["tool_home"] = raw["tool_home"].replace(old, new, 1)
        return r
    return f


def oldpage(**kw):
    def f(raw):
        r = dict(raw)
        r["old"] = dict(raw["old"], **kw)
        return r
    return f


MUTANTS = [
    ("the panel is declared a row shorter", "D2", sub("pd<2> = 'panel' : @vm : 2 : @vm : 1 : @vm : 34 :", "pd<2> = 'panel' : @vm : 2 : @vm : 1 : @vm : 33 :")),
    ("the header is declared three rows", "D2", sub("pd<1> = 'header' : @vm : 1 : @vm : 1 : @vm : 4 :", "pd<1> = 'header' : @vm : 1 : @vm : 1 : @vm : 3 :")),
    ("the panel does not stretch down", "D3", sub("138 : @vm : '' : @vm : 'stretch' : @vm : 1 : @vm : 'stretch'", "138 : @vm : '' : @vm : '' : @vm : 1 : @vm : 'stretch'")),
    ("the hint row stretches down", "D3", sub("pd<3> = 'hint' : @vm : 3 : @vm : 1 : @vm : 1 : @vm : 138 : @vm : '' : @vm : ''", "pd<3> = 'hint' : @vm : 3 : @vm : 1 : @vm : 1 : @vm : 138 : @vm : '' : @vm : 'stretch'")),
    ("the header does not stretch across", "D3", sub("pd<1> = 'header' : @vm : 1 : @vm : 1 : @vm : 4 : @vm : 138 : @vm : '' : @vm : '' : @vm : '' : @vm : 'stretch'",
                                                      "pd<1> = 'header' : @vm : 1 : @vm : 1 : @vm : 4 : @vm : 138 : @vm : '' : @vm : '' : @vm : '' : @vm : ''")),
    ("the gap between pairs is 2", "G1", sub("$define HT.PGAP    3", "$define HT.PGAP    2")),
    ("the room leaves two columns at the right", "G1", sub("   avail = pnw - 3\n", "   avail = pnw - 4\n")),
    ("the tiles start a column further in", "G1", sub("xcol<k> = pnx + 2 +", "xcol<k> = pnx + 3 +")),
    ("the old page had its pairs elsewhere (the model of the page before L2 is checked too)", "G1", oldpage(xcol=[3, 25, 47, 69, 95, 117])),
    ("the old wide tile was 44", "G2", oldpage(wide=44)),
    ("Switch account stands on the third column from the right", "T9", sub("tl<i, HT.X> = xcol<ncol - 1>", "tl<i, HT.X> = xcol<ncol - 2>")),
    ("a band's groups take single columns", "T3", sub("   if nbg > 1 then unit = 2\n", "")),
    ("band.cols shares columns out at 140 by 43 too (the guard is out)", "T3", sub("   if ncol <= HT.BASECOLS then return\n", "")),
    ("the base column count is five (a sparse band is then given a pair at 140 by 43)", "G2b", sub("$define HT.BASECOLS 6 ", "$define HT.BASECOLS 5 ")),
    ("a wide tile is two tiles wide only", "T4", sub("if tw = 2 then tl<i, HT.W> = xcol<c0 + cc + 2> + tw.n - xcol<c0 + cc + 1>", "if tw = 2 then tl<i, HT.W> = 2 * tw.n")),
    ("the leftover is not shared to the tiles", "T2", sub("tw.n = HT.TW + idiv(avail - used, ncol)", "tw.n = HT.TW")),
    ("the page keeps its own copy of the frame's rules", "T5", sub("   call $tk_layout('refresh', ctx, '', lay.chg)\n", "   call $sl_window(w, h)\n")),
    ("a resize makes the AI line again (the typed request is lost)", "T5", sub("   call $tk_ai('move', ctx, '', '')                       ;* the rows moved", "   call $tk_ai('init', ctx, '', '')                       ;* the rows moved")),
    ("a resize takes the focus off the AI line", "T5", sub("   lastmin = ''\n   call $tk_ai('move', ctx, '', '')", "   lastmin = ''\n   aif = 0\n   call $tk_ai('move', ctx, '', '')")),
    ("a resize does not clear the old header", "T5", sub("   screen clear at 0,hdy size lw,ctx<TK.C.YSTAT> - hdy\n", "")),
    ("a resize leaves the identity where it was", "T5", sub("   gosub set.title                                        ;* the identity's column", "   null                                        ;* the identity's column")),
    ("reopen does not declare the panes", "T6", sub("   call $tk_ai('init', ctx, '', '')                       ;* the account may be another, and the window another size\n   gosub declare.panes\n",
                                                    "   call $tk_ai('init', ctx, '', '')                       ;* the account may be another, and the window another size\n")),
    ("the page lowers its floor", "T6", sub("   call $tk_open('home', '', ctx, err)\n   if err # '' then\n      display err\n      stop", "   call $tk_open('home', '', ctx, err, 100, 30)\n   if err # '' then\n      display err\n      stop")),
    ("the hint row is lh - 4 again", "T1", sub("screen text '' at 0,hny width lw", "screen text '' at 0,lh - 4 width lw")),
    ("a click on the AI line is read at the old row", "T8", sub("ctx<TK.C.AI> and my = hny", "ctx<TK.C.AI> and my = 39")),
    ("the panel's last row is fixed", "T7", sub("   py1 = py0 + ph - 1\n", "   py1 = 38\n")),
    ("the identity stays at column 25 on a sub-menu page", "T9", sub("idx = (if cur.menu # '' then xcol<2> else xcol<1>)", "idx = (if cur.menu # '' then 25 else xcol<1>)")),
    ("the header is cleared to a fixed width", "T9", sub("screen clear at 0,hdy size xcol<ncol - 1> - 1,3", "screen clear at 0,hdy size 94,3")),
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
    print("test-l2-home-units: tree %s" % os.path.dirname(GPL))
    if not raw["tool_home"]:
        print("test-l2-home-units: CANNOT RUN - gpl.bp/tool_home is not there")
        return 2
    rows = checks(raw)
    bad = report(rows)
    print("\ntest-l2-home-units: %d passed, %d failed" % (len(rows) - bad, bad))
    rc = 1 if bad else 0
    if "--selftest" in argv:
        rc = (selftest(raw) or rc)
    return rc


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
