#!/usr/bin/env python3
# test-cedcore-units.py - the one-editor plan, stage 1 (30 Oct 2026): the data collection editor is an ENGINE (gpl.bp/ced_core, $ced_core(op, st, a, out)) and a full-screen HOST
# (gpl.bp/ced_edit, $cedit), read off the source as text.  The engine is what the IDE will embed in stage 2, so what makes that safe is held here: the engine never opens or closes the
# screen and never writes a file, every op the host sends has a handler, the engine's state is kept and read back in step, the host is the only writer (after the edit gate and after the
# engine has agreed), a quit that waits for a write goes on only when the write was kept, and every caller of $cedit and $ced_core gives the arguments it takes.
# The behaviour is sandbox-ced.py's (134 rows on a pseudo-terminal), unchanged by the split.
#
# FREE CHECK: the BASIC read as text; no install, no sd.
#
#   python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/test-cedcore-units.py
#   python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/test-cedcore-units.py --selftest
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
BP = os.environ.get("BPDIR", os.path.normpath(os.path.join(HERE, "..", "sdsys", "gpl.bp")))
PROGS = ("ced_core", "ced_edit", "ced", "ced_sub", "ide")


def read(name):
    with open(os.path.join(BP, name), encoding="latin-1") as f:
        return f.read()


def code(text):
    """Statements only: whole-line comments, trailing ;* comments and blank lines dropped (a * inside a quoted string is not a comment: none of the lines read here has one)."""
    out = []
    for l in text.split("\n"):
        s = re.sub(r";\*.*$", "", l).rstrip()
        if s.strip() and not s.lstrip().startswith("*"):
            out.append(s)                      # the indentation stays: a label and the program's `end` are at column 0, a block's `end` is not
    return out


def section(lines, label):
    """The statements of the label `label:` up to the next label (at column 0) or the program's `end`; None if there is none."""
    for i, l in enumerate(lines):
        if l.rstrip() == label + ":":
            out = []
            for l2 in lines[i + 1:]:
                if re.match(r"^[A-Za-z][\w.]*:\s*$", l2) or re.match(r"^end\s*$", l2):
                    break
                out.append(l2.strip())
            return out
    return None


def labels(lines):
    return {l.rstrip()[:-1] for l in lines if re.match(r"^[A-Za-z][\w.]*:\s*$", l)}


def first(lines, pat):
    for i, l in enumerate(lines):
        if re.search(pat, l):
            return i
    return None


def ordered(lines, pats):
    """Each pattern is found on a line AFTER the line of the one before it (a later statement of the same shape does not count against an earlier one)."""
    at = -1
    for p in pats:
        k = first(lines[at + 1:], p)
        if k is None:
            return False
        at += 1 + k
    return True


def args_of(call):
    """The arguments of a call `name(a, b, c)` or `call name(a, b, c)` at its first bracket: split at the commas outside brackets and quotes."""
    s = call[call.index("(") + 1:]
    depth, q, cur, out = 1, None, "", []
    for ch in s:
        if q:
            cur += ch
            if ch == q:
                q = None
        elif ch in "'\"":
            q = ch
            cur += ch
        elif ch == "(":
            depth += 1
            cur += ch
        elif ch == ")":
            depth -= 1
            if depth == 0:
                out.append(cur.strip())
                return out
            cur += ch
        elif ch == "," and depth == 1:
            out.append(cur.strip())
            cur = ""
        else:
            cur += ch
    return None


