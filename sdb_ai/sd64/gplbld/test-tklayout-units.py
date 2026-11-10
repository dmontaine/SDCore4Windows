#!/usr/bin/env python3
"""test-tklayout-units.py - the toolkit's layout service (S.88 L1, `gpl.bp/tk_layout`) and its wiring, read off the source as text, and a MODEL of its geometry.
Free: no install, no sudo, no sd.

    python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/test-tklayout-units.py [--selftest]

WHAT THIS IS, AND WHAT IT IS NOT.  ***IT RUNS NO SD, SO IT CANNOT SAY THAT A PAGE IS DRAWN AT ITS NEW SIZE, THAT A RESIZE READ BY A DIALOGUE REACHES THE PAGE OR THAT THE LOCK HOLDS THE
KEYBOARD***: that is `sandbox-tk-layout.py` (a private SD, a pseudo-terminal, the disk and the bytes written as the evidence) and, for the pages once they use the service (L2),
`sandbox-tk-resize.py`.  What it holds:

  M   THE MODEL.  A Python copy of $tk_layout's equations (frame, body, bands, columns, panes; growth counted from the 140 by 43 reference; shrink and collapse below it).  For
      EVERY toolkit page that draws literal boxes, a declaration (DECLS below: the declaration each page is to adopt in L2) laid out at 140 by 43 must give EXACTLY the boxes the page
      draws today, read from the page's own source ("screen box at x,y size w,h").  That is the claim "at 140 by 43 the layout is identical", checked against the pages and not
      against a copy of their numbers.  Then a table of window sizes (larger: every pane at least its reference size, inside the body, no two overlapping, the frame rows on the
      last three rows; smaller, for a floor under 140 by 43: compact, the highest priority collapsed first, nothing outside the body).
  T   THE TEXT.  The model and the BASIC are held together by the pieces that carry the equations: the reference body (TK.MINW - 2 * TK.XBODY, TK.MINH - 3 - TK.YBODY), the
      growth from the reference (bw - rbw, bh - rbh, hb - bbh), idiv in the share, the order of the shrink (stretching first, last first), the collapse test (>=, the last of
      equals), the frame rows (H - 3, H - 2, H - 1) and the body (W - 2 * XBODY, YSTAT - YBODY).  The model cannot run the BASIC; on 28 Oct 26 the BASIC was run once by hand
      in a compile sandbox against this model on every declaration and size here and agreed on every rectangle (the record of L1).
  W   THE WIRING.  tk.h's new slots are at the END (no slot before 12 moved; no program indexes ctx by a literal number); $tk_open is VAR.ARGS with the floor, reads it only after
      UNASSIGNED(), asks $sl_need for the floor, and calls $tk_layout 'open' after the screen is taken; $tk_layout arms $sl_guardmode in the layout mode with the floor; $sl_key's
      layout mode asks the window, not the cursor, and gives $sl_guard the floor's last cell; the three-argument cursor mode is left as it was; $sl_key notes every resize it hands
      out, $sl_scr 'pending' reads and clears the note, SCREEN KEY and SCREEN WAIT ask it before they read a key and clear it when they deliver one; the frame-cache epoch is set by
      $tk_open, compared by $tk_frame (with the geometry) and cleared by $tk_close.

--selftest breaks each invariant (the BASIC, a header, a message, and the MODEL's own equations) in the way an edit plausibly would and requires the named check to notice; a mutant
that nothing catches is a failure of the self-test.

START-HISTORY:
28 Oct 26 dm  New (S.88 L1).
1 Nov 26 dm   T6 follows S.97 stage 1 (1c8b6b4c), which let the mode stay full when the only row the body lacks is the AI line's (tk_layout:261); the check
              still wanted the line before it and failed on every tree since.  A mutant holds the allowance to the AI row only.  And the "a page's box
              moves a row" mutant changes the page's source before L2, which M2 compares with (it changed the working copy, which has no literal boxes since
              L2, and raised a KeyError on every self-test).
2 Nov 26 dm   S.88 U4: mymenu's one pane (list, 1,34, stretching) in DECLS, compared by M2 with the pre-L2 box.
9 Nov 26 (S.187): tool_viewers (the Bypass programs page) left DECLS with the pdf verb (owner: pdf only works at the machine's own display); 20 declarations remain,
              M2's floor.  The model mutant's note names tool.menus alone as the page that leaves rows empty.
END-HISTORY
"""

import copy
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SDSYS = os.path.normpath(os.path.join(HERE, "..", "sdsys"))
GPL = os.path.join(SDSYS, "gpl.bp")
MSG = os.path.join(SDSYS, "messages")
PROGS = ["tk.h", "tk_layout", "tk_open", "tk_close", "tk_frame", "sl_guardmode", "sl_guard", "sl_key", "sl_msgbox", "sl_scr", "screen_key", "sl_form", "screen_close", "sl_cleanup", "ide", "ced_edit", "debug"]
MESSAGES = [12545, 12546, 12547, 12605, 12730, 12731]


