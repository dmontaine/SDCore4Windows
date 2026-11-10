#!/usr/bin/env python3
# test-tkpublic-units.py - the public full-screen toolkit (S.130, 3 Nov 2026): the eleven `!tk` wrappers over the `$tk_*` routines and the header `syscom/tkpub.h`, read off the source as text.
#
#   T1  each wrapper is a file of gpl.bp named for it, is $internal, catalogues `!<name>` once (and no other program catalogues that name), is a subroutine with the argument count its header
#       promises and is not VAR.ARGS (a short call stops with "Argument count mismatch": the header says ALWAYS N arguments)
#   T2  each wrapper calls exactly one `$tk_` routine, the one it wraps, with its own arguments in order, and no other program of the toolkit is reached through it
#   T3  THE AUDIENCE IS THE USER'S: `!tkopen` gives $tk_open the null audience and the word `admin` is in no wrapper's code
#   T4  a wrapper runs, reads, writes and opens nothing: no `$tk_run`, `$tk_runx`, `$tk_gates`, `$tk_gate_info`, `$tk_ai*`, `$tk_help`, `$tk_ownfile`, `$tk_explain`, `$tk_word`, `$tk_brk`, no
#       statement that executes, reads or writes, and no `kernel(`: it adds no right and asks for none
#   T5  `!tkframe`, `!tkmenubar` and `!tklayout` clear the AI line's two context slots (TK.C.AI, TK.C.AIROW) BEFORE they call the toolkit, so a program cannot make the library draw an AI line or
#       take a row for one
#   T6  `!tkkeys` never passes the two AI ops (`ai`, `aiacts`) on to $tk_keys; aiacts answers nothing
#   T7  tkpub.h: every `$define` has the name AND the value tk.h gives it; the names it leaves out are exactly the AI line's two slots, the key table's AI field and the gate table; it names every
#       routine with the number of arguments the wrapper takes
#   T8  no program of the toolkit's own (`tk_*`, `sl_*`, `tool_*`, `home*`) calls a `!tk` wrapper: the public library is for user programs, the pages keep to the internal names
#
# FREE CHECK: no install, no sd.     python3 .../test-tkpublic-units.py        python3 .../test-tkpublic-units.py --selftest [--from=N]
import glob
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SDSYS = os.environ.get("SDSYSDIR", os.path.normpath(os.path.join(HERE, "..", "sdsys")))
BP = os.path.join(SDSYS, "gpl.bp")
SYSCOM = os.path.join(SDSYS, "syscom")
# wrapper: (the toolkit routine it wraps, its arguments)
WRAP = {
    "tkopen": ("tk_open", ["app", "ctx", "err", "floorw", "floorh"]),
    "tkclose": ("tk_close", ["ctx"]),
    "tkkeys": ("tk_keys", ["op", "keys", "a", "b", "c", "d", "e"]),
    "tkframe": ("tk_frame", ["ctx", "keys", "pane", "msg"]),
    "tkmenubar": ("tk_menubar", ["op", "ctx", "keys", "pane", "a", "b", "c"]),
    "tklayout": ("tk_layout", ["op", "ctx", "arg", "ret"]),
    "tkconfirm": ("tk_confirm", ["sentence", "lines", "typed", "res", "msg", "boxtitle", "btns"]),
    "tkform": ("tk_form", ["op", "ctx", "a", "b", "c"]),
    "tkpickrec": ("tk_pickrec", ["ctx", "mode", "file", "id", "res", "newtext"]),
    "tkout": ("tk_out", ["op", "ctx", "a", "b", "c"]),
    "tkwrap": ("tk_wrap", ["text", "width", "out"]),
}
NAMES = tuple(WRAP)
FORBIDDEN = ("tk_run", "tk_runx", "tk_gates", "tk_gate_info", "tk_ai", "tk_aipage", "tk_aidocs", "tk_aiwall", "tk_help", "tk_ownfile", "tk_explain", "tk_word", "tk_brk")
NOT_IN_PUBLIC = {"TK.C.AI", "TK.C.AIROW", "TK.K.AI"}
STATEMENTS = r"(?m)^\s*(execute|os\.execute|write|writev|writeu|delete|deletelist|open|openseq|openpath|read|readv|readu|readseq|writeseq|chain|perform|sh|screen)(?=\s)|\bkernel\(|\bsysmsg\("


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


def defines(t):
    return {m.group(1): m.group(2) for m in re.finditer(r"(?m)^\$define\s+(\S+)\s+(\S+)", t)}


def load():
    s = {n: read(os.path.join(BP, n)) for n in NAMES if os.path.exists(os.path.join(BP, n))}
    s["tk.h"] = read(os.path.join(BP, "tk.h"))
    p = os.path.join(SYSCOM, "tkpub.h")
    s["tkpub.h"] = read(p) if os.path.exists(p) else ""
    s["catalogs"] = {}
    s["calls"] = {}
    for p in glob.glob(os.path.join(BP, "*")):
        if not os.path.isfile(p) or p.endswith(".h"):
            continue
        t = read(p)
        s["catalogs"][os.path.basename(p)] = re.findall(r"(?mi)^\$catalog\s+(\S+)", t)
        s["calls"][os.path.basename(p)] = code(t)
    return s


