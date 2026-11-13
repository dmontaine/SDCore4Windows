#!/usr/bin/env python3
#
# mkpack.py - generate the SD knowledge pack (agent-pack/pack) from the sources.  S.69 row 1b of the AI plan
#             (.claude/ai-integration-evaluation.md, 5A.2 and 5A.2b).
#
#   python3 mkpack.py --write                       regenerate agent-pack/pack from this tree and the docs checkout
#   python3 mkpack.py --check                       build in memory and compare with the committed pack (exit 1 if they differ)
#   python3 mkpack.py --tree DIR --docs DIR --out DIR --product NAME   another tree (Linux Solo: its sdb_ai/sd64 and its docs)
#
# THE ROSTERS ARE COMPUTED, NEVER TYPED.  A verb is a VOC record of type V (or a keyword whose field 3 says V); a query
# keyword is a K record; a message is a file; a BASIC name is in a table of bcomp; a configuration parameter is a branch of
# config.c's read chain; a gate word is a case of modifya.  Meaning that no program can state (what a clause does, how a VOC
# record is laid out) is taken VERBATIM from a section of the docs, found by its heading, and the generator REFUSES to write when
# a heading it needs has gone or a verb has no syntax line - a pack with a hole in it is worse than none (the contract of the
# docs' own mktclsyntax.py and mksyntax.py, which this reuses).
#
# EVERY CHUNK carries  src=path:line#hash  - where in the tree (or, with a docs: prefix, in the docs checkout) it came from, and
# the first 8 hex of the sha1 of that line with trailing blanks removed.  The hash is the identity; the line number is a locator
# that may lag, so that an edit elsewhere in bcomp does not make every function chunk stale.  gplbld/test-pack-units.py checks
# that the cited text still exists and compares a fresh build with the committed pack ignoring the numbers.
#
# NOTHING HERE READS THE NETWORK, A KEY OR A MODEL.  Standard library only.
#
# START-HISTORY:
# 19 Oct 26 dm  Written (S.69 rows 1 and 1b).
# 13 Nov 26 Windows port - from Linux b1d496df (RELEASE_1.1 253a, owner 12 Nov: carry the agent pack).  The docs checkout is the
#               sibling SDCore4WindowsDocs (found beside this repository, not by a Linux absolute path), the product is SD Core
#               for Windows, and the command is "python" (Windows has no python3 by that name).  Nothing else changes: the
#               rosters are computed from this tree, so the pack is this tree's, not a copy of Linux's.
# END-HISTORY

import argparse
import hashlib
import io
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_TREE = os.path.dirname(HERE)
DEFAULT_DOCS = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(DEFAULT_TREE))), "SDCore4WindowsDocs")
DEFAULT_OUT = os.path.join(HERE, "pack")
PACK_FORMAT = 1
TIERS = ("core", "reference", "examples")
REGEN = "python agent-pack/mkpack.py --write"

# What the generator reads, relative to the tree root ("docs:" = the docs checkout).  test-pack-units.py copies exactly these
# for its mutants, so a source read here and not listed here makes a mutant run on a hole.
INPUT_PATHS = [
    "sdsys/newvoc", "sdsys/voc_template", "sdsys/messages", "sdsys/changelog",
    "sdsys/gpl.bp", "sdsys/syscom", "gplsrc/config.c", "sd.conf", "gplbld/FILES_DICTS", "agent-pack/core-start.md", "agent-pack/guide/sd-basic-guide.md",
    "docs:User/markdown", "docs:Administrator/markdown",
    "docs:tools/tcl-syntax-shapes.txt", "docs:tools/syntax-shapes.txt",
]


# ----------------------------------------------------------------------------------------------------------- reading

class Ctx:
    """Reads the tree and the docs, remembers every line it was asked to cite."""

    def __init__(self, tree, docs):
        self.tree = tree
        self.docs = docs
        self._text = {}

    def path(self, rel):
        if rel.startswith("docs:"):
            return os.path.join(self.docs, rel[5:])
        return os.path.join(self.tree, rel)

    def exists(self, rel):
        return os.path.exists(self.path(rel))

    def text(self, rel):
        if rel not in self._text:
            with open(self.path(rel), "rb") as f:
                raw = f.read()
            # the docs are UTF-8; everything in the tree is bytes, read as Latin-1 and made printable later by clean()
            self._text[rel] = raw.decode("utf-8", "replace") if rel.startswith("docs:") else raw.decode("latin-1")
        return self._text[rel]

    def lines(self, rel):
        t = self.text(rel).split("\n")
        if t and t[-1] == "":
            t.pop()
        return t

    def listdir(self, rel):
        return sorted(n for n in os.listdir(self.path(rel)) if os.path.isfile(os.path.join(self.path(rel), n)))

    def src(self, rel, lineno):
        """path:line#hash for line number lineno (1-based) of rel."""
        ls = self.lines(rel)
        if not 1 <= lineno <= len(ls):
            raise SystemExit("mkpack: %s has no line %d (it has %d)" % (rel, lineno, len(ls)))
        raw = ls[lineno - 1].encode("utf-8" if rel.startswith("docs:") else "latin-1")      # the bytes of the file, as the check reads them
        return "%s:%d#%s" % (rel, lineno, line_hash(raw))

    def find(self, rel, pattern, start=1, flags=0):
        """First 1-based line number at or after start whose text matches the regex, or None."""
        rx = re.compile(pattern, flags)
        ls = self.lines(rel)
        for i in range(start - 1, len(ls)):
            if rx.search(ls[i]):
                return i + 1
        return None


def line_hash(raw):
    """First 8 hex of the sha1 of a line's bytes with trailing ASCII blanks removed."""
    return hashlib.sha1(raw.rstrip()).hexdigest()[:8]


def clean(s):
    """Tree text made safe for a markdown pack: bytes 128 and up and control characters other than newline become \\xNN."""
    return "".join(c if (32 <= ord(c) < 127 or c == "\n") else "\\x%02x" % ord(c) for c in s)


def fence(text):
    """A fenced block that cannot be closed by what it holds."""
    runs = [len(m) for m in re.findall(r"`+", text)]
    f = "`" * max(3, (max(runs) + 1) if runs else 3)
    return "%s\n%s\n%s" % (f, text.rstrip("\n"), f)


def words(text):
    return len(text.split())


def md_links_plain(s):
    """[text](target.html) becomes text: a pack has no pages to link to."""
    return re.sub(r"\[([^\]]+)\]\([^)\s]*\)", r"\1", s)


def demote(body):
    """Headings inside a docs section become bold lines, so a chunk body never holds a heading that could be read as a chunk."""
    out = []
    in_fence = False
    for ln in body.split("\n"):
        if ln.startswith("```"):
            in_fence = not in_fence
        m = None if in_fence else re.match(r"^#{1,6}\s+(.*\S)\s*$", ln)
        out.append("**%s**" % m.group(1) if m else ln)
    return "\n".join(out)


class Chunk:
    def __init__(self, cid, kind, tier, since, srcs, body, group):
        assert tier in TIERS, (cid, tier)
        assert re.match(r"^[a-z0-9]+(:[A-Za-z0-9_.$@%+*<>!&#-]+)+$", cid), "bad chunk id " + cid
        self.id, self.kind, self.tier, self.since, self.srcs, self.body, self.group = cid, kind, tier, since or "-", srcs, body.strip("\n"), group
        assert "\n### " not in "\n" + self.body, "a chunk body holds a chunk heading: " + cid

    def render(self):
        meta = ["kind=%s" % self.kind, "tier=%s" % self.tier, "since=%s" % self.since]
        for i, s in enumerate(self.srcs):
            meta.append("src=%s" % s if i == 0 else "src%d=%s" % (i + 1, s))
        return "### %s\n> %s\n\n%s\n" % (self.id, " ".join(meta), self.body)


SRC_NUM = re.compile(rb"(src\d?=\S+?):\d+#")


def normalize(data):
    """A part with the source line numbers blanked: what is compared and digested (the line numbers are locators)."""
    return SRC_NUM.sub(rb"\1:#", data)


# ----------------------------------------------------------------------------------------------------------- the changelog

def changelog_sections(ctx):
    """[(section token, [title lines])] in file order: 'next', 'L1.1-3', ... and the upstream 'Version x' sections."""
    rel = "sdsys/changelog"
    out = []
    cur = None
    in_title = False
    for ln in ctx.lines(rel):
        m = re.match(r"^(Next release)\b.*", ln)
        m2 = re.match(r"^(L\d+\.\d+-\d+)\s+-\s", ln)
        m3 = re.match(r"^Version\s+(\S+)", ln)
        if m:
            cur = ("next", [])
            out.append(cur)
            in_title = False
        elif m2:
            cur = (m2.group(1), [])
            out.append(cur)
            in_title = False
        elif m3:
            cur = (m3.group(1), [])
            out.append(cur)
            in_title = False
        elif cur is not None:
            e = re.match(r"^\d{2} [A-Z][a-z]{2} \d{2}\s+(.*\S)", ln)
            if e:
                cur[1].append(e.group(1))
                in_title = True
            elif in_title and ln.strip():
                cur[1][-1] += " " + ln.strip()
            else:
                in_title = False
            if cur[0].startswith("0.") or re.match(r"^[01]\.\d", cur[0]):
                if ln.strip() and not e:
                    cur[1].append(ln.strip())
    return out