# ---------------------------------------------------------------------------------------------------------------------------------------------------------------- the model
class Model:
    """$tk_layout's equations.  Every method is a copy of the BASIC gosub of the same name; change both or neither."""

    def __init__(self, minw=140, minh=43, maxw=500, maxh=300, xbody=1, ybody=1, growth_from_reference=True, collapse_last_of_equals=True, stretch_first=True):
        self.minw, self.minh, self.maxw, self.maxh, self.xb, self.yb = minw, minh, maxw, maxh, xbody, ybody
        self.growth_from_reference = growth_from_reference              # (mutants of the model turn these off)
        self.collapse_last_of_equals = collapse_last_of_equals
        self.stretch_first = stretch_first

    def ref(self):
        return self.minw - 2 * self.xb, self.minh - 3 - self.yb

    def frame(self, winw, winh, floorw=None, floorh=None):
        fw = floorw or self.minw
        fh = floorh or self.minh
        lw = max(winw, fw)
        lh = max(winh, fh)
        lw = min(lw, self.maxw)
        lh = min(lh, self.maxh)
        return dict(W=lw, H=lh, YMENU=0, YSTAT=lh - 3, YBORD=lh - 2, YKEYS=lh - 1, XBODY=self.xb, YBODY=self.yb, BODYW=lw - 2 * self.xb, BODYH=lh - 3 - self.yb)

    @staticmethod
    def share(amount, wts):
        out = [0] * len(wts)
        tot = sum(wts)
        if amount <= 0 or tot <= 0:
            return out
        for k, w in enumerate(wts):
            out[k] = (amount * w) // tot
        rem = amount - sum(out)
        k = 0
        while rem > 0:
            if wts[k] > 0:
                out[k] += 1
                rem -= 1
            k = (k + 1) % len(wts)
        return out

    def shrink(self, size, mins, wts, d):
        size = list(size)
        passes = (1, 2) if self.stretch_first else (2, 1)
        for p in passes:
            k = len(size) - 1
            while k >= 0 and d > 0:
                st = wts[k] > 0
                if (p == 1 and st) or (p == 2 and not st):
                    take = min(size[k] - mins[k], d)
                    if take > 0:
                        size[k] -= take
                        d -= take
                k -= 1
        return size, d

    @staticmethod
    def normalise(decl):
        P = []
        for a in decl:
            vs = (a.get("vwt") or 1) if a.get("vkind") == "stretch" else 0
            hs = (a.get("hwt") or 1) if a.get("hkind") == "stretch" else 0
            P.append(dict(id=a["id"], band=int(a["band"]), col=int(a.get("col") or 1), h=int(a["h"]), w=int(a["w"]), gap=int(a.get("gap") or 0), vs=vs, hs=hs,
                          mh=int(a.get("minh") or a["h"]), mw=int(a.get("minw") or a["w"]), pr=int(a.get("prio") or 0)))
        return P

    @staticmethod
    def structure(P, shown):
        bl = sorted({p["band"] for i, p in enumerate(P) if shown[i]})
        cols, cells = [], []
        for b in bl:
            cl = sorted({p["col"] for i, p in enumerate(P) if shown[i] and p["band"] == b})
            cols.append(cl)
            cells.append([[i for i, p in enumerate(P) if shown[i] and p["band"] == b and p["col"] == c] for c in cl])
        C, B = [], []
        for bi in range(len(bl)):
            row = []
            bh = bm = bv = 0
            for cc in cells[bi]:
                c = dict(w=max(P[i]["w"] for i in cc), mw=max(P[i]["mw"] for i in cc), gap=P[cc[0]]["gap"], hs=max(P[i]["hs"] for i in cc),
                         h=sum(P[i]["h"] for i in cc), mh=sum(P[i]["mh"] for i in cc))
                bv = max([bv] + [P[i]["vs"] for i in cc])
                bh = max(bh, c["h"])
                bm = max(bm, c["mh"])
                row.append(c)
            C.append(row)
            B.append(dict(h=bh, mh=bm, vs=bv))
        return bl, cols, cells, C, B

    def validate(self, decl):
        """None, or (pane number from 1, why) - the words of $tk_layout's check.decl; ('fit', ...) for message 12547"""
        if not decl:
            return (0, "no pane")
        ids = []

        def intok(v, lo, nullok):
            if v is None or v == "":
                return nullok
            try:
                f = float(v)
            except (TypeError, ValueError):
                return False
            return f == int(f) and f >= lo

        for n, a in enumerate(decl, 1):
            pid = a.get("id") or ""
            why = None
            if pid == "" or any(c in pid for c in " \x1c\x1b"):
                why = "id"
            elif pid in ids:
                why = "id twice"
            for key, lo, nullok, word in (("band", 1, False, "band"), ("col", 1, True, "column"), ("h", 1, False, "height"), ("w", 1, False, "width"), ("gap", 0, True, "gap"),
                                          ("vwt", 1, True, "vertical weight"), ("hwt", 1, True, "horizontal weight"), ("minh", 1, True, "least height"), ("minw", 1, True, "least width"),
                                          ("prio", 0, True, "priority")):
                if why is None and not intok(a.get(key), lo, nullok):
                    why = word
            if why is None and a.get("vkind") not in (None, "", "fixed", "stretch"):
                why = "vertical kind"
            if why is None and a.get("hkind") not in (None, "", "fixed", "stretch"):
                why = "horizontal kind"
            if why is None and a.get("minh") not in (None, "") and int(a["minh"]) > int(a["h"]):
                why = "least height"
            if why is None and a.get("minw") not in (None, "") and int(a["minw"]) > int(a["w"]):
                why = "least width"
            if why:
                return (n, why)
            ids.append(pid)
        P = self.normalise(decl)
        rbw, rbh = self.ref()
        bl, cols, cells, C, B = self.structure(P, [1] * len(P))
        for row in C:
            if sum(c["gap"] + c["w"] for c in row) > rbw:
                return ("fit", "")
        if sum(b["h"] for b in B) > rbh:
            return ("fit", "")
        return None

    def layout(self, decl, fr):
        """rects (x, y, w, h, shown) in the order declared, and the mode"""
        bw, bh, xb, yb = fr["BODYW"], fr["BODYH"], fr["XBODY"], fr["YBODY"]
        rbw, rbh = self.ref()
        mode = "full" if (bw >= rbw and bh >= rbh) else "compact"
        P = self.normalise(decl)
        n = len(P)
        if n == 0:
            return [], mode
        shown = [1] * n
        while True:
            bl, cols, cells, C, B = self.structure(P, shown)
            # fit.width
            hfail, cws = [], []
            for bi, row in enumerate(C):
                need = sum(c["gap"] + c["w"] for c in row)
                szs = [c["w"] for c in row]
                if need > bw:
                    szs, d = self.shrink(szs, [c["mw"] for c in row], [c["hs"] for c in row], need - bw)
                    if d > 0:
                        hfail.append(bl[bi])
                else:
                    g = (bw - rbw) if self.growth_from_reference else (bw - need)
                    sh = self.share(g, [c["hs"] for c in row])
                    szs = [s + a for s, a in zip(szs, sh)]
                cws.append(szs)
            # fit.height
            vfail = False
            need = sum(b["h"] for b in B)
            bhs = [b["h"] for b in B]
            if need > bh:
                bhs, d = self.shrink(bhs, [b["mh"] for b in B], [b["vs"] for b in B], need - bh)
                if d > 0:
                    vfail = True
            else:
                g = (bh - rbh) if self.growth_from_reference else (bh - need)
                sh = self.share(g, [b["vs"] for b in B])
                bhs = [s + a for s, a in zip(bhs, sh)]
            best = 0
            if hfail or vfail:
                bestp = 0
                for i in range(n):
                    if shown[i] and P[i]["pr"] > 0 and (vfail or P[i]["band"] in hfail):
                        if (P[i]["pr"] >= bestp) if self.collapse_last_of_equals else (P[i]["pr"] > bestp):
                            best, bestp = i + 1, P[i]["pr"]
                if best:
                    shown[best - 1] = 0
            if not best:
                break
        rects = [(0, 0, 0, 0, 0)] * n
        y = yb
        for bi in range(len(bl)):
            hb = bhs[bi]
            x = xb
            for ci, cc in enumerate(cells[bi]):
                x += C[bi][ci]["gap"]
                wcol = cws[bi][ci]
                ch = [P[i]["h"] for i in cc]
                cwt = [P[i]["vs"] for i in cc]
                cmn = [P[i]["mh"] for i in cc]
                if hb >= B[bi]["h"]:
                    g = (hb - B[bi]["h"]) if self.growth_from_reference else (hb - C[bi][ci]["h"])
                    ch = [s + a for s, a in zip(ch, self.share(g, cwt))]
                elif C[bi][ci]["h"] > hb:
                    ch, _ = self.shrink(ch, cmn, cwt, C[bi][ci]["h"] - hb)
                cy = y
                for k, i in enumerate(cc):
                    rx, ry, rw, rh = x, cy, wcol, ch[k]
                    cy += rh
                    if rx + rw > xb + bw:
                        rw = xb + bw - rx
                    if ry + rh > y + hb:
                        rh = y + hb - ry
                    if ry + rh > yb + bh:
                        rh = yb + bh - ry
                    rw, rh = max(rw, 0), max(rh, 0)
                    rects[i] = (rx, ry, rw, rh, 1 if (rw >= 1 and rh >= 1) else 0)
                x += wcol
            y += hb
        return rects, mode


# ---------------------------------------------------------------------------------------------------------------------------------------------------------------- the declarations
def P(pid, band, h, w=138, col=None, gap=None, v=False, hz=True, vwt=None, hwt=None, minh=None, minw=None, prio=None):
    return dict(id=pid, band=band, col=col, h=h, w=w, gap=gap, vkind="stretch" if v else None, vwt=vwt, hkind="stretch" if hz else None, hwt=hwt, minh=minh, minw=minw, prio=prio)


