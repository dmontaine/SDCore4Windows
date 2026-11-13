#!/usr/bin/env python3
#
# test-pack-units.py - the generated knowledge pack (agent-pack/pack) against the tree and the docs it was generated from.
#                      S.69 rows 1 and 1b, the AI plan (.claude/ai-integration-evaluation.md, sections 5A.2 and 5A.7).
#
#   python sdb_ai/sd64/gplbld/test-pack-units.py [--selftest] [--docs DIR]
#
# No sudo, no install, no sd, no sandbox, no model.  Exit 0 every check held, 1 one did not, 2 the question cannot be
# answered (the docs checkout is missing).  A pack that cannot be compared is never a pass.
#
# START-HISTORY:
# 19 Oct 26 dm  Written FIRST, before agent-pack/mkpack.py existed, and run red (see PROJECT_STATUS S.69): the pack is generated
#               from the sources and this fails when it and they disagree, which is the owner's "a new AI does not start from
#               scratch" made honest - a stale pack is worse than none.
# 13 Nov 26 Windows port - from Linux b1d496df (RELEASE_1.1 253a): the docs checkout is the sibling SDCore4WindowsDocs, and the
#               command is "python".  Check 8's sandbox half (sandbox-guide.py) is not carried: the guide's blocks are SD BASIC, whose
#               compiler and kernel this tree shares with Linux, where they were run (owner, 12 Nov: identical code is tested once).
# END-HISTORY
#
# WHAT IT CHECKS (each prints the real inputs it used and the counts it compared)
#   1. REGENERATE: mkpack.build() run on this tree and the docs checkout gives the committed pack/ byte for byte (the same files,
#      the same bytes).  A hand edit of a generated file, a verb added, a message changed, a docs sentence moved: all land here.
#   2. VERBS: the roster of verbs is computed HERE from sdsys/newvoc and sdsys/voc_template (type V, or K whose field 3 is V);
#      every verb has a tcl: chunk and every tcl: verb chunk names a file that exists in one of the two directories.
#   3. MESSAGES: every file of sdsys/messages has a msg: chunk and the reverse; every message number the pack cites (msg:N,
#      "message N", sysmsg(N)) is a file.
#   4. SOURCES: every chunk carries src=path:line#hash; the file exists (a tree path, or docs: a docs path), the line exists and its
#      text still hashes to the recorded hash (first 8 hex of sha1 of the line with trailing blanks removed).
#   5. MANIFEST: format, rev_stamp equals the tree's (gpl.bp/revstamp.h) and the release record's, every part exists with the
#      recorded sha256 and chunk count, nothing in pack/ is unlisted, every recorded input digest is the one recomputed here.
#   6. CHUNKS: ids unique, tier one of core / reference / examples, id grammar (lower case words and the codes as stored), a body.
#   7. NULL CASE: a pack with no chunks, or fewer verbs / messages / chunks than a real tree has, fails; it does not pass by
#      having nothing to compare.
#   8. GUIDE: agent-pack/guide/sd-basic-guide.md exists and its "Guide stamp" is the tree's rev_stamp (the guide's blocks are
#      compiled and run by gplbld/sandbox-guide.py, which needs a sandbox; this is the free half: it was checked against THIS version).
#   --selftest breaks a copy of the tree (or of the pack, or of the docs) in the ways listed there and expects exactly the owning
#   check to fail for each.

import hashlib
import importlib.util
import json
import os
import re
import shutil
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
SD64 = os.path.dirname(HERE)
PACK_DIR = os.path.join(SD64, "agent-pack")
GENERATOR = os.path.join(PACK_DIR, "mkpack.py")
PACK = os.path.join(PACK_DIR, "pack")
DOCS_DEFAULT = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(SD64))), "SDCore4WindowsDocs")
REGEN = "python %s --write" % GENERATOR

TIERS = ("core", "reference", "examples")
MIN_VERBS, MIN_MESSAGES, MIN_CHUNKS = 90, 2000, 2000     # a real tree has 97+, 2476+ and several thousand

passed = failed = 0


def row(name, ok, detail=""):
    global passed, failed
    if ok:
        passed += 1
        print("  [PASS] " + name)
    else:
        failed += 1
        print("  [FAIL] " + name + ("   <- " + detail if detail else ""))


# ----------------------------------------------------------------------------------------------------- reading

def read_bytes(path):
    with open(path, "rb") as f:
        return f.read()


def read_text(path):
    return read_bytes(path).decode("latin-1")


def line_hash(text):
    """text was read as Latin-1, so encoding it as Latin-1 gives the file's bytes back (the docs' UTF-8 included)."""
    return hashlib.sha1(text.encode("latin-1").rstrip()).hexdigest()[:8]