def checks(s):
    rows = []

    def ck(name, ok, detail=""):
        rows.append((name, bool(ok), detail))

    for n, (target, args) in WRAP.items():
        t = s.get(n, "")
        c = code(t)
        m = re.search(r"(?m)^subroutine (\w+)\(([^)]*)\)(.*)$", c)
        cat = [x for x in re.findall(r"(?m)^\$catalog\s+(\S+)", c)]
        owners = [p for p, cs in s["catalogs"].items() if "!" + n in [x.lower() for x in cs]]
        ck("T1 %s is $internal, catalogued !%s once and by no other program, and takes %d arguments (not VAR.ARGS)" % (n, n, len(args)),
           m is not None and m.group(1) == n and [a.strip() for a in m.group(2).split(",")] == args and "var.args" not in m.group(3).lower() and "\n$internal\n" in "\n" + c + "\n"
           and cat == ["!" + n] and owners == [n], repr((m.groups() if m else None, cat, owners)))
        calls = re.findall(r"\$tk_\w+", c)
        want = "call $%s(%s)" % (target, ", ".join(args))
        if n == "tkopen":
            want = "call $tk_open(app, '', ctx, err, floorw, floorh)"
        ck("T2 %s calls $%s and no other toolkit routine, with its own arguments in order" % (n, target),
           set(calls) == {"$" + target} and (want in c or n in ("tkkeys",) and "call $tk_keys(op, keys, a, b, c, d, e)" in c), repr(calls))
        bad = [f for f in FORBIDDEN if re.search(r"\$%s\b" % f, c)]
        st = re.findall(STATEMENTS, c)
        ck("T4 %s runs, reads, writes, opens and asks the kernel nothing, and reaches none of the toolkit's other programs" % n, not bad and not re.search(STATEMENTS, c), repr((bad, st)))
    ck("T3 the audience is the user's: !tkopen passes the null audience and 'admin' is in no wrapper",
       "call $tk_open(app, '', ctx, err, floorw, floorh)" in code(s.get("tkopen", "")) and not any(re.search(r"admin", code(s.get(n, "")), re.I) for n in NAMES), "")
    for n, target in (("tkframe", "$tk_frame("), ("tkmenubar", "$tk_menubar("), ("tklayout", "$tk_layout(")):
        c = code(s.get(n, ""))
        ck("T5 %s clears the AI line's two slots before it calls the toolkit" % n,
           ordered(c, "ctx<TK.C.AI> = ''", "ctx<TK.C.AIROW> = ''", "call " + target) and "$include tk.h" in c, "")
    c = code(s.get("tkkeys", ""))
    ck("T6 !tkkeys keeps the AI ops from $tk_keys and answers nothing to aiacts",
       ordered(c, "if op = 'aiacts' then", "b = ''", "c = ''", "end else", "if op # 'ai' then call $tk_keys(op, keys, a, b, c, d, e)") and c.count("call $tk_keys(") == 1, c)
    internal, public = defines(s["tk.h"]), defines(s["tkpub.h"])
    diff = {k: (public[k], internal.get(k)) for k in public if internal.get(k) != public[k]}
    left = sorted(k for k in internal if k not in public)
    want_left = sorted(NOT_IN_PUBLIC | {k for k in internal if k.startswith("TK.G.")})
    ck("T7a every $define of tkpub.h has the name and the value of tk.h's", bool(public) and not diff, repr(diff))
    ck("T7b the names tkpub.h leaves out are the AI line's slots, the key table's AI field and the gate table, and no other", left == want_left, repr((left, want_left)))
    ph = s["tkpub.h"]
    ck("T7c tkpub.h lists every routine with the number of arguments of the wrapper (a call with fewer stops with an argument count mismatch)",
       all(re.search(r"call !%s\(" % n, ph) for n in NAMES) and all(len(re.search(r"call !%s\(([^)]*)\)" % n, ph).group(1).split(",")) == len(a) for n, (_t, a) in WRAP.items()), "")
    users = [p for p in s["calls"] if re.match(r"(tk_|sl_|tool_|home)", p) and re.search(r"call !tk(open|close|keys|frame|menubar|layout|confirm|form|pickrec|out|wrap)\b", s["calls"][p])]
    ck("T8 no page of the toolkit's own calls a public wrapper", not users, repr(users))
    return rows


def sub(src, old, new):
    if src.count(old) != 1:
        raise SystemExit("selftest: the old text occurs %d times, not once:\n%s" % (src.count(old), old[:120]))
    return src.replace(old, new)