LIST_DETAIL = [P("list", 1, 22, v=True), P("detail", 2, 17)]
TOP_LIST_DETAIL = [P("top", 1, 6), P("list", 2, 20, v=True), P("detail", 3, 13)]
# What each page is to declare in L2 (the stretch choices are L2's to confirm: at 140 by 43 nothing stretches, so they cannot change a box there).  The source and, for a page
# with more than one view, which of its literal boxes (in the order they appear) the declaration is for.
DECLS = {
    "tool_files": (LIST_DETAIL, None), "tool_voc": (LIST_DETAIL, None), "tool_dict": (LIST_DETAIL, None), "tool_catalog": (LIST_DETAIL, None), "tool_test": (LIST_DETAIL, [0, 1]),
    "tool_accounts": (TOP_LIST_DETAIL, None), "tool_audit": (TOP_LIST_DETAIL, None), "tool_backups": (TOP_LIST_DETAIL, None), "tool_config": (TOP_LIST_DETAIL, None),
    "tool_remote": (TOP_LIST_DETAIL, None),
    "tool_gates": ([P("matrix", 1, 19, v=True), P("cell", 2, 11), P("reach", 3, 9, w=68, col=1, hwt=1), P("sessions", 3, 9, w=69, col=2, gap=1, hwt=1)], None),
    "tool_sessions": ([P("sessions", 1, 15, v=True), P("locks", 2, 14, v=True), P("row", 3, 10)], None),
    "tool_bulk": ([P("file", 1, 4), P("which", 2, 9), P("what", 3, 13), P("result", 4, 13, v=True)], None),
    "tool_ai": ([P("choice", 1, 9), P("models", 2, 13, v=True), P("key", 3, 10), P("note", 4, 6)], None),
    "tool_mygates": ([P("gates", 1, 21, v=True), P("cell", 2, 12), P("note", 3, 6)], None),
    "mymenu": ([P("list", 1, 34, v=True)], None),                    # 2 Nov 26, S.88 U4: MY.MENU's one box
    "tool_query": ([P("files", 1, 19, w=28, col=1, v=True, hz=False), P("fields", 1, 19, w=44, col=2, v=True, hz=False), P("sentence", 1, 19, w=66, col=3, v=True),
                    P("options", 2, 11, w=46, col=1, hz=False), P("preview", 2, 11, w=92, col=2), P("result", 3, 9)], [0, 1, 2, 3, 4, 5]),
    "tool_query#whole": ([P("whole", 1, 39, v=True)], [6]),
    "tool_keys": ([P("last", 1, 12, w=45, col=1, hz=False), P("names", 1, 27, w=45, col=1, v=True, hz=False),
                   P("codes", 1, 17, w=46, col=2, gap=1), P("raw", 1, 22, w=46, col=2, gap=1, v=True),
                   P("bound", 1, 10, w=45, col=3, gap=1, hz=False), P("table", 1, 14, w=45, col=3, gap=1, hz=False), P("help", 1, 15, w=45, col=3, gap=1, v=True, hz=False)],
                  [0, 1, 2, 6, 3, 4, 5]),
    "tool_menus": ([P("menus", 1, 30, w=70, col=1, v=True), P("hint", 1, 5, w=70, col=1), P("keys", 1, 3, w=70, col=1),
                    P("items", 1, 21, w=67, col=2, gap=1, v=True), P("detail", 1, 17, w=67, col=2, gap=1)], [0, 3, 4, 1, 2]),
}                                                                    # 9 Nov 26 (S.187): tool_viewers' declaration went with the page (the pdf verb is removed)


def page_boxes(src):
    """the page's literal boxes, in the order they appear: (x, y, w, h)"""
    return [tuple(int(v) for v in m.groups()) for m in re.finditer(r"screen box at (\d+),(\d+) size (\d+),(\d+)", src)]


# 28 Oct 26 (stage L2): a page that has moved onto the layout service no longer holds its boxes as literals.  The boxes it had at 140 by 43 are the ones of the commit that
# preceded L2 (10380d19, "stages L1 and B"); M2 reads them from there, so it keeps comparing every declaration with what the pages drew before the move.
PRE_L2 = "10380d19"


def pre_l2_source(page, working):
    """the page's source with its literal boxes: the working copy while it still has them, else the one of the commit before L2 (git show)"""
    if page_boxes(working):
        return working
    import subprocess
    try:
        # 29 Oct 26: regress.sh --snapshot runs this in a copy that has no .git and exports SDREGRESS_REPO (the live repository); stage 2 of the complete run died here with an IndexError
        repo = os.environ.get("SDREGRESS_REPO") or os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
        out = subprocess.run(["git", "-C", repo, "show",
                              "%s:sdb_ai/sd64/sdsys/gpl.bp/%s" % (PRE_L2, page)], capture_output=True, timeout=60)
        return out.stdout.decode("latin-1") if out.returncode == 0 else working
    except (OSError, subprocess.SubprocessError):
        return working


# ---------------------------------------------------------------------------------------------------------------------------------------------------------------- the checks
def load():
    raw = {}
    for n in PROGS:
        try:
            with open(os.path.join(GPL, n), encoding="latin-1") as f:
                raw[n] = f.read()
        except OSError:
            raw[n] = ""
    for n in MESSAGES:
        try:
            with open(os.path.join(MSG, str(n)), encoding="latin-1") as f:
                raw["m%d" % n] = f.read()
        except OSError:
            raw["m%d" % n] = ""
    pages = {}
    for f in sorted(os.listdir(GPL)):
        if f.startswith("tool_") or f.startswith("tk_") or f in ("ide", "mymenu", "ced_edit", "debug", "sed"):
            with open(os.path.join(GPL, f), encoding="latin-1") as fh:
                pages[f] = fh.read()
    raw["pages"] = pages
    raw["model"] = Model()
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


def defines(h):
    return {m.group(1): m.group(2) for m in re.finditer(r"^\$define\s+(\S+)\s+(\S+)", h, re.M)}


def label(src, name):
    """the text of one gosub label of a squeezed program, up to the next label"""
    m = re.search(r"(?:^|\s)%s: (.*?)(?= [a-z][a-z0-9.]*: |$)" % re.escape(name), src)
    return m.group(1) if m else ""


def overlaps(a, b):
    return a[0] < b[0] + b[2] and b[0] < a[0] + a[2] and a[1] < b[1] + b[3] and b[1] < a[1] + a[3]


SIZES = [(140, 43), (141, 44), (150, 45), (180, 55), (200, 60), (233, 71), (500, 300), (600, 400)]
SMALL = [(100, 30), (120, 36), (139, 42)]