def checks(p):
    rows = []

    def row(name, ok, detail=""):
        rows.append((name, bool(ok), detail))

    core = code(p["ced_core"])
    host = code(p["ced_edit"])
    host_s = [l.strip() for l in host]
    ctext = "\n".join(core)
    htext = "\n".join(host)

    row("E1 the engine is an internal subroutine $ced_core(op, st, a, out)",
        first(core, r"^\$internal$") is not None and first(core, r"^subroutine ced_core\(op, st, a, out\)$") is not None and first(core, r"^\$catalog \$ced_core$") is not None, ctext[:200])
    bad = [l.strip() for l in core if re.search(r"\bscreen\s+(open|close|clear)\b|\bscreen\s+get\b|\b(write|writeu|writev|writet|readu|readv|delete|deleteu|openseq|openpath|execute|chain|perform|writeseq)(?![\w.])|@sentence|\bopen\b\s+['\"a-z]", l, re.I)]
    row("E2 THE ENGINE NEVER OPENS OR CLOSES THE SCREEN AND NEVER WRITES A FILE: no screen open / close / clear, no write, delete, open, execute or @sentence", not bad, "\n".join(bad[:6]))
    dialogs = sorted(set(m.group(1).lower() for l in core for m in [re.search(r"\bscreen\s+([a-z]+)", l, re.I)] if m))
    row("E3 the only SCREEN statements of the engine are the three dialogues the editor has always used (ask, menu, msgbox)", dialogs == ["ask", "menu", "msgbox"], repr(dialogs))
    # the dispatch: every op the host sends has a case, and every case's handler label exists
    disp = section(core, "") if False else None
    main = []
    for l in core:
        if re.match(r"^[A-Za-z][\w.]*:\s*$", l):
            break
        main.append(l.strip())
    ops = [m.group(1) for l in main for m in [re.match(r"case op = '([\w.]+)'$", l)] if m]
    sent = sorted(set(re.findall(r"call \$ced_core\('([\w.]+)'", htext)) | set(re.findall(r"call \$ced_core\('([\w.]+)'", "\n".join(code(p["ide"])))))      # 31 Oct 26: the IDE is the second host
    row("E4 every op a host (the CED program, the IDE) sends is a case of the engine's dispatch (and the dispatch has no op that neither sends)", all(s in ops for s in sent) and sorted(set(ops) - set(sent)) == [],
        "sent %r, dispatched %r" % (sent, ops))
    lab = labels(core)
    gos = sorted(set(m.group(1) for l in core for m in [re.search(r"\bgosub ([\w.]+)", l)] if m))
    row("E5 every GOSUB of the engine has its label", all(g in lab for g in gos), "missing: %r" % [g for g in gos if g not in lab])
    # the state
    ld = section(core, "load.state") or []
    sto = section(core, "store.state") or []
    lk = [m.group(1) for l in ld for m in [re.match(r"^[\w.]+ = st\{'([\w.]+)'\}$", l)] if m]
    sk = [m.group(1) for l in sto for m in [re.match(r"^st\{'([\w.]+)'\} = [\w.]+$", l)] if m]
    row("E6 the engine's state is read back as it is kept: every key load.state reads, store.state writes (and the other way round, 'req' apart, which is the engine's answer and starts null)",
        sorted(lk) == sorted(set(sk) - {"req"}) and len(set(lk)) == len(lk) and len(set(sk)) == len(sk) and len(lk) >= 30, "load-only %r, store-only %r" % (sorted(set(lk) - set(sk)), sorted(set(sk) - set(lk) - {"req"})))
    row("E7 load.state makes req null, and the engine hands the host its answer (req) only through store.state", first(ld, r"^req = ''$") is not None and first(sto, r"^st\{'req'\} = req$") is not None)
    row("E8 the engine stores the state after every op (one store.state before the final return)",
        ordered(main, [r"gosub load\.state", r"begin case", r"end case", r"gosub store\.state", r"^return$"]), "\n".join(main[:30]))
    # saving
    hk = section(host, "handle.key") or []
    row("E9 the host writes when the engine asks (req = 'save') and not otherwise", ordered(hk, [r"call \$ced_core\('key', st, c\.key, out\)", r"gosub pull", r"if st\{'req'\} = 'save' then gosub save\.record"]), "\n".join(hk))
    hs = section(host, "save.record") or []
    row("E10 the host is the only writer, and writes only after the engine agreed (prep.save) and the edit gate said yes (K$EDIT.OK)",
        ordered(hs, [r"call \$ced_core\('prep\.save'", r"if not\(st\{'ok'\}\) then", r"^return$", r"kernel\(K\$EDIT\.OK", r"\$ced_core\('saved', st, -1", r"^return$", r"writeu c on fv, id", r"writeu rec\.text on fv, id"])
        and not any(re.search(r"\bwriteu?\b", l) for l in core), "\n".join(hs))
    row("E11 the outcome is reported on all three paths: refused before the write (-1), written (1), failed (0 and its status)",
        ordered(hs, [r"\$ced_core\('saved', st, -1", r"if save\.ok then", r"\$ced_core\('saved', st, 1", r"end else", r"\$ced_core\('saved', st, 0 : @fm : save\.status"]), "\n".join(hs))
    ky = section(core, "handle.key") or []
    row("E12 Ctrl-S only asks the host to write (req = 'save'); it does not write and does not change dirty", ordered(ky, [r"case c\.key = 'ctrl-s'", r"req = 'save'", r"case c\.key = 'ctrl-q'"]) and not any("gosub save" in l for l in core), "\n".join(ky[-14:]))
    qe = section(core, "quit.editor") or []
    row("E13 the Yes of the quit question marks the quit as waiting (pend.quit) and asks for the write BEFORE it returns; the quit goes on only from 'saved'",
        ordered(qe, [r"case qb = 1", r"req = 'save'", r"pend\.quit = @true", r"^return$", r"case qb = 2", r"gosub revert", r"done = @true"]), "\n".join(qe))
    sv = section(core, "op.saved") or []
    row("E14 'saved': a kept record ends a waiting quit (done, and quit.all when the Ctrl-Q asked), a failure does not, and the waiting mark is cleared on every path",
        ordered(sv, [r"case a<1> = 1", r"saved\.text = jbuild\(c\)", r"dirty = @false", r"kept = @true", r"if pend\.quit then", r"done = @true", r"case a<1> = 0", r"sysmsg\(12158, a<2>\)", r"end case", r"pend\.quit = @false"])
        and not any(re.search(r"\bdone = @true\b", l) for l in sv[next((n for n, l in enumerate(sv) if l == "case a<1> = 0"), len(sv)):]), "\n".join(sv))
    pv = section(core, "op.prep.save") or []
    row("E15 a refused record (the data mode, 12993) cancels a waiting quit", ordered(pv, [r"call \$recarr\('from'", r"if not\(rec\.ok\) then", r"sysmsg\(12993\)", r"pend\.quit = @false", r"st\{'ok'\} = @false"]), "\n".join(pv))
    # the host
    row("E16 the host does not change the data: no assignment to an element of c or of cur", not any(re.search(r"\b(cur|c)\{[^}]*\}\s*=", l) or re.search(r"\bins .* as (cur|c)\{", l) for l in host), "")
    row("E17 the host owns the screen: size check, break setting, open and close in this order (the engine is called only between them)",
        ordered(host_s, [r"\$sl_need\('CED'", r"\$tk_brk\('save'", r"screen open clear then", r"call \$ced_core\('init'", r"gosub handle\.key", r"^screen close$", r"\$tk_brk\('close', saved\.trap\)"])
        and sum(1 for l in host_s if l.startswith("screen open")) == 1 and sum(1 for l in host_s if l.startswith("screen close")) == 1, "")
    row("E18 the host reads c back after every call (a revert or an accepted AI edit gives the engine another one): pull reads st{'c'}, and result comes from the state",
        first(section(host, "pull") or [], r"^c = st\{'c'\}$") is not None and first(host_s, r"^result<1> = st\{'kept'\}$") is not None and first(host_s, r"^result<2> = st\{'quit\.all'\}$") is not None)
    row("E19 the end of the input is the host's: after 20 empty keys it asks the engine to 'abandon' (revert, quit all) and does not ask any question",
        ordered(hk, [r"if c\.key = '' then", r"eof\.count \+= 1", r"if eof\.count > 20 then", r"\$ced_core\('abandon'", r"^return$", r"eof\.count = 0"]), "\n".join(hk))
    row("E20 a window made smaller or bigger is the host's to find and the engine's to lay out again ('layout' with w and h)",
        ordered(section(host, "paint") or [], [r"gosub read\.layout", r"if w # ow or h # oh then", r"\$ced_core\('layout', st, w : @fm : h", r"gosub pull"]))
    # the callers
    miss = []
    for prog in PROGS:
        for l in code(p[prog]):
            if re.search(r"call \$cedit\(", l):
                a = args_of(l[l.index("call $cedit("):])
                if a is None or len(a) != 6:
                    miss.append("%s: %s" % (prog, l.strip()[:90]))
            if re.search(r"call \$ced_core\(", l):
                a = args_of(l[l.index("call $ced_core("):])
                if a is None or len(a) != 4:
                    miss.append("%s: %s" % (prog, l.strip()[:90]))
    n_cedit = sum(1 for prog in PROGS for l in code(p[prog]) if re.search(r"call \$cedit\(", l))
    n_core = sum(1 for prog in PROGS for l in code(p[prog]) if re.search(r"call \$ced_core\(", l))
    row("E21 every call of $cedit passes its six arguments and every call of $ced_core its four (a short call stops at run time with 'Argument count mismatch' and nothing else sees it)",
        not miss and n_cedit >= 2 and n_core >= 8, "%r (cedit calls %d, ced_core calls %d)" % (miss, n_cedit, n_core))
    # the IDE is the engine's second host (30 Oct 26, stage 2a): it no longer calls the CED program, it runs the engine in its own form and writes nothing
    ide = code(p["ide"])
    fr = []
    # 30 Oct 26 (stage 2b): the view is a pane of the tab and not a mode; the tab's text is the record, written back by the IDE's own labels, so the IDE asks the engine for init, key and layout
    #   only - the 'prep.save' / 'saved' / 'abandon' ops are the full-screen host's (a write to a file, a Ctrl-S, a question at the quit)
    for lab in ("fields.enter", "fields.leave", "fields.view.on", "fields.form", "fields.apply", "fields.sync", "fields.sync.tab", "fields.parse", "fields.rebuild", "fields.drop",
                "fields.esc", "fields.key", "fields.ai", "fields.after", "fields.writeback", "fields.fill", "fields.pull", "fields.show", "fields.label"):
        fr += section(ide, lab) or []
    sent_ide = sorted(set(re.findall(r"call \$ced_core\('([\w.]+)'", "\n".join(fr))))
    row("E22 the IDE no longer calls $cedit (stage 5 of the plan, reached by the in-form pane); its fields view calls the engine's init, key and layout (after a resize or a rebuild) and, for the AI line (stage 4), ai.request and ai.explain and nothing it writes",
        not any("$cedit" in l for l in ide) and sent_ide == ["ai.explain", "ai.request", "init", "key", "layout"]
        and not any(re.search(r"\b(write|writeu|writev|delete|readu|execute)(?![\w.])", l) for l in fr), repr(sent_ide))
    lay = [r"if fz\.st\{'w'\} \+ 0 # ew or fz\.st\{'h'\} \+ 0 # \(mh \+ 3\) then", r"call \$ced_core\('layout', fz\.st, ew : @fm : \(mh \+ 3\), fz\.out\)", r"fz\.st\{'path\.row'\} = ystat",
           r"fz\.st\{'msg\.row'\} = ystat"]
    row("E23 the pane lays the engine out again, when the form's size is not the one the engine was made for, before it shows the view (view.on) and in a form just made (form); a rebuilt engine is laid out for the form",
        all(ordered(section(ide, lab) or [], lay) for lab in ("fields.view.on", "fields.form"))
        and ordered(section(ide, "fields.rebuild") or [], [r"call \$ced_core\('init', fz\.st", r"call \$ced_core\('layout', fz\.st, ew : @fm : \(mh \+ 3\), fz\.out\)"]))
    return rows