MUTANTS = [
    ("tkopen loses an argument", "tkopen", "subroutine tkopen(app, ctx, err, floorw, floorh)", "subroutine tkopen(app, ctx, err, floorw)", "T1"),
    ("tkopen is VAR.ARGS", "tkopen", "subroutine tkopen(app, ctx, err, floorw, floorh)", "subroutine tkopen(app, ctx, err, floorw, floorh) var.args", "T1"),
    ("tkclose is not internal", "tkclose", "$internal\n", "", "T1"),
    ("tkwrap is catalogued with another name", "tkwrap", "$catalog !tkwrap", "$catalog !tkwrapx", "T1"),
    ("tkout calls the wrong routine", "tkout", "call $tk_out(op, ctx, a, b, c)", "call $tk_form(op, ctx, a, b, c)", "T2"),
    ("tkform passes its arguments in another order", "tkform", "call $tk_form(op, ctx, a, b, c)", "call $tk_form(op, ctx, b, a, c)", "T2"),
    ("tkopen asks for the administrator's page", "tkopen", "call $tk_open(app, '', ctx, err, floorw, floorh)", "call $tk_open(app, 'admin', ctx, err, floorw, floorh)", "T3"),
    ("tkpickrec writes", "tkpickrec", "   call $tk_pickrec(ctx, mode, file, id, res, newtext)\n", "   call $tk_pickrec(ctx, mode, file, id, res, newtext)\n   write id on file, id\n", "T4"),
    ("tkconfirm runs the sentence", "tkconfirm", "   call $tk_confirm(sentence, lines, typed, res, msg, boxtitle, btns)\n",
     "   call $tk_confirm(sentence, lines, typed, res, msg, boxtitle, btns)\n   if res = 'run' then call $tk_run(1, sentence, out, st, err)\n", "T4"),
    ("tkform asks the kernel", "tkform", "   call $tk_form(op, ctx, a, b, c)\n", "   x = kernel(K$ADMINISTRATOR, -1)\n   call $tk_form(op, ctx, a, b, c)\n", "T4"),
    ("tkframe leaves the AI row", "tkframe", "   ctx<TK.C.AIROW> = ''\n", "", "T5"),
    ("tkmenubar clears after the call", "tkmenubar", "   ctx<TK.C.AI> = ''\n   ctx<TK.C.AIROW> = ''\n   call $tk_menubar(op, ctx, keys, pane, a, b, c)\n",
     "   call $tk_menubar(op, ctx, keys, pane, a, b, c)\n   ctx<TK.C.AI> = ''\n   ctx<TK.C.AIROW> = ''\n", "T5"),
    ("tklayout leaves the AI slot", "tklayout", "   ctx<TK.C.AI> = ''\n", "", "T5"),
    ("tkkeys passes ai on", "tkkeys", "      if op # 'ai' then call $tk_keys(op, keys, a, b, c, d, e)", "      call $tk_keys(op, keys, a, b, c, d, e)", "T6"),
    ("tkkeys passes aiacts on", "tkkeys", "   if op = 'aiacts' then\n      b = ''\n      c = ''\n   end else", "   if 0 then\n      b = ''\n      c = ''\n   end else", "T6"),
    ("a slot number differs from tk.h's", "tkpub.h", "$define TK.C.BODYH     19", "$define TK.C.BODYH     18", "T7a"),
    ("the public header gains the AI slot", "tkpub.h", "$define TK.C.GEN       10\n", "$define TK.C.GEN       10\n$define TK.C.AI        11\n", "T7b"),
    ("the public header gains a name tk.h does not have", "tkpub.h", "$define TK.XBODY       1\n", "$define TK.XBODY       1\n$define TK.C.NEW       30\n", "T7a"),
    ("the header's routine list is short an argument", "tkpub.h", "call !tkwrap(text, width, out)", "call !tkwrap(text, width)", "T7c"),
    ("a page of the toolkit calls a wrapper", "tool_mygates", "call $tk_close(ctx)", "call !tkclose(ctx)", "T8"),
]


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
        src = s0.get(key)
        if src is None and key in s0["calls"]:
            src = read(os.path.join(BP, key))
        if src is None or src.count(old) != 1:
            print("  [FAIL] selftest: %s: the old text occurs %d times in %s, not once" % (name, 0 if src is None else src.count(old), key))
            bad += 1
            continue
        over = {key: src.replace(old, new)}
        if key in s0["calls"] or key in NAMES:
            over["calls"] = dict(s0["calls"])
            over["calls"][key] = code(over[key])
            if key in NAMES:
                over["catalogs"] = dict(s0["catalogs"])
                over["catalogs"][key] = re.findall(r"(?mi)^\$catalog\s+(\S+)", over[key])
        failed = [n.split()[0] for n, ok, _ in run(over) if not ok]
        hit = want in failed
        print("  [%s] selftest: %s is caught by %s (failed: %s)" % ("PASS" if hit else "FAIL", name, want, " ".join(failed) or "none"))
        bad += 0 if hit else 1
    print("selftest: %s" % ("every mutant was caught" if bad == 0 else "%d problem(s)" % bad))
    return 0 if bad == 0 else 1


def main(argv):
    for n in NAMES:
        if not os.path.exists(os.path.join(BP, n)):
            print("test-tkpublic-units: no such program %s" % n)
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
    print("test-tkpublic-units: %d checks, %d failed" % (len(rows), bad))
    return 0 if bad == 0 else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