class Since:
    """The earliest changelog section whose entry TITLES name an item.  Only names that cannot be plain English count (they
    carry a dot, a dollar, a bang or an underscore, or are long): 'list' is in a hundred titles that are not about LIST."""

    def __init__(self, ctx):
        self.secs = changelog_sections(ctx)
        self.cache = {}

    def strong(self, name):
        return bool(re.search(r"[.$!_]", name)) or len(name) >= 9

    def of(self, name):
        if name in self.cache:
            return self.cache[name]
        got = "-"
        if self.strong(name):
            rx = re.compile(r"(?<![A-Za-z0-9.$_-])" + re.escape(name) + r"(?![A-Za-z0-9$_]|\.[A-Za-z0-9])", re.I)
            for sec, titles in reversed(self.secs):          # oldest first
                if any(rx.search(t) for t in titles):
                    got = sec
                    break
        self.cache[name] = got
        return got


# ----------------------------------------------------------------------------------------------------------- docs sections

class DocSections:
    """A docs markdown file cut at its headings, so a chunk can be one section found by its heading text."""

    def __init__(self, ctx, rel):
        self.ctx, self.rel = ctx, rel
        self.lines = ctx.lines(rel)
        self.heads = []                                       # (level, text, lineno)
        in_fence = False
        for i, ln in enumerate(self.lines, 1):
            if ln.startswith("```"):
                in_fence = not in_fence
            m = None if in_fence else re.match(r"^(#{1,6})\s+(.*\S)\s*$", ln)
            if m:
                self.heads.append((len(m.group(1)), m.group(2), i))

    def find(self, pattern):
        rx = re.compile(pattern)
        for k, (lvl, text, ln) in enumerate(self.heads):
            if rx.search(text):
                return k
        raise SystemExit("mkpack: %s has no heading matching %r - the docs changed under the pack; refusing" % (self.rel, pattern))

    def section(self, pattern, with_children=False):
        """(heading text, body text, lineno of the heading) of the section whose heading matches."""
        k = self.find(pattern)
        lvl, text, ln = self.heads[k]
        end = len(self.lines) + 1
        for lvl2, _t, ln2 in self.heads[k + 1:]:
            if lvl2 <= lvl or not with_children:
                end = ln2
                break
        body = "\n".join(self.lines[ln:end - 1]).strip("\n")
        return md_links_plain(text), demote(md_links_plain(body)), ln


# ----------------------------------------------------------------------------------------------------------- VOC records

def voc_record(ctx, rel):
    """The fields of a VOC record file: the lines, without the final newline."""
    return ctx.lines(rel)


def fld(r, n):
    return r[n - 1].strip() if len(r) >= n else ""


class Voc:
    """Both VOC layers: newvoc (every account) and voc_template (SDSYS's own, a superset)."""

    def __init__(self, ctx):
        self.ctx = ctx
        self.entries = {}                                     # name -> dict
        for layer in ("newvoc", "voc_template"):
            for name in ctx.listdir("sdsys/" + layer):
                rel = "sdsys/%s/%s" % (layer, name)
                r = voc_record(ctx, rel)
                if name.lower() in self.entries:
                    self.entries[name.lower()]["layers"].append(layer)
                    self.entries[name.lower()]["by_layer"][layer] = rel          # the layers' records are not always identical
                    continue
                t1 = fld(r, 1)[:1].upper()
                t3 = fld(r, 3)[:1].upper()
                typ = fld(r, 1)[:2].upper() if fld(r, 1)[:2].upper() in ("PA", "PH", "PQ") else t1
                verb = t1 == "V" or (t1 == "K" and t3 == "V")
                self.entries[name.lower()] = {"name": name, "rel": rel, "rec": r, "type": typ, "verb": verb, "layers": [layer],
                                              "by_layer": {layer: rel}}

    def verbs(self):
        return {k: v for k, v in self.entries.items() if v["verb"]}


def dispatch_of(e):
    r = e["rec"]
    if fld(r, 1)[:1].upper() == "V":
        return fld(r, 2).upper(), fld(r, 3), fld(r, 4)
    return fld(r, 4).upper(), fld(r, 5), fld(r, 6)


def catalogue_programs(ctx):
    """catalogue name (lower case) -> (program file, line) from the $catalog statements of gpl.bp."""
    cat = {}
    for name in ctx.listdir("sdsys/gpl.bp"):
        rel = "sdsys/gpl.bp/" + name
        for i, ln in enumerate(ctx.lines(rel), 1):
            m = re.match(r"^\s*\$catalog(?:ue)?\s+(\S+)", ln, re.I)
            if m:
                cat.setdefault(m.group(1).lower(), (rel, i))
    return cat


def read_shapes(ctx, rel, lower):
    """NAME = markdown  ->  {name: (shape, lineno)} for the docs' syntax-shapes files."""
    shapes = {}
    for i, ln in enumerate(ctx.lines(rel), 1):
        s = ln.strip()
        if not s or s.startswith("#"):
            continue
        if "=" not in s:
            raise SystemExit("mkpack: %s:%d has no '=' - refusing" % (rel, i))
        k, v = s.split("=", 1)
        k = k.strip().lower() if lower else k.strip().upper()
        if k in shapes:
            raise SystemExit("mkpack: %s:%d is a second line for %s" % (rel, i, k))
        shapes[k] = (v.strip(), i)
    return shapes


def doc_pointer(ctx, name, files):
    """The first docs heading (levels 2-4) that opens with the name, as (file, lineno), or None."""
    rx = re.compile(r"^#{2,4}\s+`?" + re.escape(name) + r"`?(\s|$|[\s—:-])", re.I)
    for f in files:
        for i, ln in enumerate(ctx.lines(f), 1):
            if rx.match(ln):
                return f, i
    return None


def tcl_chunks(ctx, voc, since):
    out = []
    shapes = read_shapes(ctx, "docs:tools/tcl-syntax-shapes.txt", True)
    verbs = voc.verbs()
    missing = sorted(set(verbs) - set(shapes))
    extra = sorted(set(shapes) - set(verbs))
    if missing or extra:
        raise SystemExit("mkpack: REFUSED - verbs with no line in tcl-syntax-shapes.txt: %s; lines that name no verb: %s" % (missing[:8], extra[:8]))
    cat = catalogue_programs(ctx)
    krows = keyword_rows(ctx)
    docfiles =["docs:User/markdown/" + n for n in ctx.listdir("docs:User/markdown")
                if re.match(r"^(19|2\d|3[01]|32|33|35|36)", n)]
    docfiles += ["docs:Administrator/markdown/" + n for n in ctx.listdir("docs:Administrator/markdown")]
    for name, e in sorted(verbs.items()):
        shape, shape_ln = shapes[name]
        mode, target, extra_opt = dispatch_of(e)
        srcs = [ctx.src(e["rel"], 1), ctx.src("docs:tools/tcl-syntax-shapes.txt", shape_ln)]
        # 24 Oct 26: a verb in BOTH layers whose two records dispatch differently (tool.gates: the matrix in SDSYS's VOC, the account holder's page in newvoc).  The dispatch line
        # is SDSYS's - gplbld/sandbox-pack-examples.py compares it with the running SD's VOC - and the ordinary account's is a line of its own.
        alt_dispatch = None
        if "newvoc" in e.get("by_layer", {}) and "voc_template" in e.get("by_layer", {}):
            m2, t2, x2 = dispatch_of(dict(e, rec=voc_record(ctx, e["by_layer"]["voc_template"])))
            if (m2, t2) != (mode, target):
                alt_dispatch = (mode, target)
                mode, target, extra_opt = m2, t2, x2
                srcs.append(ctx.src(e["by_layer"]["voc_template"], 1))
        who = "every account (in `newvoc`)" if "newvoc" in e["layers"] else "SDSYS only (in `voc_template`, not in `newvoc`)"
        lines = ["%s" % shape, ""]
        desc = fld(e["rec"], 1) if fld(e["rec"], 1)[:1].upper() == "V" else fld(e["rec"], 3)
        lines.append("- VOC record `%s`: %s" % (e["rel"], "type V" if fld(e["rec"], 1)[:1].upper() == "V" else "a keyword that is also a verb (fields 4-5 are the verb)"))
        what = {"CA": "a catalogued program", "IN": "an internal verb of the command processor", "OS": "an operating-system command (the sh gate)",
                "CS": "a locally catalogued function"}.get(mode, mode or "unknown")
        lines.append("- dispatch `%s`%s: %s" % (mode, " " + target if target else "", what))
        if mode == "CA":
            prog = cat.get(target.lower())
            if prog:
                lines.append("- program `%s`" % prog[0])
                srcs.append(ctx.src(prog[0], prog[1]))
        if alt_dispatch:
            lines.append("- in an ordinary account's VOC (`newvoc`) this verb is `%s %s`, not SDSYS's program: it is not the same page" % alt_dispatch)
        lines.append("- available to: %s" % who)
        lines.append("- VOC description: %s" % clean(desc))
        dp = doc_pointer(ctx, name, docfiles)
        if dp:
            lines.append("- documented at `%s` (heading, line %d)" % (dp[0][5:], dp[1]))
        kind = "tcl.verb" if fld(e["rec"], 1)[:1].upper() == "V" else "tcl.verb+keyword"
        if kind != "tcl.verb":                                # also a keyword: the keyword number, and the query pages' rows for it
            lines.append("- keyword number %s (field 2); VOC keyword description: %s" % (fld(e["rec"], 2), clean(fld(e["rec"], 1))))
            for rel, ln, text in krows.get(name, [])[:2]:
                lines.append("- docs %s (`%s`, line %d): %s" % ("table row" if text.startswith("|") else "first mention", rel[5:], ln, md_links_plain(text)))
                srcs.append(ctx.src(rel, ln))
        out.append(Chunk("tcl:" + name, kind, "reference", since.of(name), srcs, "\n".join(lines), "tcl-verbs"))
    return out, shapes