def load_generator(path=GENERATOR):
    if not os.path.isfile(path):
        return None, "no generator at %s" % path
    sys.dont_write_bytecode = True                           # loading the generator must not leave a __pycache__ in the tree
    spec = importlib.util.spec_from_file_location("mkpack_under_test", path)
    mod = importlib.util.module_from_spec(spec)
    try:
        spec.loader.exec_module(mod)
    except Exception as e:                                   # a generator that does not load is a finding, not a crash
        return None, "the generator does not load: %s: %s" % (type(e).__name__, e)
    return mod, ""


def read_pack(pack_dir):
    files = {}
    if os.path.isdir(pack_dir):
        for root, _dirs, names in os.walk(pack_dir):
            for n in names:
                p = os.path.join(root, n)
                files[os.path.relpath(p, pack_dir).replace(os.sep, "/")] = read_bytes(p)
    return files


CHUNK_HEAD = re.compile(r"(?m)^### (\S+)\n> (.*)\n")


def parse_chunks(files):
    """[(id, meta dict, body, part)] for every chunk of every .md part, in file order."""
    out = []
    for part in sorted(files):
        if not part.endswith(".md"):
            continue
        text = files[part].decode("utf-8", "replace")
        heads = list(CHUNK_HEAD.finditer(text))
        for i, m in enumerate(heads):
            end = heads[i + 1].start() if i + 1 < len(heads) else len(text)
            meta = {}
            for tok in re.finditer(r"(\w+)=(\S+)", m.group(2)):
                meta[tok.group(1)] = tok.group(2)
            out.append((m.group(1), meta, text[m.end():end].strip(), part))
    return out


# ----------------------------------------------------------------------------------- the tree, read independently

def newvoc_dirs(tree):
    return [os.path.join(tree, "sdsys", "newvoc"), os.path.join(tree, "sdsys", "voc_template")]


def tree_verbs(tree):
    """The verbs of the two VOC layers, computed here and not by the generator: type V, or K whose field 3 is V."""
    verbs = {}
    for d in newvoc_dirs(tree):
        if not os.path.isdir(d):
            continue
        for name in sorted(os.listdir(d)):
            p = os.path.join(d, name)
            if not os.path.isfile(p):
                continue
            lines = read_text(p).split("\n")
            f1 = lines[0].strip()[:1].upper() if lines else ""
            f3 = lines[2].strip()[:1].upper() if len(lines) > 2 else ""
            if f1 == "V" or (f1 == "K" and f3 == "V"):
                verbs.setdefault(name.lower(), os.path.relpath(p, tree))
    return verbs


def tree_messages(tree):
    d = os.path.join(tree, "sdsys", "messages")
    return {n for n in os.listdir(d) if n.isdigit()} if os.path.isdir(d) else set()


def tree_rev_stamp(tree):
    p = os.path.join(tree, "sdsys", "gpl.bp", "revstamp.h")
    m = re.search(r'(?m)^\$define SD\.REV\.STAMP\s+"([^"]+)"', read_text(p)) if os.path.isfile(p) else None
    return m.group(1) if m else None


def release_record(tree):
    p = os.path.join(tree, "sdsys", "newvoc", "$release")
    lines = read_text(p).split("\n") if os.path.isfile(p) else []
    return lines[1].strip() if len(lines) > 1 else None


SRC_NUM = re.compile(rb"(src\d?=\S+?):\d+#")


def normalize(data):
    """A part with the source line numbers blanked.  The numbers in src=path:line#hash are LOCATORS that may lag behind an edit
    elsewhere in the same file; the 8-hex hash of the cited line is the identity (check 4).  So a fresh build equals the committed
    pack when every byte but those numbers is equal.  Defined here again on purpose: the generator is not asked to mark its work."""
    return SRC_NUM.sub(rb"\1:#", data)


def same_pack(fresh, committed):
    """(equal, new-only, committed-only, changed) with the line numbers of src= ignored in the .md parts."""
    only_new = sorted(set(fresh) - set(committed))
    only_old = sorted(set(committed) - set(fresh))
    changed = [k for k in sorted(fresh) if k in committed and
               (normalize(fresh[k]) != normalize(committed[k]) if k.endswith(".md") else fresh[k] != committed[k])]
    return (not only_new and not only_old and not changed and len(fresh) > 0), only_new[:3], only_old[:3], changed[:3]