def checks(raw):
    rows = []

    def ck(i, what, ok, detail=""):
        rows.append((i, what, bool(ok), detail))

    M = raw["model"]
    th = raw["tk.h"]
    D = defines(th)
    code = {n: squeeze(strip_bas(raw[n])) for n in PROGS if n != "tk.h"}
    lay, op, cl, fr, gm, gd, ky, sc, sk, fm = (code[n] for n in ("tk_layout", "tk_open", "tk_close", "tk_frame", "sl_guardmode", "sl_guard", "sl_key", "sl_scr", "screen_key", "sl_form"))

    ck("L0", "NULL CASE: tk.h, $tk_layout, $tk_open, $tk_close, $tk_frame, the guard, the key reader, $sl_scr, SCREEN KEY, the form, messages 12545-12547 and at least 15 pages were found",
       len(th) > 3000 and len(lay) > 4000 and len(op) > 800 and all(len(code[n]) > 200 for n in ("tk_close", "tk_frame", "sl_guardmode", "sl_guard", "sl_key", "sl_scr", "screen_key", "sl_form"))
       and all(raw["m%d" % n].strip() for n in (12545, 12546, 12547)) and sum(1 for p in raw["pages"] if p.startswith("tool_")) >= 15,
       "%d %d %d" % (len(th), len(lay), len(op)))

    # ---- M: the model against the pages
    model_consts = (M.minw, M.minh, M.maxw, M.maxh, M.xb, M.yb)
    hconsts = tuple(int(D.get(k, "-1")) for k in ("TK.MINW", "TK.MINH", "TK.MAXW", "TK.MAXH", "TK.XBODY", "TK.YBODY"))
    ck("M0", "the model's constants are tk.h's: TK.MINW, TK.MINH, TK.MAXW, TK.MAXH, TK.XBODY, TK.YBODY (%r)" % (hconsts,), model_consts == hconsts, "model %r" % (model_consts,))
    f = M.frame(140, 43)
    ck("M1", "the frame at 140 by 43 is what $tk_open has always made: W 140, H 43, YSTAT 40, YBORD 41, YKEYS 42; the body 138 by 39 at 1,1; mode full",
       (f["W"], f["H"], f["YSTAT"], f["YBORD"], f["YKEYS"], f["XBODY"], f["YBODY"], f["BODYW"], f["BODYH"]) == (140, 43, 40, 41, 42, 1, 1, 138, 39), repr(f))
    bad = []
    for key, (decl, pick) in DECLS.items():
        src = pre_l2_source(key.split("#")[0], raw["pages"].get(key.split("#")[0], ""))
        boxes = page_boxes(src)
        want = [boxes[i] for i in pick] if pick is not None else boxes
        v = M.validate(decl)
        rects, mode = M.layout(decl, M.frame(140, 43))
        got = [r[:4] for r in rects]
        if not boxes or v is not None or got != want or mode != "full" or not all(r[4] for r in rects):
            bad.append("%s: valid %r mode %s got %r want %r" % (key, v, mode, got, want))
    ck("M2", "AT 140 BY 43 EVERY DECLARATION GIVES EXACTLY THE PAGE'S OWN BOXES, read from its source (%d declarations, %d pages): the layout of the pages is identical when they move onto the service"
       % (len(DECLS), len({k.split('#')[0] for k in DECLS})), not bad and len(DECLS) >= 20, "; ".join(bad)[:900])
    bad = []
    for key, (decl, pick) in DECLS.items():
        rects0, _ = M.layout(decl, M.frame(140, 43))
        for (ww, hh) in SIZES:
            fr2 = M.frame(ww, hh)
            rects, mode = M.layout(decl, fr2)
            sh = [r for r in rects if r[4]]
            if mode != "full" or len(sh) != len(rects):
                bad.append("%s %dx%d mode %s shown %d of %d" % (key, ww, hh, mode, len(sh), len(rects)))
                continue
            for a, r0 in zip(rects, rects0):
                if a[2] < r0[2] or a[3] < r0[3]:
                    bad.append("%s %dx%d %r smaller than %r" % (key, ww, hh, a, r0))
                if a[0] < fr2["XBODY"] or a[1] < fr2["YBODY"] or a[0] + a[2] > fr2["XBODY"] + fr2["BODYW"] or a[1] + a[3] > fr2["YBODY"] + fr2["BODYH"]:
                    bad.append("%s %dx%d %r outside the body" % (key, ww, hh, a))
            for i in range(len(rects)):
                for j in range(i + 1, len(rects)):
                    if overlaps(rects[i], rects[j]):
                        bad.append("%s %dx%d %r overlaps %r" % (key, ww, hh, rects[i], rects[j]))
            if fr2["YKEYS"] != fr2["H"] - 1 or fr2["YSTAT"] != fr2["H"] - 3 or fr2["H"] > M.maxh or fr2["W"] > M.maxw:
                bad.append("%s %dx%d frame %r" % (key, ww, hh, fr2))
    ck("M3", "LARGER (%s): every pane shown, at least its 140-by-43 size, inside the body, no two overlapping; the frame on the last three rows and never above TK.MAXW by TK.MAXH"
       % ", ".join("%dx%d" % s for s in SIZES), not bad, "; ".join(bad)[:900])
    exp = {}
    for ww, hh in ((180, 55), (150, 45)):
        r, _ = M.layout(DECLS["tool_files"][0], M.frame(ww, hh))
        exp[(ww, hh)] = [x[:4] for x in r]
    r, _ = M.layout(DECLS["tool_gates"][0], M.frame(180, 55))
    gates180 = [x[:4] for x in r]
    ck("M4", "worked values: tool.files at 180x55 is list 1,1 178x34 and detail 1,35 178x17; at 150x45 list 1,1 148x24, detail 1,25 148x17; tool.gates at 180x55 shares 40 columns "
             "20/20 between its two bottom panes (1,43 88x9 and 90,43 89x9) and gives the matrix the 12 rows",
       exp[(180, 55)] == [(1, 1, 178, 34), (1, 35, 178, 17)] and exp[(150, 45)] == [(1, 1, 148, 24), (1, 25, 148, 17)]
       and gates180 == [(1, 1, 178, 31), (1, 32, 178, 11), (1, 43, 88, 9), (90, 43, 89, 9)], repr((exp, gates180)))
    ck("M5", "the share: idiv by weight, the rest one at a time from the first weighted item; nothing for 0 or less; a weight 0 gets nothing",
       Model.share(10, [1, 1, 1]) == [4, 3, 3] and Model.share(7, [2, 1]) == [5, 2] and Model.share(5, [0, 1, 0, 1]) == [0, 3, 0, 2] and Model.share(0, [1]) == [0]
       and Model.share(-3, [1, 2]) == [0, 0] and Model.share(4, [0, 0]) == [0, 0], "")
    # smaller: a floor under 140 by 43 (no shipped app declares one; the equations must still be sane)
    small = [P("tree", 1, 39, w=30, col=1, hz=False, v=True, prio=2, minh=10), P("edit", 1, 30, w=107, col=2, gap=1, v=True, minw=70, minh=10),
             P("msgs", 1, 9, w=107, col=2, gap=1, minw=70, minh=3, prio=1)]
    bad = []
    for (ww, hh) in SMALL:
        fr2 = M.frame(ww, hh, 100, 30)
        rects, mode = M.layout(small, fr2)
        if mode != "compact":
            bad.append("%dx%d mode %s" % (ww, hh, mode))
        for a in rects:
            if a[4] and (a[0] < fr2["XBODY"] or a[1] < fr2["YBODY"] or a[0] + a[2] > fr2["XBODY"] + fr2["BODYW"] or a[1] + a[3] > fr2["YBODY"] + fr2["BODYH"]):
                bad.append("%dx%d %r outside" % (ww, hh, a))
        sh = [a for a in rects if a[4]]
        for i in range(len(sh)):
            for j in range(i + 1, len(sh)):
                if overlaps(sh[i], sh[j]):
                    bad.append("%dx%d overlap %r %r" % (ww, hh, sh[i], sh[j]))
    r100, _ = M.layout(small, M.frame(100, 30, 100, 30))
    r120, _ = M.layout(small, M.frame(120, 36, 100, 30))
    ck("M6", "SMALLER (a floor of 100 by 30, a tree of fixed width 30 at priority 2 beside an editor over messages at priority 1, both at least 70 wide): compact, nothing outside the body, "
             "no overlap; at 120x36 (body 118 by 32) the stretching editor column gives up its 20 columns first and nothing collapses (tree 1,1 30x32, editor 32,1 87x23, messages "
             "32,24 87x9); at 100x30 (body 98 by 26) 3 columns are still missing, so the tree (the highest priority) collapses and the editor column takes the width (2,1 97x17 and 2,18 97x9)",
       not bad and r120 == [(1, 1, 30, 32, 1), (32, 1, 87, 23, 1), (32, 24, 87, 9, 1)] and r100 == [(0, 0, 0, 0, 0), (2, 1, 97, 17, 1), (2, 18, 97, 9, 1)],
       "; ".join(bad) + " " + repr((r100, r120)))
    s1 = M.shrink([10, 10, 10], [5, 5, 5], [0, 1, 0], 4)
    s2 = M.shrink([10, 10, 10], [5, 5, 5], [0, 1, 0], 9)
    tie, _ = M.layout([P("a", 1, 10, w=60, col=1, hz=False, prio=1), P("b", 1, 10, w=60, col=2, hz=False, prio=1)], M.frame(100, 30, 100, 30))
    ck("M8", "the order of the shrink and of the collapse: 4 rows from [10, 10, 10] (the middle one stretches, least 5 each) come from the middle one; 9 rows take it to 5 and then the LAST fixed "
             "one; of two panes of equal priority that do not fit, the last declared collapses",
       s1 == ([10, 6, 10], 0) and s2 == ([10, 5, 6], 0) and tie[0][4] == 1 and tie[1][4] == 0, repr((s1, s2, tie)))
    v = [M.validate([P("a", 1, 40)]), M.validate([P("a", 1, 10), P("a", 2, 10)]), M.validate([P("a", 1, 10, minh=11)]), M.validate([P("a", 0, 10)]),
         M.validate([P("a", 1, 10, w=70, col=1), P("b", 1, 10, w=70, col=2)]), M.validate([P("a", 1, 39)]), M.validate([])]
    ck("M7", "the declaration is refused when it does not fit the reference body, has an id twice, a least size above its size, a band under 1 or two columns wider than 138; "
             "a pane of 138 by 39 is accepted; no pane at all is refused",
       v[0] == ("fit", "") and v[1] == (2, "id twice") and v[2] == (1, "least height") and v[3] == (1, "band") and v[4] == ("fit", "") and v[5] is None and v[6] == (0, "no pane"), repr(v))

    # ---- T: the BASIC carries the model's equations
    rb = "rbw = TK.MINW - 2 * TK.XBODY" in lay and "rbh = TK.MINH - 3 - TK.YBODY" in lay
    ck("T1", "$tk_layout's reference body is TK.MINW - 2 * TK.XBODY by TK.MINH - 3 - TK.YBODY, and growth is counted from it: across (bw - rbw), down (bh - rbh) and inside a band (hb - bbh)",
       rb and "sh.amt = bw - rbw" in lay and "sh.amt = bh - rbh" in lay and "sh.amt = hb - bbh<1, bi>" in lay and "if hb >= bbh<1, bi> then" in lay, "")
    fra = label(lay, "frame")
    bod = label(lay, "body")
    ck("T2", "the frame: the window, raised to the floor, cut to TK.MAXW by TK.MAXH; YSTAT H - 3, YBORD H - 2, YKEYS H - 1, YMENU 0; the body W - 2 * TK.XBODY by YSTAT - TK.YBODY",
       ordered(fra, "call $sl_window(win.w, win.h)", "if lw < fw then lw = fw", "if lh < fh then lh = fh", "if lw > TK.MAXW then lw = TK.MAXW", "if lh > TK.MAXH then lh = TK.MAXH",
               "ctx<TK.C.YSTAT> = lh - 3", "ctx<TK.C.YBORD> = lh - 2", "ctx<TK.C.YKEYS> = lh - 1", "gosub body")
       and "ctx<TK.C.YMENU> = 0" in fra and "ctx<TK.C.BODYW> = ctx<TK.C.W> - 2 * TK.XBODY" in bod and "ctx<TK.C.BODYH> = ctx<TK.C.YSTAT> - TK.YBODY" in bod, fra[:200])
    shr = label(lay, "share")
    ck("T3", "the share is idiv(amount * weight, total) and gives the rest one at a time from the first weighted item, nothing when the amount or the total is not above 0",
       "sh.out<1, sh.k> = idiv(sh.amt * sh.wt<1, sh.k>, sh.tot)" in shr and "if sh.amt <= 0 or sh.tot <= 0 then return" in shr
       and ordered(shr, "loop while sh.rem > 0 do", "if sh.wt<1, sh.k> > 0 then", "sh.rem -= 1", "if sh.k > sh.n then sh.k = 1"), shr[:200])
    srk = label(lay, "shrink")
    ck("T4", "the shrink takes from the stretching sizes first, the last first, then from the fixed ones, never below the least size",
       "for s.pass = 1 to 2" in srk and "s.k = s.n" in srk and "if s.pass = 1 and s.str then s.go = 1" in srk and "if s.pass = 2 and not(s.str) then s.go = 1" in srk
       and "s.take = s.size<1, s.k> - s.min<1, s.k>" in srk and "s.k -= 1" in srk, srk[:200])
    lp = label(lay, "lay.panes")
    ck("T5", "the collapse loop: work out the structure, the widths and the heights; when either fails, collapse the shown pane of the highest priority above 0 (>=: the last declared of equals), "
             "only among the failing bands unless the height failed; until nothing collapses",
       ordered(lp, "loop", "gosub structure", "gosub fit.width", "gosub fit.height", "if hfail # '' or vfail then", "if shown<i> and ppr<i> > 0 then", "can = vfail",
               "if ppr<i> >= bestp then", "if best then shown<best> = 0", "until not(best) do"), lp[:300])
    ck("T6", "the mode is full when the body is at least the reference body both ways (one row less when the page gave the AI line a row: S.97 stage 1), else compact; "
             "a collapsed pane's rectangle is 0, 0, 0, 0, 0; the cut also stops a pane at its band's foot",
       "if bw >= rbw and bh >= rbh - (if ctx<TK.C.AIROW> then 1 else 0) then ctx<TK.C.MODE> = 'full' else ctx<TK.C.MODE> = 'compact'" in lp and "rects<1, i> = 0 : @sm : 0 : @sm : 0 : @sm : 0 : @sm : 0" in lp
       and "if ry + rh > y + hb then rh = y + hb - ry" in label(lay, "cut"), "")
    cd = label(lay, "check.decl")
    ck("T7", "the declaration is checked before it is kept (12546 with the pane and the attribute) and against the reference body (12547), and a refused one leaves no panes in the context",
       ordered(cd, "perr = sysmsg(12546", "ctx<TK.C.PANES> = lower(arg)", "gosub structure", "if need > rbw then perr = sysmsg(12547", "if need > rbh then perr = sysmsg(12547")
       and ordered(lay, "case op = 'declare'", "gosub check.decl", "if perr # '' then ctx<TK.C.PANES> = '' ctx<TK.C.RECTS> = '' end", "gosub lay.panes", "ret = perr"), cd[:200])

    # ---- W: the wiring
    slots = {k: int(v) for k, v in D.items() if k.startswith("TK.C.")}
    old = {"TK.C.W": 1, "TK.C.H": 2, "TK.C.UTF8": 3, "TK.C.TRAP": 4, "TK.C.APP": 5, "TK.C.AUD": 6, "TK.C.YSTAT": 7, "TK.C.YBORD": 8, "TK.C.YKEYS": 9, "TK.C.GEN": 10, "TK.C.AI": 11}
    new = {k: v for k, v in slots.items() if k not in old}
    ck("W1", "tk.h: the eleven old slots keep their numbers; the new ones are 12 up, each number once (%d new)" % len(new),
       all(slots.get(k) == v for k, v in old.items()) and new and min(new.values()) == 12 and len(set(slots.values())) == len(slots)
       and sorted(new.values()) == list(range(12, 12 + len(new))), repr(new))
    lit = []
    for n, src in raw["pages"].items():
        s = strip_bas(src)
        for m in re.finditer(r"(?<![\w.$])ctx<\s*(\d+)", s):
            lit.append("%s ctx<%s" % (n, m.group(1)))
    ck("W2", "no program of the toolkit, nor the IDE, CED, SED or the debugger, indexes the toolkit's ctx by a literal number (they say TK.C.*; the editors' own ai.ctx is a different variable)",
       not lit, ", ".join(lit[:10]))
    ck("W3", "$tk_open is VAR.ARGS with floorw and floorh after err; reads each only after UNASSIGNED() in a nested IF; raises a floor to TK.LEASTW by TK.LEASTH and cuts it to TK.MAXW by TK.MAXH; "
             "asks $sl_need for the FLOOR; calls $tk_layout 'open' AFTER the screen is taken and after the floor and the epoch are in ctx; and no number is typed into it",
       "subroutine tk_open(app, audience, ctx, err, floorw, floorh) var.args" in op
       and "if not(unassigned(floorw)) then if floorw # '' then floor.w = floorw end" in op and "if not(unassigned(floorh)) then if floorh # '' then floor.h = floorh end" in op
       and "if floor.w < TK.LEASTW then floor.w = TK.LEASTW" in op and "if floor.h < TK.LEASTH then floor.h = TK.LEASTH" in op
       and "if floor.w > TK.MAXW then floor.w = TK.MAXW" in op and "if floor.h > TK.MAXH then floor.h = TK.MAXH" in op
       and "call $sl_need(app, floor.w, floor.h, need.msg, '')" in op
       and ordered(op, "screen open", "ctx<TK.C.FLOORW> = floor.w", "ctx<TK.C.EPOCH> = ep.next", "call $tk_layout('open', ctx, '', lay.chg)")
       and not re.search(r"\b(100|140|30|42|43|500|300)\b", op), "")
    ck("W4", "$tk_layout arms the cursor lock in its LAYOUT mode with the floor and the layout's size, only for a context that has an app name, on 'open' and 'refresh' (never on 'declare')",
       "call $sl_guardmode(ctx<TK.C.APP>, ctx<TK.C.FLOORW>, ctx<TK.C.FLOORH>, 'layout', ctx<TK.C.W>, ctx<TK.C.H>)" in lay
       and ordered(label(lay, "arm.lock"), "if ctx<TK.C.APP> # '' then", "call $sl_guardmode(")
       and ordered(lay, "case op = 'open' or op = 'refresh'", "gosub frame", "gosub lay.panes", "gosub arm.lock", "case op = 'declare'")
       and "arm.lock" not in lay.split("case op = 'declare'")[1].split("case op = 'pane'")[0], "")
    ck("W5", "'refresh' reports a change: the geometry key (W, H, the body, the mode, every rectangle) before and after, ret and ctx<TK.C.CHANGED>; 'open' always says 1",
       ordered(lay, "gosub geometry.key", "old.key = gk", "gosub frame", "gosub geometry.key", "if gk # old.key then chg = 1", "if op = 'open' then chg = 1", "ctx<TK.C.CHANGED> = chg", "ret = chg")
       and all(s in label(lay, "geometry.key") for s in ("ctx<TK.C.W>", "ctx<TK.C.H>", "ctx<TK.C.BODYW>", "ctx<TK.C.BODYH>", "ctx<TK.C.MODE>", "ctx<TK.C.RECTS>")), "")
    ck("W6", "$sl_guardmode is VAR.ARGS (mode, layw, layh), reads them through UNASSIGNED(), keeps the cursor mode for a three-argument call, and a layout re-arm of the app that holds "
             "the lock keeps its choice to leave; the common block /slguard/ is declared the same in $sl_guardmode, $sl_key and $sl_msgbox",
       "subroutine sl_guardmode(name, minw, minh, mode, layw, layh) var.args" in gm and "if not(unassigned(mode)) then md = mode" in gm
       and "if g.on and g.mode = 'layout' and g.name = name then keep.quit = 1" in gm and "if not(keep.quit) then g.quit = 0" in gm
       and "if md = 'layout' then g.mode = 'layout'" in gm
       and all("common /slguard/ g.on, g.name, g.minw, g.minh, g.quit, g.mode, g.lw, g.lh" in code[n] for n in ("sl_guardmode", "sl_key", "sl_msgbox")), "")
    gc = label(ky, "guard.cursor")
    ck("W7", "R-b: in the layout mode $sl_key asks the WINDOW against the floor (>= both ways: no lock) and gives $sl_guard the floor's last cell and 'layout'; the cursor test is only in the other "
             "branch, as it was",
       ordered(gc, "if g.mode = 'layout' then", "call $sl_window(gw, gh)", "if gw >= g.minw and gh >= g.minh then return",
               "call $sl_guard(g.name, g.minw, g.minh, g.minw - 1, g.minh - 1, gres, 'layout')", "end else", "if not(cu.has) or cu.hid then return",
               "if cu.x < gw and cu.y < gh then return", "call $sl_guard(g.name, g.minw, g.minh, cu.x, cu.y, gres)", "if gres = 'quit' then"), gc[:300])
    ck("W8", "$sl_guard is VAR.ARGS with a seventh argument read through UNASSIGNED(); 'layout' words the warning as the longest of three wordings whose wrapped rows fit the window "
             "(12545, 12730, 12731: a loop of three tiers, each wrapped by its own label, the first with nlines <= h kept), anything else as 12605; 12545 names the window, the app and the floor "
             "and keeps the words 'is laid out for' before the floor (sandbox-tk-keys.py and sandbox-tk-resize.py read them), and says that Ctrl-Q leaves and that text not saved is lost unless a "
             "recovery copy is on; 12730 and 12731 name the window and the floor too (%1, %3) and Ctrl-Q",
       "subroutine sl_guard(name, minw, minh, cx, cy, result, mode) var.args" in gd and "if not(unassigned(mode)) then gmode = mode" in gd
       and ordered(gd, "draw.box:", "if gmode = 'layout' then", "for tier = 1 to 3", "text = sysmsg(12545, w : ' by ' : h, name, minw : ' by ' : minh)",
                   "text = sysmsg(12730, w : ' by ' : h, name, minw : ' by ' : minh)", "text = sysmsg(12731, w : ' by ' : h, name, minw : ' by ' : minh)", "gosub wrap.text",
                   "if nlines <= h then exit", "next tier", "end else", "text = sysmsg(12605, w : ' by ' : h, name, minw : ' by ' : minh)", "gosub wrap.text")
       and "nshow = nlines" in gd and "if nshow > h then nshow = h" in gd and "wrap.text:" in gd
       and re.match(r"^The window is %1 and %2 is laid out for %3\b", raw["m12545"]) is not None and "Ctrl-Q" in raw["m12545"] and "unless a recovery copy is on" in raw["m12545"]
       and all(t in raw["m12730"] for t in ("%1", "%2", "%3", "Ctrl-Q")) and all(t in raw["m12731"] for t in ("%1", "%2", "%3", "Ctrl-Q")), repr(raw["m12545"][:80]))
    ck("W9", "R-a: $sl_key notes every resize it hands out (rz.pending = 1 in resized:, common /slpend/); $sl_scr 'pending' returns and clears the note, and 'open' and 'close' clear it; "
             "the block /slscr/ is unchanged (CPROC declares it)",
       "common /slpend/ rz.pending" in ky and "rz.pending = 1" in label(ky, "resized") and "common /slpend/ rz.pending" in sc
       and "case op = 'pending' scr = 0 if rz.pending then scr = 1 rz.pending = 0" in sc
       and ordered(sc, "case op = 'open'", "rz.pending = 0", "case op = 'resized'") and ordered(sc, "case op = 'close'", "rz.pending = 0", "end case")
       and "common /slscr/ ctx, ctx.open, ctx.resized" in sc, "")
    ck("W10", "R-a: SCREEN KEY asks the note BEFORE it reads a key and gives resize first; when it reads a resize itself it clears the note (delivered once); then the kept picture is made the size",
       # 3 Nov 26 (S.113): the if is a block, the screen is flushed before the key is read, and the kept picture is made the
       # terminal's size with 'peek' (drawn whole at the page's next flush, after it has laid itself out) - the order is unchanged
       ordered(sk, "call $sl_scr('pending', pend)", "if pend then", "ret = 'resize'", "end else", "call $sl_scr('flush', '')", "call $sl_key(timeout, ret)",
               "if ret = 'resize' then call $sl_scr('pending', pend)", "if ret = 'resize' then", "call $sl_scr('peek', scr)", "call $sl_scr('put', scr)"), "")
    we = label(fm, "wait.event")
    ck("W11", "R-a: SCREEN WAIT's wait asks the note before EVERY key (an open list of the form may read a resize too), takes resize as the key, and clears the note when it reads one itself; "
              "the modal run (a dialogue) does not ask",
       ordered(we, "loop", "call $sl_scr('pending', rz.was)", "if rz.was then kk = 'resize' end else", "call $sl_key(tmo, kk)", "if kk = 'resize' then call $sl_scr('pending', rz.was)",
               "if kk = '' then") and "pending" not in label(fm, "run.modal"), we[:300])
    ck("W12", "F1: $tk_open makes a new epoch (common /tkepoch/) into ctx<TK.C.EPOCH>; $tk_frame forgets its cache when the epoch, the geometry or the generation differs; $tk_close clears the epoch "
              "in the block and in ctx after the screen is given back",
       "common /tkepoch/ ep.next, ep.drawn" in op and ordered(op, "ep.next += 1", "ctx<TK.C.EPOCH> = ep.next")
       and "common /tkepoch/ ep.next, ep.drawn" in fr and "if ctx<TK.C.EPOCH> # ep.drawn then forget = 1" in fr and "if geo # last.geo then forget = 1" in fr
       and "if ctx<TK.C.GEN> # last.gen then forget = 1" in fr and ordered(fr, "if forget then", "ep.drawn = ctx<TK.C.EPOCH>", "last.stat = ''", "last.keys = ''", "last.bord = ''", "last.top = ''")
       and "common /tkepoch/ ep.next, ep.drawn" in cl and ordered(cl, "screen close", "call $tk_brk('close'", "ep.drawn = ''", "ctx<TK.C.EPOCH> = ''"), "")
    ck("W13", "the IDE holds the WINDOW lock (28 Oct 26, handoff step 1) and CED does too (9 Nov 26, S.134): each calls $sl_guardmode in the layout mode with its floor and its layout size, "
              "never the three-argument cursor mode; the debugger $sl_guard with six; SCREEN CLOSE and $sl_cleanup still take the lock off",
       "call $sl_guardmode('IDE', LAYW, LAYH, 'layout', LAYW, LAYH)" in code["ide"] and "call $sl_guardmode('IDE', LAYW, LAYH)" not in code["ide"]
       and "call $sl_guardmode('CED', LAYW, LAYH, 'layout', LAYW, LAYH)" in code["ced_edit"] and "call $sl_guardmode('CED', LAYW, LAYH)" not in code["ced_edit"]
       and "call $sl_guard('the debugger', LAY.WIDTH, LAY.DEPTH, cur.x, command.line, guard.result)" in code["debug"]
       and "call $sl_guardmode('', 0, 0)" in code["screen_close"] and "call $sl_guardmode('', 0, 0)" in code["sl_cleanup"], "")
    ck("W14", "$tk_layout is an internal subroutine catalogued $tk_layout, VAR.ARGS (op, ctx, arg, ret), and has the ops open, refresh, declare, pane and body",
       re.search(r"^\$internal\b", raw["tk_layout"], re.M) is not None and re.search(r"^\$catalog \$tk_layout\b", raw["tk_layout"], re.M) is not None
       and "subroutine tk_layout(op, ctx, arg, ret) var.args" in lay
       and all(("op = '%s'" % o) in lay for o in ("open", "refresh", "declare", "pane", "body")), "")
    ck("W15", "messages: 12545 (the layout lock), 12546 (a pane not valid: %1 app, %2 pane, %3 what) and 12547 (the panes do not fit: %1 app, %2 by %3) exist, one line each, in this "
              "port's block",
       all(raw["m%d" % n].endswith("\n") and raw["m%d" % n].count("\n") == 1 for n in (12545, 12546, 12547, 12730, 12731))
       and all(t in raw["m12546"] for t in ("%1", "%2", "%3")) and all(t in raw["m12547"] for t in ("%1", "%2", "%3")), "")
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
        r["model"] = Model(**kw)
        return r
    return f