KEYWORD_DOCS = ["19-sd-tcl-command-processor", "21-sd-tcl-query-processor", "22-sd-tcl-select-lists", "23-sd-tcl-alternate-key-indexes",
                "20-sd-tcl-files-and-records", "20a-sd-tcl-collection-files"]


def keyword_rows(ctx):
    """name -> [(docs file, lineno, text)]: table rows of the query pages whose first cell names a keyword, then (so that a keyword
    the tables do not list still points somewhere) the first prose line that puts it in backticks."""
    rows = {}
    firsts = {}
    for stem in KEYWORD_DOCS:
        rel = "docs:User/markdown/%s.md" % stem
        if not ctx.exists(rel):
            continue
        in_fence = False
        for i, ln in enumerate(ctx.lines(rel), 1):
            if ln.startswith("```"):
                in_fence = not in_fence
            if in_fence or ln.startswith("#"):
                continue
            if ln.startswith("|"):
                cells = [c.strip() for c in ln.strip().strip("|").split("|")]
                if len(cells) >= 2:
                    for tok in re.findall(r"`([A-Za-z][A-Za-z0-9.$-]*)`", cells[0]):
                        rows.setdefault(tok.lower(), []).append((rel, i, ln.strip()))
                continue
            for tok in re.findall(r"`([A-Za-z][A-Za-z0-9.$-]*)`", ln):
                firsts.setdefault(tok.lower(), (rel, i, ln.strip()[:400]))
    for tok, hit in firsts.items():
        if tok not in rows:
            rows[tok] = [hit]
    return rows


def keyword_chunks(ctx, voc, since):
    out = []
    rows = keyword_rows(ctx)
    for name, e in sorted(voc.entries.items()):
        if e["type"] != "K" or e["verb"]:                     # the four keyword-verbs are one chunk, in tcl_chunks
            continue
        r = e["rec"]
        srcs = [ctx.src(e["rel"], 1)]
        lines = ["`%s` - a keyword of the query processor and the command line" % name, ""]
        lines.append("- VOC record `%s`, type K, keyword number %s" % (e["rel"], fld(r, 2) or "(none)"))
        lines.append("- VOC description: %s" % clean(fld(r, 1)))
        lines.append("- available to: %s" % ("every account (in `newvoc`)" if "newvoc" in e["layers"] else "SDSYS only (in `voc_template`, not in `newvoc`)"))
        got = rows.get(name, [])[:2]
        for rel, ln, text in got:
            lines.append("- docs %s (`%s`, line %d): %s" % ("table row" if text.startswith("|") else "first mention", rel[5:], ln, md_links_plain(text)))
            srcs.append(ctx.src(rel, ln))
        out.append(Chunk("tcl:" + name, "tcl.keyword", "reference", since.of(name), srcs, "\n".join(lines), "tcl-keywords"))
    return out


# ----------------------------------------------------------------------------------------------------------- VOC types and layers

VOC_TYPE_DOC = "docs:User/markdown/32-sd-voc-structure-and-usage.md"

VOC_TYPES = [                     # (type code, heading pattern in docs 32)
    ("V", r"^The V record"), ("K", r"^The K record"), ("S", r"^The S record"), ("PA", r"^The PA record"),
    ("PH", r"^The PH record"), ("Q", r"^The Q record"), ("F", r"^The F record"), ("R", r"^The R record"),
    ("X", r"^The X record"),
]


def voc_chunks(ctx, voc, since):
    out = []
    d = DocSections(ctx, VOC_TYPE_DOC)
    # the table of ten types
    h, body, ln = d.section(r"^The ten record types")
    out.append(Chunk("voc:types", "voc.types", "reference", "-", [ctx.src(VOC_TYPE_DOC, ln)], "**%s**\n\n%s" % (h, body), "voc"))
    for code, pat in VOC_TYPES:
        h, body, ln = d.section(pat, with_children=True)
        census = {}
        for k, e in voc.entries.items():
            if e["type"] == code or (code == "V" and e["verb"]):
                census[e["layers"][0]] = census.get(e["layers"][0], 0) + 1
        out.append(Chunk("voc:type:" + code, "voc.type", "reference", "-", [ctx.src(VOC_TYPE_DOC, ln)], "**%s**\n\n%s" % (h, body), "voc"))
    h, body, ln = d.section(r"^The ten record types")
    # the layers and the census, computed
    layers = {"newvoc": {}, "voc_template": {}}
    only_tmpl = []
    for k, e in sorted(voc.entries.items()):
        for L in e["layers"]:
            layers[L][e["type"]] = layers[L].get(e["type"], 0) + 1
        if "newvoc" not in e["layers"]:
            only_tmpl.append(e["name"])
    for L in ("newvoc", "voc_template"):
        n = sum(layers[L].values())
        census = ", ".join("%s %d" % (t, c) for t, c in sorted(layers[L].items()))
        lines = ["%d records in `sdsys/%s`, by the type letter of field 1: %s." % (n, L, census), ""]
        if L == "newvoc":
            lines.append("Every ordinary account's VOC is `newvoc` in full (`create.account` copies it; `update.accounts` refreshes it). It holds the local "
                         "changes saved in `newvoc.mods` on top, when that file exists.")
        else:
            lines.append("SDSYS's own VOC is `voc_template` in full: a superset of `newvoc`. The records only SDSYS has (%d): %s." % (
                len(only_tmpl), ", ".join("`%s`" % x for x in only_tmpl)))
        out.append(Chunk("voc:layer:" + L, "voc.layer", "reference", "-", [ctx.src("sdsys/%s/%s" % (L, sorted(os.listdir(ctx.path("sdsys/" + L)))[0]), 1)],
                         "\n".join(lines), "voc"))
    return out


def voc_entry_examples(ctx, voc, since):
    """Every shipped VOC record that is not a verb or a keyword, verbatim: real S, PA, PH, Q, F, R and X records."""
    out = []
    for name, e in sorted(voc.entries.items()):
        if e["verb"] or e["type"] == "K":
            continue
        texts = {L: ctx.text(rel).rstrip("\n") for L, rel in e["by_layer"].items()}
        srcs = [ctx.src(rel, 1) for rel in e["by_layer"].values()]
        if len(set(texts.values())) <= 1:
            body = "VOC record `%s` (type %s), the same in %s:\n\n%s" % (e["rel"], e["type"], " and ".join("`%s`" % L for L in e["layers"]),
                                                                       fence(clean(next(iter(texts.values())))))
        else:
            # the two layers differ (a description in field 1 in one and not in the other): both are shown, newvoc first.  SDSYS's own
            # VOC is built from voc_template, so gplbld/sandbox-pack-examples.py compares the SECOND block with the running SD.
            body = ("VOC record `%s` (type %s). The layers differ, usually in field 1, where one carries a description and the other only the type.\n\n"
                    "In `newvoc` (what a new account's VOC is made from):\n\n%s\n\nIn `voc_template` (SDSYS's own VOC):\n\n%s") % (
                name, e["type"], fence(clean(texts["newvoc"])), fence(clean(texts["voc_template"])))
        out.append(Chunk("voc:entry:" + name, "voc.entry", "examples", since.of(name), srcs, body, "voc-entries"))
    return out


# ----------------------------------------------------------------------------------------------------------- docs mentions

def docs_mentions(ctx, order=("User", "Administrator")):
    """token (lower case) -> (docs file, lineno, line): the first backtick span in the User and Administrator pages that holds the
    token as a whole word, so that a name from a table of the code can point at a page that talks about it."""
    seen = {}
    for sub in order:
        base = "docs:%s/markdown/" % sub
        for n in ctx.listdir(base[:-1]):
            if not n.endswith(".md") or n.startswith("94-") or n.startswith("95-") or n.startswith("00"):
                continue
            rel = base + n
            for i, ln in enumerate(ctx.lines(rel), 1):
                if ln.startswith("#"):
                    for tok in re.findall(r"`([^`]+)`", ln):
                        for w in re.findall(r"[A-Za-z$][A-Za-z0-9.$_-]*", tok):
                            seen.setdefault(w.lower(), (rel, i, ln.strip()))
                    continue
                for tok in re.findall(r"`([^`]+)`", ln):
                    for w in re.findall(r"[A-Za-z$][A-Za-z0-9.$_-]*", tok):
                        seen.setdefault(w.lower(), (rel, i, ln.strip()))
    return seen


# ----------------------------------------------------------------------------------------------------------- BASIC