def moved_kinds(fresh, committed):
    """Which kinds of chunk the two manifests disagree about: the first thing to read when check 1 fails."""
    try:
        a = json.loads(fresh["manifest.json"].decode("utf-8")).get("kinds", {})
        b = json.loads(committed["manifest.json"].decode("utf-8")).get("kinds", {})
    except (KeyError, ValueError):
        return []
    return sorted(k for k in set(a) | set(b) if a.get(k) != b.get(k))[:6]


# ------------------------------------------------------------------------------------------------------- checks

def check_all(tree, docs, pack_files, gen, gen_error="", quiet=False):
    """Run every check; returns [(name, ok, detail)].  pack_files is {relpath: bytes}."""
    res = []
    chunks = parse_chunks(pack_files)
    ids = [c[0] for c in chunks]

    # 1. regenerate and compare
    regen_detail = ""
    ok1 = False
    files = None
    if gen is None:
        regen_detail = gen_error
    else:
        try:
            made = gen.build(tree, docs)
            files = made.files if hasattr(made, "files") else made
            ok1, only_new, only_old, diff = same_pack(files, pack_files)
            if not ok1:
                regen_detail = ("the committed pack differs from a fresh build: new-only %s, committed-only %s, changed %s, chunk kinds that moved %s - "
                                "regenerate with: %s" % (only_new, only_old, diff, moved_kinds(files, pack_files), REGEN)) if files else "the build made no files"
        except SystemExit as e:                               # the generator REFUSES when a source is incomplete: say what it said
            regen_detail = "the generator refused: %s" % e
        except Exception as e:
            regen_detail = "the generator failed: %s: %s" % (type(e).__name__, e)
    res.append(("1. the committed pack equals a fresh build from this tree and the docs (%d files committed)" % len(pack_files), ok1, regen_detail))

    # 2. verbs
    verbs = tree_verbs(tree)
    verb_chunks = {c[0][4:]: c for c in chunks if c[0].startswith("tcl:") and c[1].get("kind", "").startswith("tcl.verb")}
    no_chunk = sorted(set(verbs) - set(verb_chunks))
    no_verb = sorted(set(verb_chunks) - set(verbs))
    res.append(("2. every VOC verb has a tcl: chunk and every tcl: verb chunk is a verb (%d verbs in the VOC layers, %d chunks)" % (len(verbs), len(verb_chunks)),
                bool(verbs) and not no_chunk and not no_verb,
                "no chunk: %s; no such verb: %s" % (no_chunk[:5], no_verb[:5])))

    # 3. messages
    msgs = tree_messages(tree)
    msg_chunks = {c[0][4:] for c in chunks if c[0].startswith("msg:")}
    # the numbers the pack CITES are those in chunk bodies (a chunk's own heading is not a citation of itself)
    text_all = "\n".join(c[2] for c in chunks)
    cited = set(re.findall(r"\bmsg:(\d+)", text_all)) | set(re.findall(r"\bmessages? (\d{4,5})\b", text_all)) | set(re.findall(r"sysmsg\((\d+)\)", text_all))
    missing_msg = sorted(cited - msgs)
    res.append(("3. every message file has a msg: chunk, every msg: chunk a file, every message number the pack cites is a file "
                "(%d files, %d chunks, %d numbers cited)" % (len(msgs), len(msg_chunks), len(cited)),
                bool(msgs) and msgs == msg_chunks and not missing_msg,
                "no chunk: %s; no file: %s; cited but absent: %s" % (sorted(msgs - msg_chunks)[:5], sorted(msg_chunks - msgs)[:5], missing_msg[:5])))

    # 4. sources
    bad = []
    nsrc = 0
    moved = 0
    for cid, meta, _body, _part in chunks:
        for key in ("src", "src2", "src3"):
            if key not in meta:
                continue
            nsrc += 1
            m = re.match(r"^(docs:)?(.+):(\d+)#([0-9a-f]{8})$", meta[key])
            if not m:
                bad.append("%s: %s=%s is not path:line#hash" % (cid, key, meta[key]))
                continue
            base = docs if m.group(1) else tree
            p = os.path.join(base, m.group(2))
            if not os.path.isfile(p):
                bad.append("%s: %s has no file %s" % (cid, key, m.group(2)))
                continue
            lines = read_text(p).split("\n")
            n = int(m.group(3))
            # the hash is the identity, the number a locator that may lag: the cited text must still be in the file
            if n >= 1 and n <= len(lines) and line_hash(lines[n - 1]) == m.group(4):
                continue
            if any(line_hash(l) == m.group(4) for l in lines):
                moved += 1
                continue
            bad.append("%s: %s (line %d of %s): that text is no longer in the file" % (cid, key, n, m.group(2)))
        if "src" not in meta:
            bad.append("%s: no src" % cid)
    res.append(("4. every chunk carries a source path and a line whose text still exists (%d chunks, %d sources, %d moved to another line number)" % (len(chunks), nsrc, moved),
                bool(chunks) and not bad, "%d bad, first: %s" % (len(bad), bad[:3])))

    # 5. manifest
    problems = []
    mpath = "manifest.json"
    man = None
    if mpath not in pack_files:
        problems.append("no manifest.json")
    else:
        try:
            man = json.loads(pack_files[mpath].decode("utf-8"))
        except ValueError as e:
            problems.append("manifest.json is not JSON: %s" % e)
    if man is not None:
        stamp = tree_rev_stamp(tree)
        if not stamp or man.get("rev_stamp") != stamp:
            problems.append("rev_stamp %r, the tree's gpl.bp/revstamp.h says %r" % (man.get("rev_stamp"), stamp))
        if man.get("release_record") != release_record(tree):
            problems.append("release_record %r, sdsys/newvoc/$release says %r" % (man.get("release_record"), release_record(tree)))
        parts = man.get("parts", {})
        for part, info in parts.items():
            if part not in pack_files:
                problems.append("part %s is listed and absent" % part)
            elif hashlib.sha256(normalize(pack_files[part])).hexdigest() != info.get("sha256"):
                problems.append("part %s has changed since the manifest was written" % part)
            elif part.endswith(".md") and info.get("chunks") != sum(1 for c in chunks if c[3] == part):
                problems.append("part %s lists %s chunks, has %d" % (part, info.get("chunks"), sum(1 for c in chunks if c[3] == part)))
        unlisted = sorted(set(pack_files) - set(parts) - {mpath})
        if unlisted:
            problems.append("files in pack/ that the manifest does not list: %s" % unlisted[:3])
        if man.get("chunk_count") != len(chunks):
            problems.append("chunk_count %s, parsed %d" % (man.get("chunk_count"), len(chunks)))
        kinds = man.get("kinds", {})
        if not kinds or sum(v.get("chunks", 0) for v in kinds.values()) != len(chunks):
            problems.append("kinds lists %d chunks, parsed %d" % (sum(v.get("chunks", 0) for v in kinds.values()), len(chunks)))
    res.append(("5. the manifest: version stamp %s, release record %s, part digests and chunk counts (%d parts)" % (
        tree_rev_stamp(tree), release_record(tree), len((man or {}).get("parts", {}))), not problems, "; ".join(problems[:4])))

    # 6. chunks
    seen = set()
    dup = []
    badc = []
    for cid, meta, body, part in chunks:
        if cid in seen:
            dup.append(cid)
        seen.add(cid)
        if meta.get("tier") not in TIERS:
            badc.append("%s: tier %r" % (cid, meta.get("tier")))
        if not re.match(r"^[a-z0-9]+(:[A-Za-z0-9_.$@%+*<>!&#-]+)+$", cid):
            badc.append("%s: id grammar" % cid)
        if not meta.get("kind") or not meta.get("since"):
            badc.append("%s: no kind or since" % cid)
        if not body:
            badc.append("%s: empty body" % cid)
    res.append(("6. chunk ids are unique, tiers valid, ids well formed, every chunk has kind, since and a body (%d chunks)" % len(chunks),
                bool(chunks) and not dup and not badc, "duplicates %s; %s" % (dup[:3], badc[:3])))

    # 7. the null case
    short = []
    if len(verb_chunks) < MIN_VERBS:
        short.append("%d verb chunks (a real tree has at least %d)" % (len(verb_chunks), MIN_VERBS))
    if len(msg_chunks) < MIN_MESSAGES:
        short.append("%d message chunks (at least %d)" % (len(msg_chunks), MIN_MESSAGES))
    if len(chunks) < MIN_CHUNKS:
        short.append("%d chunks (at least %d)" % (len(chunks), MIN_CHUNKS))
    res.append(("7. the pack is not empty: at least %d verbs, %d messages, %d chunks" % (MIN_VERBS, MIN_MESSAGES, MIN_CHUNKS), not short, "; ".join(short)))

    # 8. the hand-written guide carries the stamp of the tree it describes
    gpath = os.path.join(tree, "agent-pack", "guide", "sd-basic-guide.md")
    gproblem = ""
    gstamp = None
    if not os.path.isfile(gpath):
        gproblem = "there is no guide at agent-pack/guide/sd-basic-guide.md"
    else:
        gm = re.search(r"Guide stamp:\*{0,2}\s*`([^`]+)`", read_text(gpath))
        gstamp = gm.group(1) if gm else None
        if gstamp != tree_rev_stamp(tree):
            gproblem = "the guide's stamp is %r, the tree's revstamp.h says %r - the guide was checked against another version" % (gstamp, tree_rev_stamp(tree))
    res.append(("8. the guide exists and its stamp %s is the tree's %s" % (gstamp, tree_rev_stamp(tree)), not gproblem, gproblem))

    # 9. the Claude Code skill: SKILL.md is well formed, and references/ is the guide and the pack, byte for byte
    sk_dir = os.path.join(tree, "agent-pack", "skill", "sd-core")
    sprob = []
    smd = os.path.join(sk_dir, "SKILL.md")
    nrefs = 0
    if not os.path.isfile(smd):
        sprob.append("no SKILL.md")
    else:
        text = read_text(smd)
        fm = re.match(r"^---\n(.*?)\n---\n(.*)$", text, re.S)           # the opening --- must be the file's first line (the skills page)
        if not fm:
            sprob.append("SKILL.md does not open with --- front matter")
        else:
            head, body = fm.group(1), fm.group(2)
            fields = dict(re.findall(r"(?m)^([a-z_-]+):\s*(.*)$", head))
            if fields.get("name") != "sd-core":
                sprob.append("name is %r, the folder is sd-core" % fields.get("name"))
            desc = fields.get("description", "")
            when = fields.get("when_to_use", "")
            if not desc:
                sprob.append("no description")
            if len(desc) + len(when) > 1536:
                sprob.append("description + when_to_use is %d characters; the listing truncates at 1,536" % (len(desc) + len(when)))
            if len(body.split("\n")) > 500:
                sprob.append("the body is %d lines; the skills page recommends under 500" % len(body.split("\n")))
            for k in fields:
                if k not in ("name", "description", "when_to_use"):
                    sprob.append("front matter field %r is not one the check expects (allowed-tools and the like widen what the skill may do)" % k)
            for link in sorted(set(re.findall(r"\]\((references/[^)#]+)", body))):
                if not os.path.isfile(os.path.join(sk_dir, link)):
                    sprob.append("SKILL.md links %s, which is not there" % link)
    refs_dir = os.path.join(sk_dir, "references")
    have_refs = read_pack(refs_dir)
    nrefs = len(have_refs)
    if gen is not None and have_refs and files:
        try:
            want_refs = gen.build_skill(files, tree)
        except Exception as e:
            want_refs = None
            sprob.append("build_skill failed: %s" % e)
        if want_refs is not None:
            ok_refs, o_new, o_old, o_diff = same_pack(want_refs, have_refs)
            if not ok_refs:
                sprob.append("references/ differs from the guide and the pack: new-only %s, committed-only %s, changed %s - regenerate with %s" % (o_new, o_old, o_diff, REGEN))
    elif not have_refs:
        sprob.append("references/ is empty or absent")
    res.append(("9. the skill: SKILL.md well formed (name, description within 1,536 characters, links resolve) and references/ equals the guide and the pack (%d files)" % nrefs,
                not sprob, "; ".join(sprob[:3])))

    # 10. the CLAUDE.md template, the .mcp.json example and the recipe
    tprob = []
    tdir = os.path.join(tree, "agent-pack", "templates")
    rdir = os.path.join(tree, "agent-pack", "recipe")
    ct = os.path.join(tdir, "CLAUDE.md")
    if not os.path.isfile(ct):
        tprob.append("no templates/CLAUDE.md")
    else:
        ctext = read_text(ct)
        if len(ctext.split("\n")) > 200:
            tprob.append("templates/CLAUDE.md is %d lines; Claude Code asks for under 200" % len(ctext.split("\n")))
        if "gates are walls" not in ctext.lower():
            tprob.append("templates/CLAUDE.md no longer says the gates are walls")
    mj = os.path.join(tdir, "mcp.json.example")
    if not os.path.isfile(mj):
        tprob.append("no templates/mcp.json.example")
    else:
        try:
            cfg = json.loads(read_text(mj))
            srv = cfg["mcpServers"]["sd"]
            if srv.get("type") != "stdio" or not srv.get("command"):
                tprob.append("mcp.json.example: the sd server is not a stdio command")
        except (ValueError, KeyError) as e:
            tprob.append("mcp.json.example is not the file it should be: %s" % e)
    tr = os.path.join(tdir, "README.md")
    if not os.path.isfile(tr) or "DOES NOT WORK TODAY" not in read_text(tr):
        tprob.append("templates/README.md must say, in those words, that the .mcp.json example DOES NOT WORK TODAY (there is no sd-mcp)")
    rec = os.path.join(rdir, "agent-account.md")
    rwords = []
    if not os.path.isfile(rec):
        tprob.append("no recipe/agent-account.md")
    else:
        m = re.search(r"\*\*Words used:\*\*(.*)", read_text(rec))
        rwords = re.findall(r"`([a-z.-]+)`", m.group(1)) if m else []
        if not rwords:
            tprob.append("the recipe lists no 'Words used:'")
        known = {c[0][len("sys:word:"):] for c in chunks if c[0].startswith("sys:word:")}
        gone = [w for w in rwords if w not in known]
        if gone:
            tprob.append("the recipe uses account words the pack does not have: %s" % gone)
    res.append(("10. templates and recipe: CLAUDE.md under 200 lines and still says the gates are walls; mcp.json.example valid and honestly labelled; the recipe's account words (%d) exist in the pack" % len(rwords),
                not tprob, "; ".join(tprob[:3])))
    return res