def load():
    return {n: read(n) for n in PROGS}


def run():
    rows = checks(load())
    bad = 0
    for name, ok, detail in rows:
        print("  [%s] %s%s" % ("PASS" if ok else "FAIL", name, "" if ok else "   <- " + detail))
        bad += 0 if ok else 1
    print("test-cedcore-units: %d passed, %d failed" % (len(rows) - bad, bad))
    return 1 if bad or not rows else 0


def selftest():
    progs = load()
    if not all(ok for _, ok, _ in checks(progs)):
        print("  [FAIL] the real sources do not pass")
        return 1
    print("  [ok] the real sources pass")
    caught = missed = 0

    def mutant(name, key, old, new, prefix):
        nonlocal caught, missed
        p = dict(progs)
        if old not in p[key]:
            print("  [MISSED] %s: the text to change is not there" % name)
            missed += 1
            return
        p[key] = p[key].replace(old, new, 1)
        failing = [n for n, ok, _ in checks(p) if not ok]
        if failing and all(n.startswith(tuple(prefix.split("|"))) for n in failing):       # "E19|E4": the rows a mutant may fail
            print("  [caught] %s (%s)" % (name, ", ".join(n.split()[0] for n in failing)))
            caught += 1
        else:
            print("  [MISSED] %s: failing rows %s" % (name, failing))
            missed += 1

    mutant("the engine opens the screen", "ced_core", "   out = ''\n\n   gosub load.state", "   out = ''\n   screen open clear then null\n\n   gosub load.state", "E2|E3")
    mutant("the engine writes the record", "ced_core", "         req = 'save'                ;* the host writes the record", "         writeu c on fv, id\n         req = 'save'                ;* the host writes the record", "E")
    mutant("the engine executes a command", "ced_core", "   gosub store.state\n   return", "   execute 'LIST'\n   gosub store.state\n   return", "E2")
    mutant("the engine draws a label of its own", "ced_core", "   screen msgbox s returning b else b = 0", "   screen label f, 'x', s at 0,0\n   b = 0", "E3")
    mutant("an op the host sends has no case", "ced_core", "      case op = 'abandon'", "      case op = 'abandonx'", "E4")
    mutant("a gosub without its label", "ced_core", "      case c.key = 'f1' or c.key = '?'\n         gosub show.help", "      case c.key = 'f1' or c.key = '?'\n         gosub show.helpx", "E5")
    mutant("a state key is read but not kept", "ced_core", "   st{'clip.name'} = clip.name\n", "", "E6")
    mutant("a state key is kept but not read", "ced_core", "   clip.name = st{'clip.name'}\n", "", "E6")
    mutant("req is not made null", "ced_core", "   req = ''\n   clip.has = st{'clip.has'}", "   clip.has = st{'clip.has'}", "E7")
    mutant("the state is not stored", "ced_core", "   gosub store.state\n   return\n\n* ====", "   return\n\n* ====", "E8")
    mutant("the host writes without being asked", "ced_edit", "   if st{'req'} = 'save' then gosub save.record", "   gosub save.record", "E9")
    mutant("the host writes although the engine refused", "ced_edit", "   if not(st{'ok'}) then\n      gosub pull ", "   if 0 then\n      gosub pull ", "E10")
    mutant("the host skips the edit gate", "ced_edit", "if not(kernel(K$EDIT.OK, edit.p)) then", "if 0 then", "E10")
    mutant("the refusal of the gate is not reported", "ced_edit", "         call $ced_core('saved', st, -1, out)\n", "", "E")
    mutant("a failed write is reported as written", "ced_edit", "      call $ced_core('saved', st, 0 : @fm : save.status, out)", "      call $ced_core('saved', st, 1, out)", "E11")
    mutant("Ctrl-S writes in the engine", "ced_core", "         req = 'save'                ;* the host writes the record and tells us ('saved')", "         gosub save.record", "E")
    mutant("the quit does not wait for the write", "ced_core", "            req = 'save'\n            pend.quit = @true\n            return", "            req = 'save'\n            pend.quit = @true", "E13")
    mutant("a failed write ends the quit", "ced_core", "      case a<1> = 0\n         message.text = sysmsg(12158, a<2>)", "      case a<1> = 0\n         message.text = sysmsg(12158, a<2>)\n         done = @true", "E14")
    mutant("the waiting mark is kept", "ced_core", "   pend.quit = @false\n   return\n\n* ======================================================================\n* THE AI", "   return\n\n* ======================================================================\n* THE AI", "E14")
    mutant("a refusal leaves a quit waiting", "ced_core", "            message.text = sysmsg(12993)\n            pend.quit = @false", "            message.text = sysmsg(12993)", "E15")
    mutant("the host changes the data", "ced_edit", "   rec.text = st{'text'}", "   rec.text = st{'text'}\n   c{1} = rec.text", "E16")
    mutant("the host opens the screen before the size check", "ced_edit", "   call $sl_need('CED', LAYW, LAYH, need.msg, '')", "   screen open clear then null\n   call $sl_need('CED', LAYW, LAYH, need.msg, '')", "E17")
    mutant("the host does not read c back", "ced_edit", "pull:\n   c = st{'c'}", "pull:\n   c = c", "E18")
    mutant("the end of the input is not given up on", "ced_edit", "         call $ced_core('abandon', st, '', out)", "         null", "E19|E4")
    mutant("a new window size is not given to the engine", "ced_edit", "      call $ced_core('layout', st, w : @fm : h, out)", "      null", "E20|E4")
    mutant("a call of the engine with three arguments", "ced_edit", "call $ced_core('layout', st, w : @fm : h, out)", "call $ced_core('layout', st, w : @fm : h)", "E21")
    mutant("the IDE calls the engine with three arguments", "ide", "call $ced_core('init', fz.st, '', fz.out)", "call $ced_core('init', fz.st, '')", "E21")
    mutant("the IDE calls the CED program again", "ide", "   gosub fields.enter\n   return", "   call $cedit(fd.arr, '', '', 2, fz.title, fd.res)\n   gosub fields.enter\n   return", "E22")
    mutant("the IDE's fields view writes the record", "ide", "fields.after:\n   fz.st{'done'} = @false", "fields.after:\n   writeu fz.nc on fv, fd.id\n   fz.st{'done'} = @false", "E22")
    mutant("the IDE's view asks the engine to write", "ide", "   call $ced_core('key', fz.st, fz.k, fz.out)\n   gosub fields.after", "   call $ced_core('key', fz.st, fz.k, fz.out)\n   call $ced_core('prep.save', fz.st, '', fz.out)\n   gosub fields.after", "E22")
    mutant("the IDE's view never lays the engine out again", "ide", "   if fz.st{'w'} + 0 # ew or fz.st{'h'} + 0 # (mh + 3) then\n      call $ced_core('layout', fz.st, ew : @fm : (mh + 3), fz.out)\n      fz.st{'path.row'} = ystat\n      fz.st{'msg.row'} = ystat\n   end\n   f{'quiet'} = 1\n   screen set f, 'ed' visible 0",
           "   f{'quiet'} = 1\n   screen set f, 'ed' visible 0", "E23")
    mutant("a form made again keeps an engine laid out for the old size", "ide", "      if fz.st{'w'} + 0 # ew or fz.st{'h'} + 0 # (mh + 3) then\n         call $ced_core('layout', fz.st, ew : @fm : (mh + 3), fz.out)\n         fz.st{'path.row'} = ystat\n         fz.st{'msg.row'} = ystat\n      end\n      f{'quiet'} = 1",
           "      f{'quiet'} = 1", "E23")
    print("selftest: %d of %d mutants caught, %d missed" % (caught, caught + missed, missed))
    return 0 if missed == 0 else 1


if __name__ == "__main__":
    sys.exit(selftest() if "--selftest" in sys.argv else run())