BCOMP = "sdsys/gpl.bp/bcomp"
SHAPES_BASIC = "docs:tools/syntax-shapes.txt"
NO_SUCH_THING = {"ERRMSG"}          # mksyntax.py: in a table, with no opcode behind it; compiles for nobody
ARITY = {"in.none": 0, "in.one": 1, "in.two": 2, "in.three": 3, "in.four": 4, "in.five": 5}
WORD = re.compile(r'"([A-Z][A-Z0-9.$]*)"')


def strip_comment(s):
    return re.split(r";\s*\*", s, maxsplit=1)[0]


def scrub_comment(s):
    """A source comment made fit for the pack: the author's date stamp and the other product's item numbers (how this project is
    developed, not what the language does) are taken off the front."""
    s = s.strip().lstrip("*; ").strip()
    s = re.sub(r"^\d{1,2} [A-Z][a-z]{2} \d{2}\s+(?:dm\s*)?-?\s*", "", s)
    s = re.sub(r"^openQM (?:item )?\d+(?:\s*(?:/|and|,)\s*\d+)*\s*:?\s*-?\s*", "", s)
    return clean(s)


def bcomp_table(ctx, name):
    """{NAME: first line number} of the names in one of bcomp's tables (initialiser and appends); the same matcher the docs'
    mksyntax.py and docmap.py use, with the trailing comments taken off first."""
    got = {}
    for i, ln in enumerate(ctx.lines(BCOMP), 1):
        s = ln.strip()
        if s.startswith("*"):
            continue
        if re.match(re.escape(name) + r"\s*(<[^>]*>)?\s*:?=", s):
            for w in WORD.findall(strip_comment(s)):
                got.setdefault(w, i)
    if not got:
        raise SystemExit("mkpack: bcomp table %s is empty or gone - refusing to build from nothing" % name)
    return got


def bcomp_ordered(ctx, prefix):
    out = []
    pat = re.compile(r'^' + re.escape(prefix) + r'\s*(?:<-1>)?\s*=\s*"([A-Z][A-Z0-9.$]*)"')
    for i, ln in enumerate(ctx.lines(BCOMP), 1):
        s = ln.strip()
        if s.startswith("*"):
            continue
        m = pat.match(s)
        if m:
            out.append((m.group(1), i))
    return out


def bcomp_handlers(ctx, start):
    out = []
    ls = ctx.lines(BCOMP)
    i = start
    while i < len(ls):
        s = ls[i].strip()
        m = re.match(r"(?:on i goto\s+)?(in\.[a-z0-9.]+)\s*,?\s*;\*\s*(\S+)", s)
        if m:
            out.append((m.group(1), m.group(2)))
        elif out:
            break
        i += 1
    return out


def xfun_rows(ctx):
    """NAME -> (function number, arguments written, optional last argument, multivalued) from bcomp's xfun.rows."""
    text = "\n".join(ln for ln in ctx.lines(BCOMP) if re.match(r"\s*xfun\.rows\s*:?=", ln))
    return {m.group(1): (int(m.group(2)), int(m.group(3)), m.group(4), int(m.group(5)))
            for m in re.finditer(r'"([A-Z0-9.]+),(\d+),(\d+),(\d*),([01])"', text)}


def basic_chunks(ctx, since, mentions):
    out = []
    STATEMENTS = bcomp_table(ctx, "statements")
    for k, v in bcomp_table(ctx, "non.debug.statements").items():
        STATEMENTS.setdefault(k, v)
    RESTRICTED = bcomp_table(ctx, "restricted.statements")
    RESERVED = bcomp_table(ctx, "reserved.names")
    INTRINSICS = bcomp_table(ctx, "intrinsics")
    INTERNAL = bcomp_table(ctx, "int.intrinsics")
    pub = bcomp_ordered(ctx, "intrinsics")
    internal = bcomp_ordered(ctx, "int.intrinsics")
    ls = ctx.lines(BCOMP)
    starts = [n for n, ln in enumerate(ls) if "on i goto" in ln and "in." in ln]
    if len(starts) < 2:
        raise SystemExit("mkpack: cannot find bcomp's two intrinsic dispatch blocks - refusing")
    hp = bcomp_handlers(ctx, starts[1])
    hi = bcomp_handlers(ctx, starts[0])
    if len(pub) != len(hp) or len(internal) != len(hi):
        raise SystemExit("mkpack: bcomp's intrinsic name lists and dispatch lists are %d/%d and %d/%d: they are positional and have drifted" %
                         (len(pub), len(hp), len(internal), len(hi)))
    xr = xfun_rows(ctx)
    derived = {}
    for (name, _l), (hnd, _c) in list(zip(pub, hp)) + list(zip(internal, hi)):
        if hnd in ARITY:
            n = ARITY[hnd]
            derived[name] = "`%s(`%s`)`" % (name.lower(), ", ".join("*%s*" % "abcde"[i] for i in range(n))) if n else "`%s()`" % name.lower()
        elif hnd == "in.xfun" and name in xr:
            _sel, argc, opt, _mv = xr[name]
            args = ["*%s*" % "abcde"[i] for i in range(argc)]
            if opt and args:
                args[-1] = "{*%s*}" % "abcde"[argc - 1]
            derived[name] = "`%s(`%s`)`" % (name.lower(), ", ".join(args)) if args else "`%s()`" % name.lower()
    shapes = read_shapes(ctx, SHAPES_BASIC, False)
    missing = []

    def shape_of(name):
        if name in shapes:
            return shapes[name][0], ctx.src(SHAPES_BASIC, shapes[name][1])
        if name in derived:
            return derived[name], None
        missing.append(name)
        return None, None

    # statements, restricted statements and clause words; then the functions
    for name in sorted(set(STATEMENTS) | set(RESTRICTED) | set(RESERVED)):
        if name in RESTRICTED:
            kind, line = "basic.restricted", RESTRICTED[name]
        elif name in STATEMENTS:
            kind, line = "basic.statement", STATEMENTS[name]
        else:
            kind, line = "basic.clause", RESERVED[name]
        if name in NO_SUCH_THING:
            kind = "basic.nothing"
        shp, shp_src = shape_of(name)
        srcs = [ctx.src(BCOMP, line)] + ([shp_src] if shp_src else [])
        body = [shp or "(no syntax line yet in the docs' syntax-shapes.txt)", ""]
        body.append({"basic.statement": "- a statement of SD BASIC",
                     "basic.restricted": "- a RESTRICTED statement: it compiles only in a program with `$internal`, which an ordinary account cannot make; an ordinary program is told \"Unrecognised statement\"",
                     "basic.clause": "- a word that belongs inside another statement's syntax, not a statement of its own",
                     "basic.nothing": "- in the compiler's table with no opcode behind it: it compiles for nobody"}[kind])
        m = mentions.get(name.lower())
        if m:
            body.append("- docs: `%s` line %d" % (m[0][5:], m[1]))
        out.append(Chunk("basic:stmt:" + name.lower(), kind, "reference", since.of(name), srcs, "\n".join(body), "basic-statements"))
    for name in sorted(set(INTRINSICS) | set(INTERNAL)):
        internal_only = name in INTERNAL and name not in INTRINSICS
        kind = "basic.internal" if internal_only else "basic.function"
        line = INTERNAL[name] if internal_only else INTRINSICS[name]
        shp, shp_src = shape_of(name)
        srcs = [ctx.src(BCOMP, line)] + ([shp_src] if shp_src else [])
        body = [shp or "(no syntax line yet in the docs' syntax-shapes.txt)", ""]
        body.append("- an INTERNAL-only function: it compiles only in a program with `$internal`; elsewhere the compiler reads the name as a matrix" if internal_only
                    else "- a function of SD BASIC")
        if name in xr:
            sel, argc, opt, mv = xr[name]
            body.append("- extended function %d: %d argument%s written%s%s" % (sel, argc, "" if argc == 1 else "s", ", the last optional" if opt else "", ", multivalued" if mv else ""))
        m = mentions.get(name.lower())
        if m:
            body.append("- docs: `%s` line %d" % (m[0][5:], m[1]))
        out.append(Chunk("basic:func:" + name.lower(), kind, "reference", since.of(name), srcs, "\n".join(body), "basic-functions"))
    return out, sorted(set(missing))


