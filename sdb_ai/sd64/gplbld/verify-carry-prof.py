#!/usr/bin/env python3
#
# sandbox-prof.py - the PROFILER command, the application event profiler (openQM 4, QM4 gaps 66 and 203).  No install, no sudo.
#
#   python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/sandbox-prof.py <dir> [--build]
#
# <dir> is a sandbox made by sandbox-fromtree.py.  With --build it is built first from THIS tree (it must be empty
# or absent); without it <dir> must already be built.  Exit 0 every row passed, 1 a row failed, 2 it could not run.
#
# START-HISTORY:
# 16 Oct 26 dm  New.  profiler.c (prof_event, prof_set, prof_dump), the hooks in op_dio1/op_dio3/op_seqio/op_jumps/op_exec/objprog,
#               K_PROFILER and K_PROFILER_USER in op_kernel.c, EVT_PROFILER in kernel.c, gpl.bp/profiler.
# END-HISTORY
#
# It uses sandbox-gates.py's way of making ordinary sessions in a fixture account (zzoff), by loading that file.  A program in zzoff
# does a known set of things: one OPEN, three READs (two READ and one READV), one WRITE, one DELETE, two CALLs of a subroutine, an OPENSEQ
# to make and one to read a file, a WRITESEQ, a READSEQ and an EXECUTE.  THE INSTRUMENT.  The profile is read raw (a probe program prints
# the $ipc record) and judged for THAT program only, since the command processor and the verbs it runs are in the profile too.  The
# controls are the program run before PROFILER ON and after PROFILER OFF (it must not be counted), PROFILER ON with a list of events (only
# those), and the refusal of another user to an ordinary session.  The administrator profiles another running session in the last part.

import importlib.util
import os
import re
import subprocess
import sys
import threading
import time

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("sandbox_gates", os.path.join(HERE, "sandbox-gates.py"))
g = importlib.util.module_from_spec(spec)
spec.loader.exec_module(g)
RUN = "%05d" % (os.getpid() % 100000)
passed = failed = 0


def say(s=""):
    print(s)


def row(name, ok, detail=""):
    global passed, failed
    if ok:
        passed += 1
        say("  [PASS] " + name)
    else:
        failed += 1
        say("  [FAIL] " + name + ("   <- " + detail if detail else ""))


def bail(msg):
    say("sandbox-prof: CANNOT RUN - " + msg)
    sys.exit(2)


def table(lines, prog):
    """The entries of program prog in the probe's PDUMP line: {(type, qualifier): [(line, count), ...]}"""
    for ln in lines:
        if ln.startswith("PDUMP "):
            out = {}
            for ent in ln[6:].split("|")[1:]:
                f = ent.split("^")
                if len(f) == 5 and (f[2] == prog or f[2].endswith("/" + prog)):    # a user's program is named by its object pathname
                    out.setdefault((f[0], f[1]), []).append((int(f[3]), int(f[4])))
            return out
    return None


def cnt(t, ty, q=None):
    """The events of type ty (on q, when it is given) in the table t"""
    return sum(c for (tt, qq), v in t.items() if tt == ty and (q is None or qq == q) for (ln, c) in v)