def run_checks(tree, docs, pack_dir, gen, gen_error=""):
    print("test-pack-units: tree %s" % tree)
    print("test-pack-units: docs %s" % docs)
    print("test-pack-units: pack %s" % pack_dir)
    print("test-pack-units: generator %s" % (GENERATOR if gen is not None else "NOT LOADED (%s)" % gen_error))
    files = read_pack(pack_dir)
    ok_all = True
    for name, ok, detail in check_all(tree, docs, files, gen, gen_error):
        row(name, ok, detail)
        ok_all = ok_all and ok
    return ok_all


# ----------------------------------------------------------------------------------------------------- selftest

def copy_inputs(gen, tree, docs, dest):
    """A scratch copy of exactly what the generator reads (it names them in INPUT_PATHS), so a mutant never touches the live tree."""
    t = os.path.join(dest, "tree")
    d = os.path.join(dest, "docs")
    for rel in list(gen.INPUT_PATHS) + ["agent-pack/skill", "agent-pack/templates", "agent-pack/recipe"]:      # what checks 9 and 10 read; the generator only writes into the skill
        src = os.path.join(docs, rel[5:]) if rel.startswith("docs:") else os.path.join(tree, rel)
        dst = os.path.join(d, rel[5:]) if rel.startswith("docs:") else os.path.join(t, rel)
        if os.path.isdir(src):
            shutil.copytree(src, dst)
        elif os.path.isfile(src):
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            shutil.copy2(src, dst)
    return t, d