def mode_chunks(ctx, since, mentions):
    """$MODE names (bit positions in bcomp's mode.names) and OPTION names (the list in gpl.bp/option, with the message that describes each)."""
    out = []
    pos = []
    cur = 0                                  # the position the next appended name takes: an empty `:= @VM` keeps a place for a retired name
    for i, ln in enumerate(ctx.lines(BCOMP), 1):
        s = strip_comment(ln.strip())
        if s.startswith("*"):
            continue
        m = re.match(r'mode\.names\s*=\s*"([A-Z0-9.$]+)"', s)
        if m:
            cur = 1
            pos.append((m.group(1), i, cur))
            continue
        m = re.match(r'mode\.names\s*:=\s*@VM\s*:\s*"([A-Z0-9.$]+)"', s)
        if m:
            cur += 1
            pos.append((m.group(1), i, cur))
            continue
        if re.match(r"mode\.names\s*:=\s*@VM\s*$", s):
            cur += 1
            continue
        m = re.match(r'mode\.names<1,(\d+)>\s*=\s*"([A-Z0-9.$]+)"', s)
        if m:
            cur = max(cur, int(m.group(1)))
            pos.append((m.group(2), i, int(m.group(1))))
    if len(pos) < 6:                                 # 27 Oct 26: 11 modes since S.87 batch 17 (30+ before the modes of other products went)
        raise SystemExit("mkpack: only %d $MODE names found in bcomp - refusing" % len(pos))
    # what each bit is for: the comment on bcomp's  $define M.NAME bit  /  $define M2.NAME bit  lines (keyed by the bit)
    why = {}
    for i, ln in enumerate(ctx.lines(BCOMP), 1):
        m = re.match(r"\$define (M2?)\.(\S+)\s+(\d+)\s*;?\s*(?:;\*)?\s*(.*)$", ln.strip())
        if m:
            why[(m.group(1), int(m.group(3)))] = (scrub_comment(m.group(4)), i)
    for name, line, p in sorted(pos, key=lambda t: t[2]):
        which, bitno = ("M", p - 1) if p <= 32 else ("M2", p - 33)
        bit = ("bit %d of mode" % bitno) if which == "M" else ("bit %d of mode2" % bitno)
        body = ["`$mode %s` - %s" % (name.lower(), bit), "", "- set with `$mode name` or `$mode name, name` in a program; some names also work in `$basic.options`"]
        w = why.get((which, bitno))
        srcs_extra = []
        if w and w[0]:
            body.append("- what it does (bcomp's comment on the define): %s" % w[0])
            srcs_extra.append(ctx.src(BCOMP, w[1]))
        m = mentions.get(name.lower())
        if m:
            body.append("- docs: `%s` line %d" % (m[0][5:], m[1]))
        out.append(Chunk("basic:mode:" + name.lower(), "basic.mode", "reference", since.of(name), [ctx.src(BCOMP, line)] + srcs_extra, "\n".join(body), "basic-modes"))
    opt_rel = "sdsys/gpl.bp/option"
    nopt = 0
    for i, ln in enumerate(ctx.lines(opt_rel), 1):
        m = re.match(r"\s*opt<-1>\s*=\s*'([A-Z0-9.$]+)\|([A-Z]*)\|(\d+)'", ln)
        if not m:
            continue
        nopt += 1
        name, flag, msg = m.group(1), m.group(2), m.group(3)
        srcs = [ctx.src(opt_rel, i)]
        body = ["`option %s` {on | off | display}" % name.lower(), ""]
        if flag:
            body.append("- belongs to the option group `%s` (`option %s on|off` sets the whole group)" % ({"W": "sdbasic.warnings"}.get(flag, flag.lower()),
                                                                                                  {"W": "sdbasic.warnings"}.get(flag, flag.lower())))
        mrel = "sdsys/messages/" + msg
        if ctx.exists(mrel):
            body.append("- what it does (message %s): %s" % (msg, clean(" ".join(ctx.lines(mrel)))))
            srcs.append(ctx.src(mrel, 1))
        m2 = mentions.get(name.lower())
        if m2:
            body.append("- docs: `%s` line %d" % (m2[0][5:], m2[1]))
        out.append(Chunk("basic:option:" + name.lower(), "basic.option", "reference", since.of(name), srcs, "\n".join(body), "basic-modes"))
    if nopt < 6:                                    # 27 Oct 26: 15 option words since 6 more were removed (batch 16; 28 after batch 7; the 22 that imitated other products went before; blank rows are not counted); 61 at the start
        raise SystemExit("mkpack: only %d OPTION names found in gpl.bp/option - refusing" % nopt)
    return out


# ----------------------------------------------------------------------------------------------------------- dictionaries

D33 = "docs:User/markdown/33-sd-dicts-structure.md"
D33A = "docs:User/markdown/33a-sd-dicts-in-use.md"
D34 = "docs:User/markdown/34-sd-dicts-conversions.md"
D34A = "docs:User/markdown/34a-sd-dicts-formats-and-expressions.md"


def slug(s):
    s = re.sub(r"[`*_]", "", s).lower()
    s = re.sub(r"[^a-z0-9]+", "-", s).strip("-")
    return s[:40].strip("-") or "section"


def sec_chunk(ctx, d, cid, kind, pattern, group, since="-", with_children=False, tier="reference"):
    h, body, ln = d.section(pattern, with_children=with_children)
    return Chunk(cid, kind, tier, since, [ctx.src(d.rel, ln)], "**%s**\n\n%s" % (h, body), group)


def children(d, pattern):
    """The level-3 headings under the level-2 heading that matches: [(heading text, lineno)]."""
    k = d.find(pattern)
    lvl = d.heads[k][0]
    out = []
    for lvl2, text, ln in d.heads[k + 1:]:
        if lvl2 <= lvl:
            break
        if lvl2 == lvl + 1:
            out.append((text, ln))
    return out


def table_rows(lines, start, end):
    """The cells of the markdown table rows between two line numbers (1-based, end exclusive), header and rule rows left out."""
    rows = []
    for i in range(start - 1, min(end - 1, len(lines))):
        ln = lines[i]
        if ln.startswith("|") and not re.match(r"^\|[\s:|-]+\|?$", ln):
            rows.append((i + 1, [c.strip() for c in ln.strip().strip("|").split("|")]))
    return rows[1:] if rows else rows


def dict_chunks(ctx, since):
    out = []
    d33, d34, d34a, d33a = DocSections(ctx, D33), DocSections(ctx, D34), DocSections(ctx, D34A), DocSections(ctx, D33A)
    out.append(sec_chunk(ctx, d33, "dict:what", "dict.overview", r"^What a dictionary is", "dict"))
    out.append(sec_chunk(ctx, d33a, "dict:use", "dict.overview", r"^How the query processor uses the dictionary", "dict", with_children=True))
    out.append(sec_chunk(ctx, d33a, "dict:system", "dict.overview", r"^The system dictionaries", "dict"))
    # the roster of item types is the first column of the docs' table of types; each type is that row and, where there is one, its section
    h, tbody, tln = d33.section(r"^The dictionary record types")
    k = d33.find(r"^The dictionary record types")
    end = d33.heads[k + 1][2] if k + 1 < len(d33.heads) else len(d33.lines) + 1
    rows = table_rows(d33.lines, tln, end)
    letters = []
    for ln, cells in rows:
        m = re.match(r"^`([A-Z]+)`$", cells[0])
        if m and len(cells) >= 3:
            letters.append((m.group(1), cells, ln))
    if len(letters) < 6:
        raise SystemExit("mkpack: the docs' table of dictionary record types gave %d types - refusing" % len(letters))
    out.append(Chunk("dict:types", "dict.types", "reference", "-", [ctx.src(D33, tln)], "**%s**\n\n%s" % (h, tbody), "dict"))
    own = {"D": r"^The D record", "I": r"^The I record", "C": r"^The C record", "PH": r"^The PH record",
           "L": r"^The L record", "X": r"^The X record"}
    for letter, cells, ln in letters:
        row = "| " + " | ".join(cells) + " |"
        srcs = [ctx.src(D33, ln)]
        body = ["Dictionary record type `%s` - %s: %s" % (letter, cells[1], md_links_plain(cells[2])), "", "Field 1 of the dictionary record starts with `%s`." % letter]
        if letter in own:
            h2, b2, ln2 = d33.section(own[letter], with_children=True)
            body += ["", "**%s**" % h2, "", b2]
            srcs.append(ctx.src(D33, ln2))
        elif letter == "E":
            body += ["", "`E` is laid out like `D`, but field 2 is the path of an element of a data collection record instead of a field number: see dict:type:D and the collection files page."]
        out.append(Chunk("dict:type:" + letter, "dict.type", "reference", "-", srcs, "\n".join(body), "dict"))
    # formats, I-type expressions and the rest of 34a: one chunk for each section, ids from the headings
    for top, base, kind in ((r"^Format specifications", "dict:format", "dict.format"), (r"^I-type expressions", "dict:itype", "dict.itype")):
        h, b, ln = d34a.section(top)
        out.append(Chunk(base, kind, "reference", "-", [ctx.src(D34A, ln)], "**%s**\n\n%s" % (h, b), "dict"))
        for text, cln in children(d34a, top):
            hh, bb, ln2 = d34a.section("^" + re.escape(text) + "$")
            out.append(Chunk("%s:%s" % (base, slug(text)), kind, "reference", "-", [ctx.src(D34A, ln2)], "**%s**\n\n%s" % (hh, bb), "dict"))
    for pat, cid, kind in ((r"^Correlatives", "dict:correlative", "dict.correlative"), (r"^Chaining conversions", "dict:chaining", "dict.conv"),
                           (r"^Input and output conversion", "dict:io-conversion", "dict.conv")):
        out.append(sec_chunk(ctx, d34a, cid, kind, pat, "dict"))
    # conversion codes: one chunk for each level-3 heading of "Conversion codes - field 3"; the codes are the capitals after the dash
    h, b, ln = d34.section(r"^Conversion codes")
    out.append(Chunk("dict:conv", "dict.conv", "reference", "-", [ctx.src(D34, ln)], "**%s**\n\n%s" % (h, b), "dict"))
    taken = set()
    for text, cln in children(d34, r"^Conversion codes"):
        hh, bb, ln2 = d34.section("^" + re.escape(text) + "$")
        after = text.split("—", 1)[1] if "—" in text else ""
        codes = [c.strip("` ") for c in after.split(",") if re.match(r"^`?[A-Z][A-Z0-9]*`?$", c.strip())]
        first = codes[0] if codes else slug(text)
        if first in taken:
            first = re.split(r"\s", text)[0].upper().strip("`")
        taken.add(first)
        out.append(Chunk("dict:conv:" + first, "dict.conv.code", "reference", "-", [ctx.src(D34, ln2)], "**%s**\n\n%s" % (hh, bb), "dict"))
        for c in codes[1:]:
            if c in taken:
                continue
            taken.add(c)
            out.append(Chunk("dict:conv:" + c, "dict.conv.code", "reference", "-", [ctx.src(D34, ln2)],
                             "Conversion code `%s` is described with the codes of **%s**: see dict:conv:%s." % (c, hh, first), "dict"))
    # the shipped dictionaries' items, verbatim (examples)
    base = "gplbld/FILES_DICTS"
    n = 0
    for fn in ctx.listdir(base):
        if "^" not in fn:
            continue
        dname, item = fn.split("^", 1)
        rel = "%s/%s" % (base, fn)
        raw = ctx.text(rel).rstrip("\n")
        first = raw.split("\n", 1)[0].strip()
        typ = first[:2] if first[:2] == "PH" else first[:1]
        body = "Item `%s` of the shipped dictionary `%s` (type %s), in `%s`:\n\n%s" % (item, dname, typ, rel, fence(clean(raw)))
        out.append(Chunk("dict:item:%s:%s" % (dname, item), "dict.item", "examples", "-", [ctx.src(rel, 1)], body, "dict-items"))
        n += 1
    if n < 40:
        raise SystemExit("mkpack: only %d shipped dictionary items found - refusing" % n)
    return out