def page(name, old, new):
    def f(raw):
        r = dict(raw)
        r["pages"] = dict(raw["pages"])
        # 1 Nov 26: a page that moved onto the layout service holds no literal boxes; M2 compares with its source before L2 (pre_l2_source), so the mutant changes THAT
        #   text, and pre_l2_source then takes the mutated text as the working copy because it has boxes again.  Before, the mutant failed with a KeyError on every run.
        src = pre_l2_source(name, r["pages"].get(name, ""))
        if old not in src:
            raise KeyError("%s: %r is not in the page" % (name, old))
        r["pages"][name] = src.replace(old, new, 1)
        return r
    return f


MUTANTS = [
    ("the model grows from what the panes need, not from the reference (tool.menus leaves rows empty at 140 by 43)", "M2", model(growth_from_reference=False)),
    ("the model's body starts on row 2", "M0", model(ybody=2)),
    ("the model's minimum is 140 by 42", "M0", model(minh=42)),
    ("the model collapses the first of equals", "M8", model(collapse_last_of_equals=False)),
    ("the model shrinks the fixed panes first", "M8", model(stretch_first=False)),
    ("a page's box moves a row", "M2", page("tool_gates", "screen box at 1,20 size 138,11", "screen box at 1,21 size 138,10")),
    ("the body is a column wider", "T2", sub("tk_layout", "ctx<TK.C.BODYW> = ctx<TK.C.W> - 2 * TK.XBODY", "ctx<TK.C.BODYW> = ctx<TK.C.W> - TK.XBODY")),
    ("the status line is a row lower", "T2", sub("tk_layout", "ctx<TK.C.YSTAT> = lh - 3", "ctx<TK.C.YSTAT> = lh - 2")),
    ("the layout is not raised to the floor", "T2", sub("tk_layout", "   if lw < fw then lw = fw ", "   if 0 then lw = fw ")),
    ("the layout is not cut to the largest window", "T2", sub("tk_layout", "   if lh > TK.MAXH then lh = TK.MAXH\n", "")),
    ("the growth is counted from the panes' need", "T1", sub("tk_layout", "sh.amt = bh - rbh", "sh.amt = bh - need")),
    ("the band's rows go to its columns from their own need", "T1", sub("tk_layout", "sh.amt = hb - bbh<1, bi>", "sh.amt = hb - cbh<bi, ci>")),
    ("the share divides with /", "T3", sub("tk_layout", "idiv(sh.amt * sh.wt<1, sh.k>, sh.tot)", "int(sh.amt * sh.wt<1, sh.k> / sh.tot)")),
    ("the rest is given to weight 0 too", "T3", sub("tk_layout", "      if sh.wt<1, sh.k> > 0 then\n         sh.out<1, sh.k> = sh.out<1, sh.k> + 1", "      if 1 then\n         sh.out<1, sh.k> = sh.out<1, sh.k> + 1")),
    ("the shrink goes first to last", "T4", sub("tk_layout", "      s.k = s.n\n", "      s.k = 1\n")),
    ("the collapse takes the first of equals", "T5", sub("tk_layout", "if ppr<i> >= bestp then", "if ppr<i> > bestp then")),
    ("a never-collapse pane collapses", "T5", sub("tk_layout", "if shown<i> and ppr<i> > 0 then", "if shown<i> then")),
    ("the mode is always full", "T6", sub("tk_layout", "else ctx<TK.C.MODE> = 'compact'", "else ctx<TK.C.MODE> = 'full'")),
    ("a row short is full for every page, not only one with the AI line", "T6", sub("tk_layout", "bh >= rbh - (if ctx<TK.C.AIROW> then 1 else 0)", "bh >= rbh - 1")),
    ("a refused declaration keeps its panes", "T7", sub("tk_layout", "         if perr # '' then\n            ctx<TK.C.PANES> = ''\n", "         if perr # '' then\n")),
    ("the fit is not checked", "T7", sub("tk_layout", "      if need > rbw then perr = sysmsg(12547, app, TK.MINW, TK.MINH)\n", "")),
    ("a slot moves", "W1", sub("tk.h", "$define TK.C.AI        11", "$define TK.C.AI        12")),
    ("two slots share a number", "W1", sub("tk.h", "$define TK.C.WINW      14", "$define TK.C.WINW      13")),
    ("a page indexes ctx by number", "W2", page("tool_files", "ctx<TK.C.GEN> = gen", "ctx<10> = gen")),
    ("the floor is read without UNASSIGNED", "W3", sub("tk_open", "   if not(unassigned(floorw)) then\n      if floorw # '' then floor.w = floorw\n   end", "   if floorw # '' then floor.w = floorw")),
    ("the floor is not raised to the least", "W3", sub("tk_open", "   if floor.w < TK.LEASTW then floor.w = TK.LEASTW\n", "")),
    ("$sl_need is asked for 140 by 43 whatever the floor", "W3", sub("tk_open", "call $sl_need(app, floor.w, floor.h, need.msg, '')", "call $sl_need(app, TK.MINW, TK.MINH, need.msg, '')")),
    ("the layout is made before the screen is taken", "W3", sub("tk_open", "   call $tk_layout('open', ctx, '', lay.chg)\n", "")),
    ("$tk_open is not VAR.ARGS", "W3", sub("tk_open", "floorw, floorh) var.args", "floorw, floorh)")),
    ("the lock is armed in the cursor mode", "W4", sub("tk_layout", "ctx<TK.C.FLOORH>, 'layout', ctx<TK.C.W>, ctx<TK.C.H>)", "ctx<TK.C.FLOORH>)")),
    ("the lock is armed with a null name", "W4", sub("tk_layout", "   if ctx<TK.C.APP> # '' then\n      call $sl_guardmode(", "   if 1 then\n      call $sl_guardmode(")),
    ("refresh never says it changed", "W5", sub("tk_layout", "         if gk # old.key then chg = 1\n         if op = 'open' then chg = 1\n", "         if op = 'open' then chg = 1\n")),
    ("a layout re-arm forgets the choice to leave", "W6", sub("sl_guardmode", "   if not(keep.quit) then g.quit = 0", "   g.quit = 0")),
    ("$sl_msgbox declares the old block", "W6", sub("sl_msgbox", "common /slguard/ g.on, g.name, g.minw, g.minh, g.quit, g.mode, g.lw, g.lh", "common /slguard/ g.on, g.name, g.minw, g.minh, g.quit")),
    ("the layout mode asks the cursor", "W7", sub("sl_key", "      if gw >= g.minw and gh >= g.minh then return\n", "      if cu.x < gw and cu.y < gh then return\n")),
    ("the layout lock lifts only above the floor", "W7", sub("sl_key", "if gw >= g.minw and gh >= g.minh then return", "if gw > g.minw and gh > g.minh then return")),
    ("the layout warning is the cursor's", "W8", sub("sl_guard", "text = sysmsg(12545,", "text = sysmsg(12605,")),
    ("12545 loses the words the suites read", "W8", sub("m12545", "is laid out for %3", "needs %3")),
    ("$sl_key forgets to note a resize", "W9", sub("sl_key", "   rz.pending = 1\n", "")),
    ("SCREEN OPEN keeps an old note", "W9", sub("sl_scr", "         rz.pending = 0                         ;* a resize from before this screen is not this program's\n", "")),
    ("SCREEN KEY does not ask the note", "W10", sub("screen_key", "   call $sl_scr('pending', pend)                   ;* a resize a dialogue read", "   pend = 0                   ;* a resize a dialogue read")),
    ("SCREEN KEY delivers a resize twice", "W10", sub("screen_key", "      if ret = 'resize' then call $sl_scr('pending', pend)", "      null")),
    ("SCREEN WAIT does not ask the note", "W11", sub("sl_form", "      call $sl_scr('pending', rz.was)\n      if rz.was then", "      rz.was = 0\n      if rz.was then")),
    ("SCREEN WAIT delivers a resize twice", "W11", sub("sl_form", "         if kk = 'resize' then call $sl_scr('pending', rz.was)\n", "")),
    ("the frame ignores the epoch", "W12", sub("tk_frame", "   if ctx<TK.C.EPOCH> # ep.drawn then forget = 1\n", "")),
    ("the frame ignores the geometry", "W12", sub("tk_frame", "   if geo # last.geo then forget = 1\n", "")),
    ("$tk_close keeps the epoch", "W12", sub("tk_close", "   ep.drawn = ''", "   null")),
    ("$tk_open makes no new epoch", "W12", sub("tk_open", "   ep.next += 1\n", "")),
    ("the IDE is put back in the cursor mode", "W13", sub("ide", "call $sl_guardmode('IDE', LAYW, LAYH, 'layout', LAYW, LAYH)", "call $sl_guardmode('IDE', LAYW, LAYH)")),
    ("CED is put back in the cursor mode", "W13", sub("ced_edit", "call $sl_guardmode('CED', LAYW, LAYH, 'layout', LAYW, LAYH)", "call $sl_guardmode('CED', LAYW, LAYH)")),
    ("the warning is always the longest wording", "W8", sub("sl_guard", "            if nlines <= h then exit\n", "            null\n")),
    ("the middle wording is the cursor's", "W8", sub("sl_guard", "text = sysmsg(12730,", "text = sysmsg(12605,")),
    ("12545 stops saying that unsaved text is lost", "W8", sub("m12545", "; text not saved is lost unless a recovery copy is on", "")),
    ("12731 loses the floor", "W8", sub("m12731", "needs %3", "needs more")),
    ("$tk_layout loses the op pane", "W14", sub("tk_layout", "case op = 'pane'", "case op = 'panes'")),
    ("12547 loses its size", "W15", sub("m12547", "%2 by %3", "reference")),
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
    print("test-tklayout-units: tree %s" % os.path.dirname(GPL))
    if not raw["tk_layout"] or not raw["tk.h"]:
        print("test-tklayout-units: CANNOT RUN - gpl.bp/tk_layout or tk.h is not there")
        return 2
    rows = checks(raw)
    bad = report(rows)
    print("\ntest-tklayout-units: %d passed, %d failed" % (len(rows) - bad, bad))
    rc = 1 if bad else 0
    if "--selftest" in argv:
        rc = (selftest(raw) or rc)
    return rc


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