def lns(t, ty, q):
    return sorted(ln for (ln, c) in t.get((ty, q), []))


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) != 1:
        bail("usage: sandbox-prof.py <dir> [--build]")
    g.BOX = os.path.abspath(args[0])
    g.SYS = os.path.join(g.BOX, "sys")
    g.SD = os.path.join(g.SYS, "bin", "sd")
    say("sandbox-prof: sandbox %s" % g.BOX)
    if "--build" in sys.argv:
        if os.path.exists(g.BOX) and os.listdir(g.BOX):
            bail("%s is not empty" % g.BOX)
        r = subprocess.run([sys.executable, g.TOOL, g.BOX, "all"], capture_output=True, text=True, errors="replace", timeout=900)
        if "[FAIL]" in r.stdout or r.returncode != 0 or "[PASS] THIRD.COMPILE" not in r.stdout:
            bail("the sandbox build did not pass:\n" + r.stdout[-800:])
        say("sandbox-prof: built, bootstrap passed")
    elif not os.path.isfile(g.SD):
        bail("%s holds no built sandbox (use --build, or point it at one)" % g.BOX)
    subprocess.run([sys.executable, g.TOOL, g.BOX, "start"], capture_output=True, text=True, errors="replace", timeout=120)

    say("\n--- preparation: a CPROC that is not the install build, the probes, one fixture account ----------------------")
    g.prepare()
    g.build_account("zzoff")
    d = os.path.join(g.BOX, "user_accounts", "zzoff")
    # a probe that prints the profile the kernel put in $ipc for this session, and a VOC entry for it in zzoff
    g.put(os.path.join(g.SYS, "gpl.bp", "zzpdump"), "\n".join([
        "$internal", "program zzpdump", "$catalog $zzpdump", "$include syscom.h",
        "   read s from ipc.f, 'F':@userno else crt 'PDUMP none' ; stop",
        "   crt 'PDUMP ':convert(@fm:@vm, '|^', s)", "end", ""]))
    out = g.adm(["BASIC gpl.bp zzpdump"], internal=True)
    if not g.has(out, r"^Compiled 1 program\(s\) with no errors"):
        bail("the probe did not compile:\n" + "\n".join(out[-6:]))
    g.put(os.path.join(g.SYS, "bp", "zzfixp"), "\n".join([
        "$internal",
        "   openpath '%s' to v else crt 'FIXP open voc failed' ; stop" % os.path.join(d, "voc"),
        "   write 'V':@fm:'CA':@fm:'$zzpdump' to v, 'zzpdump'",
        "   crt 'FIXP done'", "end", ""]))
    out = g.adm(["BASIC bp zzfixp", "RUN bp zzfixp"], internal=True)
    if not g.has(out, r"^FIXP done$"):
        bail("the zzpdump verb was not made:\n" + "\n".join(out[-6:]))

    fil, sub, main_p, loop_p = "zzpf" + RUN, "zzprs" + RUN, "zzprm" + RUN, "zzprl" + RUN
    seq = "zzseq" + RUN + ".txt"
    g.put(os.path.join(d, "bp", sub), "subroutine %s\n   return\nend\n" % sub)
    g.put(os.path.join(d, "bp", main_p), "\n".join([
        "   open '%s' to f else crt 'MAIN open failed' ; stop" % fil,
        "   write 'a' to f, 'k1'",
        "   read r from f, 'k1' else null",
        "   read r from f, 'k1' else null",
        "   readv x from f, 'k1', 1 else null",
        "   delete f, 'k1'",
        "   call %s" % sub,
        "   call %s" % sub,
        "   openseq 'bp', '%s' to sf else" % seq,
        "      create sf else crt 'MAIN create failed'",
        "   end",
        "   weofseq sf",
        "   writeseq 'line1' to sf else crt 'MAIN writeseq failed'",
        "   closeseq sf",
        "   openseq 'bp', '%s' to sf then" % seq,
        "      readseq l from sf else crt 'MAIN readseq failed'",
        "      closeseq sf",
        "   end else crt 'MAIN openseq 2 failed'",
        "   execute 'WHO' capturing w",
        "   crt 'MAIN done'", "end", ""]))
    # a program for the administrator to watch: reads a file every tenth of a second for a while
    g.put(os.path.join(d, "bp", loop_p), "\n".join([
        "   open '%s' to f else crt 'LOOP open failed' ; stop" % fil,
        "   crt 'LOOP USER ':@userno",
        "   for i = 1 to 90",
        "      read r from f, 'k1' else null",
        "      nap 100",
        "   next i",
        "   crt 'LOOP DONE'", "end", ""]))
    out = g.plain("zzoff", ["CREATE.FILE " + fil, "BASIC bp " + sub, "BASIC bp " + main_p, "BASIC bp " + loop_p, "CATALOG bp " + sub])
    row("setup: the file, the subroutine and both programs", len([l for l in out if re.search(r"^Compiled 1 program\(s\) with no errors", l)]) == 3, "\n".join(out[-6:]))

    say("\n--- PROFILER ON, a program, PROFILER OFF ------------------------------------------------------------------")
    out = g.plain("zzoff", ["RUN bp " + main_p, "PROFILER ON", "RUN bp " + main_p, "PROFILER OFF", "RUN bp " + main_p, "ZZPDUMP"])
    on = next((l for l in out if l.startswith("Profiler on for user")), None)
    off = next((l for l in out if l.startswith("Profiler off for user")), None)
    row("PROFILER ON says which user it is on for", on is not None, repr(out[:6]))
    m = re.match(r"Profiler off for user (\d+): (\d+) events in (\d+) entries", off or "")
    row("PROFILER OFF says how many events and entries it found", m is not None and int(m.group(2)) > 0 and int(m.group(3)) > 0, repr(off))
    t = table(out, main_p)
    row("the table is there (the probe read the record)", t is not None, repr(out[-3:]))
    t = t or {}
    row("CONTROL: the program run before PROFILER ON and after PROFILER OFF is not counted: its OPEN is counted once, not three times",
        cnt(t, "OPEN", fil) == 1, repr(t.get(("OPEN", fil))))
    row("READ: the two READs and the READV, 3 on the file, at lines 3, 4 and 5", cnt(t, "READ", fil) == 3 and lns(t, "READ", fil) == [3, 4, 5], repr(t.get(("READ", fil))))
    row("WRITE 1 and DELETE 1 on the file", cnt(t, "WRITE", fil) == 1 and cnt(t, "DELETE", fil) == 1,
        repr((t.get(("WRITE", fil)), t.get(("DELETE", fil)))))
    row("CALL: the subroutine twice, at lines 7 and 8", cnt(t, "CALL", sub) == 2 and lns(t, "CALL", sub) == [7, 8], repr(t.get(("CALL", sub))))
    row("OPENSEQ twice, WRITESEQ once and READSEQ once, on the file the program named",
        cnt(t, "OPENSEQ") == 2 and cnt(t, "WRITESEQ") == 1 and cnt(t, "READSEQ") == 1 and any(seq in q for (ty, q) in t if ty == "OPENSEQ"), repr(t))
    row("EXECUTE: the command, once", cnt(t, "EXECUTE", "WHO") == 1, repr([k for k in t if k[0] == "EXECUTE"]))
    row("the line numbers are the program's own: OPEN on line 1, WRITE on 2, DELETE on 6",
        lns(t, "OPEN", fil) == [1] and lns(t, "WRITE", fil) == [2] and lns(t, "DELETE", fil) == [6],
        repr((t.get(("OPEN", fil)), t.get(("WRITE", fil)), t.get(("DELETE", fil)))))

    say("\n--- PROFILER ON with a list of events ----------------------------------------------------------------------------")
    out = g.plain("zzoff", ["PROFILER ON READ WRITE", "RUN bp " + main_p, "PROFILER OFF", "ZZPDUMP"])
    t = table(out, main_p) or {}
    types = sorted({ty for (ty, q) in t})
    row("only READ and WRITE are logged: %s" % types, types == ["READ", "WRITE"] and cnt(t, "READ", fil) == 3, repr(types))

    say("\n--- PROFILER DISPLAY ----------------------------------------------------------------------------------------------")
    run = ["PROFILER ON", "RUN bp " + main_p, "PROFILER OFF", "PROFILER DISPLAY"]
    out = g.plain("zzoff", run + ["Q"])
    types = [re.sub(r"^\s*\d+\s+\d+\s+", "", l).strip() for l in out if re.match(r"^\s*\d+\s+\d+\s+[A-Z]+\s*$", l)]
    row("level 1 lists the event types with their counts: %s" % types, "READ" in types and "CALL" in types and "EXECUTE" in types, repr(out[:14]))
    if "READ" in types:
        ix = types.index("READ") + 1
        out = g.plain("zzoff", run + [str(ix), "Q"])
        part = "\n".join(out).split("READ events, by name", 1)[-1]
        row("level 2, after choosing READ, lists what the events were on, with the file and its count 3",
            re.search(r"(?m)^\s*\d+\s+3\s+" + re.escape(fil) + r"\s*$", part) is not None, part[:300])
        names = [re.sub(r"^\s*\d+\s+\d+\s+", "", l).strip() for l in part.splitlines() if re.match(r"^\s*\d+\s+\d+\s+\S+\s*$", l)]
        if fil in names:
            jx = names.index(fil) + 1
            out = g.plain("zzoff", run + [str(ix), str(jx), "Q"])
            part = "\n".join(out).split("by program", 1)[-1]
            row("level 3 lists the programs that did them: ours, with 3", re.search(r"(?m)^\s*\d+\s+3\s+\S*" + re.escape(main_p) + r"\s*$", part) is not None, part[:300])
            progs = [re.sub(r"^\s*\d+\s+\d+\s+", "", l).strip() for l in part.splitlines() if re.match(r"^\s*\d+\s+\d+\s+\S+\s*$", l)]
            ours = [p for p in progs if p.endswith(main_p)]
            if ours:
                kx = progs.index(ours[0]) + 1
                out = g.plain("zzoff", run + [str(ix), str(jx), str(kx), "Q"])
                part = "\n".join(out).split("by line number", 1)[-1]
                row("level 4 lists the line numbers, 3, 4 and 5, one READ each",
                    all(re.search(r"(?m)^\s*\d+\s+1\s+%d\s*$" % ln, part) for ln in (3, 4, 5)), part[:300])
                out = g.plain("zzoff", run + [str(ix), str(jx), str(kx), "B", "B", "B", "Q"])
                row("B goes back a level at a time, down to the event types again",
                    "\n".join(out).count("Event types") >= 2, repr(out[-6:]))
            else:
                row("level 4 (the program was not found at level 3)", False, repr(progs))
        else:
            row("level 3 (the file was not found at level 2)", False, repr(names))

    out = g.plain("zzoff", ["PROFILER ON USER 99"])
    row("an ordinary session is refused another user's process", g.has(out, r"Only the administrator can profile another user"), repr(out[-3:]))

    say("\n--- the administrator profiles another running session ------------------------------------------------------------")
    argv = [g.SD, "-azzoff"]
    e = g.env(False)
    proc = subprocess.Popen(argv, cwd=d, env=e, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, errors="replace")
    seen = []
    lock = threading.Lock()

    def reader():
        for ln in proc.stdout:
            with lock:
                seen.append(re.sub(r"\x1b\[[0-9;?]*[A-Za-z]", "", ln).rstrip())
    th = threading.Thread(target=reader, daemon=True)
    th.start()
    proc.stdin.write("\nTERM 200,9999\nRUN bp %s\n" % loop_p)
    proc.stdin.flush()
    other = None
    for _ in range(100):
        with lock:
            for ln in seen:
                m = re.match(r"^LOOP USER (\d+)", ln)
                if m:
                    other = int(m.group(1))
        if other is not None:
            break
        time.sleep(0.2)
    row("the session to be profiled is running (its user number is %s)" % other, other is not None, repr(seen[-5:]))
    if other is not None:
        out = g.adm(["PROFILER ON USER %d READ" % other])
        row("the administrator starts the profiler in it", g.has(out, r"^Profiler on for user %d$" % other), repr(out))
        time.sleep(2.0)
        out = g.adm(["PROFILER OFF USER %d" % other])
        row("...stops it, and the session wrote its table: events and entries are reported",
            g.has(out, r"^Profiler off for user %d: [1-9]\d* events in [1-9]\d* entries$" % other), repr(out))
        part = g.adm(["PROFILER DISPLAY USER %d" % other, "1", "1", "Q"])
        row("DISPLAY USER n shows what the other session did: the loop program's READs of the file",
            g.has(part, r"^\s*\d+\s+[1-9]\d*\s+" + re.escape(fil) + r"\s*$"), repr(part[:20]))
    try:
        proc.stdin.write("OFF\n")
        proc.stdin.flush()
    except OSError:
        pass
    try:
        proc.wait(timeout=30)
    except subprocess.TimeoutExpired:
        proc.kill()

    g.plain("zzoff", ["DELETE.FILE " + fil, "DELETE.CATALOG " + sub])
    for p in (main_p, loop_p, sub, seq):
        for q in (os.path.join(d, "bp", p), os.path.join(d, "bp.out", p)):
            if os.path.exists(q):
                os.remove(q)
    say("")
    say("sandbox-prof: %d passed, %d failed" % (passed, failed))
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