# ----------------------------------------------------------------------------------------------------------- the system

def syntax_block(ctx, rel, anchor_rx):
    """The contiguous run of crt '...' lines that begins at the first crt line matching anchor_rx: [(lineno, text)]."""
    ls = ctx.lines(rel)
    out = []
    for i, ln in enumerate(ls, 1):
        m = re.match(r"\s*crt '(.*)'\s*(?:;\*.*)?$", ln)
        if not out:
            if m and re.search(anchor_rx, m.group(1)):
                out.append((i, m.group(1)))
        else:
            if m:
                out.append((i, m.group(1)))
            else:
                break
    return out


def word_descriptions(ctx):
    """WORD -> (description, lineno) from the START-DESCRIPTION block of createa, whose lines read  *     WORD, WORD   what it does."""
    rel = "sdsys/gpl.bp/createa"
    out = {}
    for i, ln in enumerate(ctx.lines(rel), 1):
        m = re.match(r"^\*     ([A-Z][A-Z-]+(?:, [A-Z][A-Z-]+)*(?: \(\d+ \w+ \d+, S\.\d+\))?)\s{2,}(.*)$", ln)
        if m:
            d = re.sub(r"^\(\d+ \w+ \d+, S\.\d+\)\s*", "", m.group(2)).strip()
            for w in re.findall(r"[A-Z][A-Z-]+", m.group(1).split("(")[0]):
                out[w.lower()] = (scrub_comment(d), i)
    return out


def system_chunks(ctx, since, mentions):
    out = []
    # the words CREATE.ACCOUNT and MODIFY.ACCOUNT take: the syntax the verbs print is the truth (createa's own header says so)
    cblock = syntax_block(ctx, "sdsys/gpl.bp/createa", r"^Command Syntax:\s+create\.account")
    mblock = syntax_block(ctx, "sdsys/gpl.bp/modifya", r"^Command Syntax:\s+modify\.account")
    mwords = syntax_block(ctx, "sdsys/gpl.bp/modifya", r"^modify\.account Action Must Be")
    if not cblock or not mblock or not mwords:
        raise SystemExit("mkpack: the syntax lines of create.account or modify.account are not where they were - refusing")
    cwords = {w for _l, t in cblock for w in re.findall(r"(?<![a-z.])([a-z]+(?:-[a-z]+)+)", t)}
    words_text = " ".join(t for _l, t in mwords)
    mw = re.findall(r"[a-z][a-z-]*", words_text.split("Must Be", 1)[1])
    mw = [w for w in mw if w not in ("or",)]
    desc = word_descriptions(ctx)
    for w in sorted(set(mw)):
        srcs = [ctx.src("sdsys/gpl.bp/modifya", mwords[0][0])]
        verbs = ["`modify.account <account> %s`" % w]
        if w in cwords or w in ("ssh", "api", "both", "none"):
            verbs.append("`create.account user <name> %s`" % w)
            srcs.append(ctx.src("sdsys/gpl.bp/createa", cblock[0][0]))
        body = ["Account word `%s`" % w, "", "- typed by the administrator (SDSYS) only: " + "; ".join(verbs)]
        base = w[:-3] if w.endswith(("-on", "-off")) else w
        if w.endswith("-on"):
            body.append("- turns the `%s` gate ON for the account; the delivered default is OFF (high security is delivered, the administrator loosens it)" % base)
        elif w.endswith("-off"):
            body.append("- turns the `%s` gate OFF for the account" % base)
        dd = desc.get(w) or desc.get(base)
        if dd:
            body.append("- what it is (createa's description): %s" % dd[0])
            srcs.append(ctx.src("sdsys/gpl.bp/createa", dd[1]))
        m = mentions.get(w)
        if m:
            body.append("- docs: `%s` line %d" % (m[0][5:], m[1]))
        out.append(Chunk("sys:word:" + w, "sys.word", "reference", since.of(w), srcs, "\n".join(body), "system"))
    out.append(Chunk("sys:syntax:accounts", "sys.syntax", "reference", "-", [ctx.src("sdsys/gpl.bp/createa", cblock[0][0]), ctx.src("sdsys/gpl.bp/modifya", mblock[0][0])],
                     "What `create.account` prints when typed with no arguments:\n\n%s\n\nWhat `modify.account` prints:\n\n%s" % (
                         fence("\n".join(t for _l, t in cblock)), fence("\n".join(t for _l, t in mblock))), "system"))
    # sd.conf parameters: the branches of config.c's read chain, with the range check where there is one
    rel = "gplsrc/config.c"
    cl = ctx.lines(rel)
    pr = re.compile(r'(?:sscanf\(rec, "|strncmp\(rec, ")([A-Z][A-Z0-9_]*)=')
    ranges = {}
    for ln in cl:
        for m in re.finditer(r'rangecheck\("([A-Z0-9_]+)",[^,]+,\s*([-0-9A-Z_]+),\s*([-0-9A-Z_]+)', ln):
            ranges[m.group(1)] = (m.group(2), m.group(3))
    shipped = {}
    if ctx.exists("sd.conf"):
        for i, ln in enumerate(ctx.lines("sd.conf"), 1):
            m = re.match(r"^([A-Z][A-Z0-9_]*)=(.*)$", ln.strip())
            if m:
                shipped[m.group(1)] = (m.group(2), i)
    seen = set()
    for i, ln in enumerate(cl, 1):
        m = pr.search(ln)
        if not m or m.group(1) in seen:
            continue
        name = m.group(1)
        seen.add(name)
        srcs = [ctx.src(rel, i)]
        body = ["`%s=` in the `[sd]` section of `sd.conf`" % name, ""]
        if name in ranges:
            body.append("- accepted range: %s to %s (a value outside it stops SD starting)" % ranges[name])
        if name in shipped:
            body.append("- the shipped `sd.conf` sets `%s=%s`" % (name, shipped[name][0]))
            srcs.append(ctx.src("sd.conf", shipped[name][1]))
        mm = mentions.get(name.lower())
        if mm:
            body.append("- docs: `%s` line %d" % (mm[0][5:], mm[1]))
        out.append(Chunk("sys:param:" + name.lower(), "sys.param", "reference", since.of(name), srcs, "\n".join(body), "system"))
    if len(seen) < 30:
        raise SystemExit("mkpack: only %d sd.conf parameters found in config.c - refusing" % len(seen))
    # the key and error-code headers, one chunk for each prefix (FL$, ACC$, K$ ...)
    for rel, label, vis in (("sdsys/syscom/keys.h", "keys.h", "an ordinary program may include it"),
                            ("sdsys/gpl.bp/int$keys.h", "int$keys.h", "internal programs only (`$internal`)"),
                            ("sdsys/syscom/err.h", "err.h", "error codes: STATUS() after a failed statement, and the return codes of the verbs")):
        groups = {}
        order = []
        for i, ln in enumerate(ctx.lines(rel), 1):
            m = re.match(r"\s*\$define\s+([A-Za-z0-9_.]+\$)([A-Za-z0-9_.$]*)\s+(\S+)\s*(?:;\*\s*(.*))?$", ln)
            if not m:
                continue
            pre = m.group(1)
            if pre not in groups:
                groups[pre] = []
                order.append(pre)
            groups[pre].append((i, m.group(1) + m.group(2), m.group(3), scrub_comment(m.group(4) or "")))
        for pre in order:
            rows = groups[pre]
            body = ["Constants beginning `%s` in `%s` (%s):" % (pre, rel, vis), ""]
            body += ["- `%s` = %s%s" % (n, v, (" - " + c) if c else "") for _l, n, v, c in rows]
            cid = "sys:%s:%s" % ({"keys.h": "keys", "int$keys.h": "ikeys", "err.h": "err"}[label], pre.lower())
            out.append(Chunk(cid, "sys.keys", "reference", "-", [ctx.src(rel, rows[0][0])], "\n".join(body), "system-keys"))
    # the release history: the changelog's own section headings
    rel = "sdsys/changelog"
    heads = []
    for i, ln in enumerate(ctx.lines(rel), 1):
        if re.match(r"^(Next release\b|L\d+\.\d+-\d+\s+-\s|Version\s+\S+)", ln):
            heads.append((i, ln.strip()))
    body = ["The sections of `sdsys/changelog`, newest first (the first is the tree you are reading; entries inside a section are not listed here):", ""]
    body += ["- %s" % h for _i, h in heads[:12]]
    if len(heads) > 12:
        body.append("- and %d older sections, back to upstream's first" % (len(heads) - 12))
    out.append(Chunk("sys:releases", "sys.releases", "reference", "-", [ctx.src(rel, heads[0][0])], "\n".join(body), "system"))
    return out