def dir_digest(root):
    h = hashlib.sha256()
    for r, _d, names in sorted(os.walk(root)):
        for n in sorted(names):
            p = os.path.join(r, n)
            h.update(os.path.relpath(p, root).encode() + b"\0" + hashlib.sha256(read_bytes(p)).digest())
    return h.hexdigest()


def edit(path, fn):
    data = read_bytes(path)
    new = fn(data)
    if new == data:
        return False
    with open(path, "wb") as f:
        f.write(new)
    return True


def selftest(gen, tree, docs):
    if gen is None:
        row("selftest: cannot run without the generator", False, "no generator")
        return False
    ok_all = True
    committed = read_pack(PACK)
    verb = "list"
    mutants = []

    def add(label, want, tree_fn=None, pack_fn=None, docs_fn=None):
        mutants.append((label, want, tree_fn, pack_fn, docs_fn))

    # tree mutants (applied to the scratch copy; the committed pack is judged against the changed tree)
    add("a verb removed from both VOC layers", "2.",
        tree_fn=lambda t, d: [os.remove(os.path.join(t, "sdsys", layer, verb)) for layer in ("newvoc", "voc_template")])
    add("a verb added to voc_template with no pack run", "2.",
        tree_fn=lambda t, d: open(os.path.join(t, "sdsys", "voc_template", "zz.selftest.verb"), "w").write("Verb - a selftest verb\nCA\n$list\n"))
    add("a message text changed", "1.",
        tree_fn=lambda t, d: edit(os.path.join(t, "sdsys", "messages", "10161"), lambda b: b + b" (changed)"))
    add("a message file removed", "3.", tree_fn=lambda t, d: os.remove(os.path.join(t, "sdsys", "messages", "10161")))
    add("the version stamp moved", "5.",
        tree_fn=lambda t, d: edit(os.path.join(t, "sdsys", "gpl.bp", "revstamp.h"), lambda b: b.replace(b'SD.REV.STAMP   "', b'SD.REV.STAMP   "X')))
    add("a source line the pack cites changed", "4.",
        tree_fn=lambda t, d: edit(os.path.join(t, "sdsys", "newvoc", verb), lambda b: b.replace(b"Verb", b"Verbs", 1)))
    add("a source file the pack cites truncated to nothing", "4.",
        tree_fn=lambda t, d: open(os.path.join(t, "sdsys", "newvoc", verb), "w").close())
    # pack mutants (the tree is the live one)
    add("a hand edit to a generated file", "1.",
        pack_fn=lambda p: edit(os.path.join(p, sorted(f for f in committed if f.endswith(".md"))[0]), lambda b: b.replace(b"\n\n", b"\n\n(edited by hand) ", 1)))
    add("a chunk citing a message that does not exist", "3.",
        pack_fn=lambda p: edit(os.path.join(p, sorted(f for f in committed if f.endswith(".md"))[0]), lambda b: b + b"\nsee msg:99999\n"))
    add("a stale manifest (a part digest recorded for other bytes)", "5.",
        pack_fn=lambda p: edit(os.path.join(p, "manifest.json"),
                               lambda b: b.split(b'"parts"')[0] + b'"parts"' + re.sub(rb'("sha256": ")([0-9a-f])', lambda m: m.group(1) + (b"0" if m.group(2) != b"0" else b"1"), b.split(b'"parts"')[1], count=1)))
    add("a part listed in the manifest and deleted", "5.",
        pack_fn=lambda p: os.remove(os.path.join(p, sorted(f for f in committed if f.endswith(".md"))[-1])))
    add("the pack emptied", "7.", pack_fn=lambda p: [os.remove(os.path.join(p, f)) for f in committed if f.endswith(".md")])
    add("the guide's stamp is not the tree's", "8.",
        tree_fn=lambda t, d: edit(os.path.join(t, "agent-pack", "guide", "sd-basic-guide.md"), lambda b: b.replace(b"Guide stamp:** `W", b"Guide stamp:** `X", 1)))   # 13 Nov 26 Windows: the stamp starts W here (Linux's starts L)
    add("the guide is missing", "8.", tree_fn=lambda t, d: os.remove(os.path.join(t, "agent-pack", "guide", "sd-basic-guide.md")))
    sk = ("agent-pack", "skill", "sd-core")
    add("a hand edit to the skill's copy of the guide", "9.",
        tree_fn=lambda t, d: edit(os.path.join(t, *sk, "references", "guide.md"), lambda b: b.replace(b"# Part A", b"# Part A (edited)", 1)))
    add("the skill's description grows past the 1,536 characters the listing keeps", "9.",
        tree_fn=lambda t, d: edit(os.path.join(t, *sk, "SKILL.md"), lambda b: b.replace(b"\nwhen_to_use: ", b"\nwhen_to_use: " + b"x" * 1500 + b" ", 1)))
    add("SKILL.md links a reference that is not there", "9.",
        tree_fn=lambda t, d: edit(os.path.join(t, *sk, "SKILL.md"), lambda b: b.replace(b"(references/guide.md)", b"(references/guide-gone.md)", 1)))
    tp = ("agent-pack", "templates")
    add("the recipe names an account word that does not exist", "10.",
        tree_fn=lambda t, d: edit(os.path.join(t, "agent-pack", "recipe", "agent-account.md"), lambda b: b.replace(b"`bp-on`, `dict-on`", b"`bp-yes`, `dict-on`", 1)))
    add("the CLAUDE.md template grows past 200 lines", "10.",
        tree_fn=lambda t, d: edit(os.path.join(t, *tp, "CLAUDE.md"), lambda b: b + b"- a line\n" * 200))
    add("the CLAUDE.md template stops saying the gates are walls", "10.",
        tree_fn=lambda t, d: edit(os.path.join(t, *tp, "CLAUDE.md"), lambda b: b.replace(b"The gates are walls.", b"The gates are advice.", 1)))
    add("the .mcp.json example is no longer JSON", "10.",
        tree_fn=lambda t, d: edit(os.path.join(t, *tp, "mcp.json.example"), lambda b: b.replace(b'"type": "stdio",', b'"type": "stdio"', 1)))
    add("the templates README stops warning that the example does not work", "10.",
        tree_fn=lambda t, d: edit(os.path.join(t, *tp, "README.md"), lambda b: b.replace(b"DOES NOT WORK TODAY", b"works", 1)))
    add("SKILL.md gains an allowed-tools field", "9.",
        tree_fn=lambda t, d: edit(os.path.join(t, *sk, "SKILL.md"), lambda b: b.replace(b"\n---\n\n# SD Core", b"\nallowed-tools: Bash\n---\n\n# SD Core", 1)))
    add("a docs line the pack quotes changed (the generator must notice)", "1.",
        docs_fn=lambda t, d: edit(os.path.join(d, "tools", "tcl-syntax-shapes.txt"), lambda b: b.replace(b"abort = ", b"abort = (changed) ", 1)))
    add("a verb with no syntax line in the docs (the generator must refuse)", "1.",
        docs_fn=lambda t, d: edit(os.path.join(d, "tools", "tcl-syntax-shapes.txt"), lambda b: re.sub(rb"(?m)^abort = .*\n", b"", b, count=1)))
    add("a docs heading the pack needs renamed (the generator must refuse)", "1.",
        docs_fn=lambda t, d: edit(os.path.join(d, "User", "markdown", "32-sd-voc-structure-and-usage.md"), lambda b: b.replace(b"## The V record", b"## A V record", 1)))
    add("bcomp's intrinsic name list and dispatch list drift apart (the generator must refuse)", "1.",
        tree_fn=lambda t, d: edit(os.path.join(t, "sdsys", "gpl.bp", "bcomp"), lambda b: b.replace(b'   intrinsics = "ABS" ', b'   intrinsics = "ABSX"                ; intrinsic.opcodes = OP.ABS\n   intrinsics<-1> = "ABS" ', 1)))
    # the control for the line-number tolerance: lines inserted above everything the pack cites move the numbers and nothing else
    add("three comment lines inserted at the top of bcomp and of createa (line numbers move, no text changes)", None,
        tree_fn=lambda t, d: [edit(os.path.join(t, "sdsys", "gpl.bp", n), lambda b: b"* a\n* b\n* c\n" + b) for n in ("bcomp", "createa")])

    for label, want, tree_fn, pack_fn, docs_fn in mutants:
        work = tempfile.mkdtemp(prefix="packtest-")
        try:
            t, d = copy_inputs(gen, tree, docs, work)
            before = dir_digest(t) + dir_digest(d)
            use_tree, use_docs, use_pack = t, d, PACK
            if tree_fn is not None:
                tree_fn(t, d)
            if docs_fn is not None:
                docs_fn(t, d)
            if pack_fn is not None:
                use_pack = os.path.join(work, "pack")
                shutil.copytree(PACK, use_pack)
                pack_fn(use_pack)
            files = read_pack(use_pack)
            changed = files != committed or dir_digest(t) + dir_digest(d) != before      # the BYTES moved, whatever the lambda says
            if not changed:
                row("selftest: %s" % label, False, "the mutation changed nothing")
                ok_all = False
                continue
            fails = [n.split(" ")[0] for n, ok, _d in check_all(use_tree, use_docs, files, gen) if not ok]
            if want is None:                                  # a control: this change must NOT be a finding
                row("selftest: %s passes every check (control; failed: %s)" % (label, " ".join(fails) or "none"), not fails)
                ok_all = ok_all and not fails
            else:
                row("selftest: %s is caught by check %s (failed: %s)" % (label, want, " ".join(fails) or "none"), want in fails)
                ok_all = ok_all and (want in fails)
        finally:
            shutil.rmtree(work, ignore_errors=True)
    # the control: the unmutated copy passes everything, so a mutant's failure is the mutant's and not the copy's
    work = tempfile.mkdtemp(prefix="packtest-")
    try:
        t, d = copy_inputs(gen, tree, docs, work)
        fails = [n.split(" ")[0] for n, ok, _d in check_all(t, d, committed, gen) if not ok]
        row("selftest: the unchanged scratch copy passes every check (control)", not fails, "failed: %s" % fails)
        ok_all = ok_all and not fails
    finally:
        shutil.rmtree(work, ignore_errors=True)
    return ok_all


def main():
    docs = DOCS_DEFAULT
    if "--docs" in sys.argv:
        docs = sys.argv[sys.argv.index("--docs") + 1]
    need = [os.path.join(docs, "User", "markdown"), os.path.join(docs, "tools", "tcl-syntax-shapes.txt"), os.path.join(docs, "tools", "syntax-shapes.txt")]
    gone = [p for p in need if not os.path.exists(p)]
    if gone:
        print("test-pack-units: CANNOT RUN - the docs checkout is missing or incomplete: %s" % gone)
        print("test-pack-units: the pack is generated from SDCore4WindowsDocs; clone it to %s or pass --docs DIR" % DOCS_DEFAULT)
        sys.exit(2)
    gen, gen_error = load_generator()
    ok = run_checks(SD64, docs, PACK, gen, gen_error)
    if "--selftest" in sys.argv:
        selftest(gen, SD64, docs)
    print("\ntest-pack-units: %d passed, %d failed" % (passed, failed))
    sys.exit(0 if failed == 0 and ok else 1)


if __name__ == "__main__":
    main()