# ----------------------------------------------------------------------------------------------------------- core digests

CORE_VERB_DOCS = ("19-", "19a-", "20-", "20a-", "21-", "22-", "23-", "24-", "40-")
CORE_VERBS = 30
CORE_CONVERSIONS = 12


def verb_usage(ctx, verbs):
    """verb -> number of times the User pages 19-24 and the tutorial use it inside a backtick span or a fenced block."""
    counts = {v: 0 for v in verbs}
    rx = re.compile(r"[A-Za-z$!][A-Za-z0-9.$!]*|!")
    for n in ctx.listdir("docs:User/markdown"):
        if not n.startswith(CORE_VERB_DOCS) or not n.endswith(".md"):
            continue
        in_fence = False
        for ln in ctx.lines("docs:User/markdown/" + n):
            if ln.startswith("```"):
                in_fence = not in_fence
                continue
            spans = [ln] if in_fence else re.findall(r"`([^`]+)`", ln)
            for sp in spans:
                for w in rx.findall(sp):
                    w = w.lower()
                    if w in counts:
                        counts[w] += 1
    return counts


def first_table(text):
    """The first markdown table of a text (header, rule and rows) as a list of lines."""
    out = []
    for ln in text.split("\n"):
        if ln.startswith("|"):
            out.append(ln)
        elif out:
            break
    return out


def core_chunks(ctx, voc, since, shapes, chunks_so_far):
    out = []
    # 1. the verbs most used by the docs' own examples, each as its syntax line only
    verbs = voc.verbs()
    usage = verb_usage(ctx, verbs)
    top = sorted((v for v in verbs if usage[v] > 0), key=lambda v: (-usage[v], v))[:CORE_VERBS]
    if len(top) < CORE_VERBS:
        raise SystemExit("mkpack: the docs use only %d verbs in their examples - refusing" % len(top))
    body = ["The %d verbs the User pages 19-24 and the tutorial use most (counted in their examples), each as its syntax line; a verb's full chunk is `tcl:<verb>`." % CORE_VERBS, ""]
    body += ["- %s" % shapes[v][0] for v in sorted(top)]
    out.append(Chunk("core:tcl-verbs", "core.digest", "core", "-", [ctx.src("docs:tools/tcl-syntax-shapes.txt", shapes[sorted(top)[0]][1])], "\n".join(body), "core"))
    # 2. the ten VOC record types
    d32 = DocSections(ctx, VOC_TYPE_DOC)
    h, b, ln = d32.section(r"^The ten record types")
    out.append(Chunk("core:voc-types", "core.digest", "core", "-", [ctx.src(VOC_TYPE_DOC, ln)],
                     "The VOC record types (field 1, character 1, is the type). Each type is the chunk `voc:type:<T>`.\n\n" + "\n".join(first_table(b)), "core"))
    # 3. the dictionary item types and the D layout
    d33 = DocSections(ctx, D33)
    h, b, ln = d33.section(r"^The dictionary record types")
    parts = ["The dictionary item types (field 1 starts with the letter). Each type is the chunk `dict:type:<T>`.", "", "\n".join(first_table(b))]
    for letter in ("D",):
        h2, b2, ln2 = d33.section(r"^The %s record" % letter, with_children=True)
        t = first_table(b2)
        if t:
            parts += ["", "**%s - fields**" % h2, "", "\n".join(t)]
    out.append(Chunk("core:dict-types", "core.digest", "core", "-", [ctx.src(D33, ln)], "\n".join(parts), "core"))
    # 4. the conversion codes the docs' examples use most
    codes = [c.id[len("dict:conv:"):] for c in chunks_so_far if c.id.startswith("dict:conv:") and c.kind == "dict.conv.code" and re.match(r"^[A-Z][A-Z0-9]*$", c.id[len("dict:conv:"):])]
    alias = {}                                                # a code that shares another's section counts toward that section
    for c in chunks_so_far:
        m = re.search(r"see dict:conv:(\S+)\.$", c.body)
        if c.id.startswith("dict:conv:") and m:
            alias[c.id[len("dict:conv:"):]] = m.group(1)
    usage_c = {c: 0 for c in codes}
    for n in ctx.listdir("docs:User/markdown"):
        if n.startswith("34") or not n.endswith(".md"):
            continue
        in_fence = False
        for l in ctx.lines("docs:User/markdown/" + n):
            if l.startswith("```"):
                in_fence = not in_fence
                continue
            hay = [l] if in_fence else re.findall(r"`([^`]+)`", l)
            for sp in hay:
                for c in codes:
                    usage_c[alias.get(c, c)] = usage_c.get(alias.get(c, c), 0) + len(re.findall(r"(?<![A-Za-z0-9])" + c + r"(?=[0-9\"'\s/,;{*-]|$)", sp))
    topc = sorted((c for c in codes if c not in alias and usage_c.get(c, 0) > 0), key=lambda c: (-usage_c[c], c))[:CORE_CONVERSIONS]
    byid = {c.id: c for c in chunks_so_far}
    body = ["The %d conversion codes the docs' examples use most (field 3 of a dictionary item, and the second argument of `oconv()` and `iconv()`); every code is the chunk `dict:conv:<CODE>`." % len(topc), ""]
    srcs = []
    for c in sorted(topc):
        ch = byid["dict:conv:" + c]
        title = ch.body.split("\n", 1)[0].strip("*")
        body.append("- `%s` - %s" % (c, title))
        if not srcs:
            srcs = [ch.srcs[0]]
    out.append(Chunk("core:conversions", "core.digest", "core", "-", srcs, "\n".join(body), "core"))
    # 5. the gates: the words, as the verbs print them
    cblock = syntax_block(ctx, "sdsys/gpl.bp/createa", r"^Command Syntax:\s+create\.account")
    out.append(Chunk("core:gates", "core.digest", "core", "-", [ctx.src("sdsys/gpl.bp/createa", cblock[0][0])],
                     "A new user account starts with every gate OFF. Only SDSYS, the one administrator, turns one on, with these words (`create.account`, then "
                     "`modify.account <account> <word>`). Each word is the chunk `sys:word:<word>`. This is what `create.account` prints:\n\n%s" % fence("\n".join(t for _l, t in cblock)), "core"))
    # 6. start here (hand-written, in agent-pack/core-start.md, and embedded whole)
    rel = "agent-pack/core-start.md"
    if ctx.exists(rel):
        out.append(Chunk("core:start", "core.start", "core", "-", [ctx.src(rel, 1)], "\n".join(ctx.lines(rel)), "core"))
    return out


# ----------------------------------------------------------------------------------------------------------- messages

def message_citations(ctx):
    """message number -> sorted programs of gpl.bp that cite it with sysmsg(N...) outside comments."""
    cites = {}
    rx = re.compile(r"sysmsg\(\s*(\d+)")
    for name in ctx.listdir("sdsys/gpl.bp"):
        rel = "sdsys/gpl.bp/" + name
        for ln in ctx.lines(rel):
            s = ln.lstrip()
            if s.startswith("*") or s.startswith("!"):
                continue
            code = re.split(r";\s*\*", ln, maxsplit=1)[0]
            for m in rx.finditer(code):
                cites.setdefault(m.group(1), set()).add(name)
    return cites


def message_chunks(ctx, since):
    out = []
    cites = message_citations(ctx)
    for n in ctx.listdir("sdsys/messages"):
        if not n.isdigit():
            continue
        rel = "sdsys/messages/" + n
        text = ctx.text(rel).rstrip("\n")
        progs = sorted(cites.get(n, ()))
        lines = [fence(clean(text))]
        if progs:
            lines.append("")
            lines.append("cited by: %s%s" % (", ".join("`%s`" % p for p in progs[:8]), " and %d more" % (len(progs) - 8) if len(progs) > 8 else ""))
        out.append(Chunk("msg:" + n, "message", "reference", "-", [ctx.src(rel, 1)], "\n".join(lines), "messages"))
    return out


# ----------------------------------------------------------------------------------------------------------- assembly

def build_chunks(ctx):
    since = Since(ctx)
    voc = Voc(ctx)
    mentions = docs_mentions(ctx)
    notes = {}
    chunks = []
    tcl, shapes = tcl_chunks(ctx, voc, since)
    chunks += tcl
    chunks += keyword_chunks(ctx, voc, since)
    chunks += voc_chunks(ctx, voc, since)
    chunks += voc_entry_examples(ctx, voc, since)
    basic, missing = basic_chunks(ctx, since, mentions)
    chunks += basic
    notes["basic_names_without_a_docs_syntax_line"] = missing
    chunks += mode_chunks(ctx, since, mentions)
    chunks += dict_chunks(ctx, since)
    chunks += system_chunks(ctx, since, docs_mentions(ctx, ("Administrator", "User")))
    chunks += message_chunks(ctx, since)
    chunks += core_chunks(ctx, voc, since, shapes, chunks)
    return chunks, notes


PART_TITLES = {
    "core": ("core.md", "Core: the always-loaded digest"),
    "tcl-verbs": ("reference/tcl-verbs.md", "TCL verbs"),
    "tcl-keywords": ("reference/tcl-keywords.md", "Query-processor and command-line keywords"),
    "voc": ("reference/voc.md", "The VOC: record types and layers"),
    "voc-entries": ("examples/voc-entries.md", "Shipped VOC records, verbatim"),
    "basic-statements": ("reference/basic-statements.md", "SD BASIC statements, clause words and restricted statements"),
    "basic-functions": ("reference/basic-functions.md", "SD BASIC functions"),
    "basic-modes": ("reference/basic-modes.md", "SD BASIC $MODE names and OPTION names"),
    "dict": ("reference/dictionaries.md", "Dictionaries: item types, formats, I-types and conversion codes"),
    "dict-items": ("examples/dictionary-items.md", "Shipped dictionary items, verbatim"),
    "system": ("reference/system.md", "Account words and gates, sd.conf parameters, releases"),
    "system-keys": ("reference/system-keys.md", "Key and error-code constants"),
    "messages": ("reference/messages.md", "System messages"),
}


def release_info(ctx):
    stamp = None
    rel = "sdsys/gpl.bp/revstamp.h"
    m = re.search(r'(?m)^\$define SD\.REV\.STAMP\s+"([^"]+)"', ctx.text(rel))
    if m:
        stamp = m.group(1)
    rec = ctx.lines("sdsys/newvoc/$release")
    return stamp, (rec[1].strip() if len(rec) > 1 else None)


def build(tree, docs, product="SD Core for Windows"):
    """The whole pack as {relative path: bytes}; nothing is written."""
    for need in ("sdsys/newvoc", "sdsys/voc_template", "sdsys/messages", "sdsys/gpl.bp", "docs:User/markdown", "docs:tools/tcl-syntax-shapes.txt"):
        if not Ctx(tree, docs).exists(need):
            raise SystemExit("mkpack: cannot find %s under %s - give --tree and --docs" % (need, docs if need.startswith("docs:") else tree))
    ctx = Ctx(tree, docs)
    chunks, notes = build_chunks(ctx)
    ids = [c.id for c in chunks]
    dup = sorted({i for i in ids if ids.count(i) > 1})
    if dup:
        raise SystemExit("mkpack: duplicate chunk ids %s" % dup[:5])
    files = {}
    parts = {}
    groups = {}
    for c in chunks:
        groups.setdefault(c.group, []).append(c)
    for g, cs in groups.items():
        part, title = PART_TITLES[g]
        cs.sort(key=lambda c: c.id)
        text = "# %s\n\nGenerated by agent-pack/mkpack.py from the sources named in each chunk. Do not edit; regenerate with `%s`.\n\n" % (title, REGEN)
        text += "\n".join(c.render() for c in cs)
        data = text.encode("utf-8")
        files[part] = data
        parts[part] = {"sha256": hashlib.sha256(normalize(data)).hexdigest(), "chunks": len(cs), "words": sum(words(c.body) for c in cs)}
    stamp, rec = release_info(ctx)
    kinds = {}
    for c in chunks:
        k = kinds.setdefault(c.kind, {"chunks": 0, "h": hashlib.sha256()})
        k["chunks"] += 1
        k["h"].update(normalize(c.render().encode("utf-8")))
    manifest = {
        "pack_format": PACK_FORMAT, "product": product, "rev_stamp": stamp, "release_record": rec,
        "development": "the changelog's 'Next release - in progress' section is part of this tree",
        "generator": "agent-pack/mkpack.py", "regenerate": REGEN,
        "since_rule": "the oldest changelog section whose entry titles name the item; only names that cannot be plain English count; '-' = not found",
        "line_numbers": "src line numbers are locators and may lag; the 8-hex hash of the cited line is the identity",
        "chunk_count": len(chunks),
        "gaps": notes,
        "kinds": {k: {"chunks": v["chunks"], "sha256": v["h"].hexdigest()} for k, v in sorted(kinds.items())},
        "parts": dict(sorted(parts.items())),
    }
    index = {c.id: {"part": PART_TITLES[c.group][0], "tier": c.tier, "kind": c.kind, "since": c.since, "words": words(c.body)} for c in chunks}
    files["index.json"] = (json.dumps({"pack_format": PACK_FORMAT, "chunks": dict(sorted(index.items()))}, indent=0, sort_keys=True) + "\n").encode("utf-8")
    parts["index.json"] = {"sha256": hashlib.sha256(files["index.json"]).hexdigest()}
    manifest["parts"] = dict(sorted(parts.items()))
    files["manifest.json"] = (json.dumps(manifest, indent=1, sort_keys=True) + "\n").encode("utf-8")
    return Built(files, chunks)


class Built:
    def __init__(self, files, chunks):
        self.files, self.chunks = files, chunks


def write_pack(files, out):
    if os.path.isdir(out):
        for root, _d, names in os.walk(out):
            for n in names:
                os.remove(os.path.join(root, n))
    for rel, data in files.items():
        p = os.path.join(out, rel)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        with open(p, "wb") as f:
            f.write(data)


def read_pack(out):
    files = {}
    if os.path.isdir(out):
        for root, _d, names in os.walk(out):
            for n in names:
                p = os.path.join(root, n)
                with open(p, "rb") as f:
                    files[os.path.relpath(p, out).replace(os.sep, "/")] = f.read()
    return files


GUIDE_REL = "agent-pack/guide/sd-basic-guide.md"
SKILL_REFS = os.path.join(HERE, "skill", "sd-core", "references")


def build_skill(files, tree):
    """The skill's references/ folder as {relative path: bytes}: the hand-written guide, and the generated pack without index.json (a
    skill is read by grep and by Claude's own reading, and the map of 3,900 chunks would only be context).  SKILL.md is hand-written
    and is not made here."""
    refs = {}
    gpath = os.path.join(tree, GUIDE_REL)
    if os.path.isfile(gpath):
        with open(gpath, "rb") as f:
            refs["guide.md"] = f.read()
    for rel, data in files.items():
        if rel != "index.json":
            refs["pack/" + rel] = data
    return refs


def main():
    ap = argparse.ArgumentParser(description=__doc__ and "Generate the SD knowledge pack.")
    ap.add_argument("--tree", default=DEFAULT_TREE)
    ap.add_argument("--docs", default=DEFAULT_DOCS)
    ap.add_argument("--out", default=DEFAULT_OUT)
    ap.add_argument("--skill", default=SKILL_REFS, help="where the Claude Code skill's references/ folder is made (the guide and the pack)")
    ap.add_argument("--no-skill", action="store_true", help="make the pack only")
    ap.add_argument("--product", default="SD Core for Windows")
    ap.add_argument("--write", action="store_true")
    ap.add_argument("--check", action="store_true")
    a = ap.parse_args()
    print("mkpack: tree  %s" % a.tree)
    print("mkpack: docs  %s" % a.docs)
    print("mkpack: out   %s" % a.out)
    if not a.no_skill:
        print("mkpack: skill %s" % a.skill)
    if not os.path.isdir(a.docs):
        print("mkpack: the docs checkout is missing: %s" % a.docs)
        sys.exit(2)
    built = build(a.tree, a.docs, a.product)
    n = len(built.chunks)
    if n == 0:
        print("mkpack: REFUSED - zero chunks is not a pack")
        sys.exit(1)
    refs = {} if a.no_skill else build_skill(built.files, a.tree)
    if not a.no_skill and "guide.md" not in refs:
        print("mkpack: REFUSED - there is no guide at %s, so the skill would be half made" % os.path.join(a.tree, GUIDE_REL))
        sys.exit(1)
    print("mkpack: %d chunks in %d files%s" % (n, len(built.files), "" if a.no_skill else ", %d files for the skill" % len(refs)))
    if a.write:
        write_pack(built.files, a.out)
        print("mkpack: wrote %s" % a.out)
        if not a.no_skill:
            write_pack(refs, a.skill)
            print("mkpack: wrote %s" % a.skill)
    if a.check:
        have = read_pack(a.out)
        same = set(have) == set(built.files) and all(normalize(have[k]) == normalize(built.files[k]) for k in have if k.endswith(".md")) \
            and have.get("manifest.json") == built.files["manifest.json"]
        print("mkpack: the committed pack %s a fresh build" % ("equals" if same else "DIFFERS FROM"))
        ok = same
        if not a.no_skill:
            hr = read_pack(a.skill)
            sk = set(hr) == set(refs) and all(normalize(hr[k]) == normalize(refs[k]) if k.endswith(".md") else hr[k] == refs[k] for k in hr)
            print("mkpack: the committed skill references %s a fresh build" % ("equal" if sk else "DIFFER FROM"))
            ok = ok and sk
        sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
