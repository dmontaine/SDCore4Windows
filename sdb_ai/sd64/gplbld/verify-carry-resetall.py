#!/usr/bin/env python3
#
# sandbox-resetall.py - LOGTO name RESET ALL (QM4 Fixes item 30).  No install, no sudo.
#
#   python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/sandbox-resetall.py <dir> [--build]
#
# <dir> is a sandbox made by sandbox-fromtree.py.  With --build it is built first from THIS tree (it must be empty or
# absent); without it <dir> must already be built.  Exit 0 every row passed, 1 a row failed, 2 it could not run.
#
# START-HISTORY:
# 16 Oct 26 dm  New.  gpl.bp/cproc int.logto: RESET ALL; kernel.c K_RESET_ALL_EXIT; kernel(K$RESET.ALL).
# END-HISTORY
#
# It uses sandbox-gates.py's way of making ordinary sessions in fixture accounts (as sandbox-stacked.py does).  Two accounts:
# zzoff, whose bp holds the programs, and zzon, which the user is allowed into and which has a LOGIN paragraph (it runs a program
# that says at what command level it ran).  zzra1 runs zzra2 with EXECUTE ... TRAPPING ABORTS; zzra2 sets a variable in its unnamed
# common block and runs LOGTO with EXECUTE.  Three levels are stacked when the LOGTO runs: the prompt, the EXECUTE of zzra2 and
# the EXECUTE of the LOGTO.
#
#   RESET (CONTROL): the LOGTO's own level is restarted; the program that ran it, and the one that ran that, carry on.
#   RESET ALL:       neither carries on, TRAPPING ABORTS does not catch it, the session is in zzon at command level 1, the
#                    stacked levels' unnamed common blocks are gone, and the LOGIN of zzon ran at level 1.
#   At the prompt (level 1) RESET ALL is RESET.
#
# THE INSTRUMENT.  Every command sent and the lines returned are printed for the failing row.  A row for "did not carry on" is
# paired with a control row where the same marker line IS printed, so a missing line cannot be a program that never ran.
# NOT RUN HERE: the refusal in an API session (message 11392); a sandbox cannot host one.

import importlib.util
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("sandbox_gates", os.path.join(HERE, "sandbox-gates.py"))
g = importlib.util.module_from_spec(spec)
spec.loader.exec_module(g)
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
    say("sandbox-resetall: CANNOT RUN - " + msg)
    sys.exit(2)


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) != 1:
        bail("usage: sandbox-resetall.py <dir> [--build]")
    g.BOX = os.path.abspath(args[0])
    g.SYS = os.path.join(g.BOX, "sys")
    g.SD = os.path.join(g.SYS, "bin", "sd")
    say("sandbox-resetall: sandbox %s" % g.BOX)
    if "--build" in sys.argv:
        if os.path.exists(g.BOX) and os.listdir(g.BOX):
            bail("%s is not empty" % g.BOX)
        r = subprocess.run([sys.executable, g.TOOL, g.BOX, "all"], capture_output=True, text=True, errors="replace", timeout=900)
        if "[FAIL]" in r.stdout or r.returncode != 0 or "[PASS] THIRD.COMPILE" not in r.stdout:
            bail("the sandbox build did not pass:\n" + r.stdout[-800:])
        say("sandbox-resetall: built, bootstrap passed")
    elif not os.path.isfile(g.SD):
        bail("%s holds no built sandbox (use --build, or point it at one)" % g.BOX)
    subprocess.run([sys.executable, g.TOOL, g.BOX, "start"], capture_output=True, text=True, errors="replace", timeout=120)

    say("\n--- preparation: a CPROC that is not the install build, two fixture accounts, the programs ---------------------")
    g.prepare()
    for name in ("zzoff", "zzon"):
        g.build_account(name)
    off = os.path.join(g.BOX, "user_accounts", "zzoff")
    on = os.path.join(g.BOX, "user_accounts", "zzon")

    def prog(acct_dir, name, *lines):
        g.put(os.path.join(acct_dir, "bp", name), "\n".join(list(lines) + [""]))

    # the LOGIN of zzon: a paragraph that runs a program saying at what command level it ran
    prog(on, "zzlg", "   crt 'LOGIN RAN LEVEL ':@level", "end")
    out = g.plain("zzon", ["BASIC bp zzlg"])
    if not g.has(out, r"^Compiled 1 program\(s\) with no errors"):
        bail("the LOGIN program did not compile in zzon:\n" + "\n".join(out[-6:]))
    g.put(os.path.join(g.SYS, "bp", "zzvoc"), "\n".join([
        "$internal",
        "   openpath '%s' to v else crt 'VOC open failed' ; stop" % os.path.join(on, "voc"),
        "   write 'PA':@fm:'RUN BP ZZLG' to v, 'login'",
        "   crt 'VOC done'", "end", ""]))
    out = g.adm(["BASIC bp zzvoc", "RUN bp zzvoc"], internal=True)
    if not g.has(out, r"^VOC done$"):
        bail("the LOGIN paragraph was not made:\n" + "\n".join(out[-6:]))

    for tag, cmd in (("zzraa", "LOGTO zzon RESET ALL"), ("zzrab", "LOGTO zzon RESET")):
        prog(off, tag + "1", "   common stale", "   crt 'OUTER START'", "   execute 'RUN BP %s2' trapping aborts" % tag.upper(),
             "   crt 'OUTER AFTER'", "end")
        prog(off, tag + "2", "   common stale", "   stale = 'STALE2'", "   crt 'MID START LEVEL ':@level",
             "   execute '%s'" % cmd, "   crt 'MID AFTER'", "end")
    # what a level started afterwards finds: the level it ran at, the unnamed common block, and where the session is.  The probes
    # are in both accounts: after the LOGTO the session is in zzon and runs them from there.
    for acct_dir in (off, on):
        prog(acct_dir, "zzra3", "   common stale", "   crt 'PROBE LEVEL ':@level", "   crt 'PROBE STALE[':stale:']'", "   crt 'PROBE PATH ':@path", "end")
        prog(acct_dir, "zzra4", "   execute 'RUN BP ZZRA3' capturing o", "   convert @fm to char(10) in o", "   crt o", "end")
    out = g.plain("zzoff", ["BASIC bp zzraa1 zzraa2 zzrab1 zzrab2 zzra3 zzra4"])
    n = len([l for l in out if re.search(r"^Compiled 6 program\(s\) with no errors", l)])
    out2 = g.plain("zzon", ["BASIC bp zzra3 zzra4"])
    n2 = len([l for l in out2 if re.search(r"^Compiled 2 program\(s\) with no errors", l)])
    if n != 1 or n2 != 1:
        bail("the programs did not compile:\n" + "\n".join(out[-8:] + out2[-6:]))

    def show(lines):
        return "\n".join(lines[-14:])

    say("\n--- CONTROL: RESET, not RESET ALL, from the third level ------------------------------------------------------")
    out = g.plain("zzoff", ["RUN bp zzrab1", "RUN bp zzra4"])
    row("the instrument: both programs started (OUTER START, MID START LEVEL 2)", g.has(out, r"^OUTER START$") and g.has(out, r"^MID START LEVEL 2$"), show(out))
    row("CONTROL  with RESET the program that ran the LOGTO carries on (MID AFTER) and so does the outer one (OUTER AFTER)",
        g.has(out, r"^MID AFTER$") and g.has(out, r"^OUTER AFTER$"), show(out))
    row("CONTROL  with RESET the LOGIN of zzon ran at the level of the LOGTO (LEVEL 3)", g.has(out, r"^LOGIN RAN LEVEL 3$"), show(out))
    row("CONTROL  the session is in zzon afterwards", any(re.match(r"^PROBE PATH .*/zzon$", l) for l in out), show(out))

    say("\n--- RESET ALL from the third level -----------------------------------------------------------------------------")
    out = g.plain("zzoff", ["RUN bp zzraa1", "RUN bp zzra4"])
    row("the instrument: both programs started (OUTER START, MID START LEVEL 2)", g.has(out, r"^OUTER START$") and g.has(out, r"^MID START LEVEL 2$"), show(out))
    row("30  the program that ran the LOGTO does not carry on (no MID AFTER)", not g.has(out, r"^MID AFTER$"), show(out))
    row("30  the outer program does not carry on either, TRAPPING ABORTS did not catch it (no OUTER AFTER)",
        not g.has(out, r"^OUTER AFTER$"), show(out))
    row("30  the LOGIN of zzon ran, at command level 1", g.has(out, r"^LOGIN RAN LEVEL 1$"), show(out))
    row("30  the session is in zzon afterwards", any(re.match(r"^PROBE PATH .*/zzon$", l) for l in out), show(out))
    row("30  a command run afterwards with EXECUTE is at level 2 again (the levels were counted back)",
        g.has(out, r"^PROBE LEVEL 2$"), show(out))
    row("30  the unnamed common block of that level is empty (the old level's STALE2 is gone)",
        g.has(out, r"^PROBE STALE\[0\]$") and not g.has(out, r"STALE2"), show(out))

    say("\n--- RESET ALL at the prompt: nothing is stacked, so it is RESET ----------------------------------------------")
    out = g.plain("zzoff", ["LOGTO zzon RESET ALL", "ZZKF"])
    fl = g.flags(out)
    row("30  at command level 1 it enters zzon and runs its LOGIN there", g.has(out, r"^LOGIN RAN LEVEL 1$") and fl is not None, show(out))
    out = g.plain("zzoff", ["LOGTO nosuchaccount RESET ALL", "RUN bp zzra3"])
    row("CONTROL  a LOGTO that is refused (no such account) leaves the session where it was, whatever follows",
        any(re.match(r"^PROBE PATH .*/zzoff$", l) for l in out), show(out))

    for acct_dir, names in ((off, ("zzraa1", "zzraa2", "zzrab1", "zzrab2", "zzra3", "zzra4")), (on, ("zzlg", "zzra3", "zzra4"))):
        for p in names:
            for q in (os.path.join(acct_dir, "bp", p), os.path.join(acct_dir, "bp.out", p)):
                if os.path.exists(q):
                    os.remove(q)
    say("")
    say("sandbox-resetall: %d passed, %d failed" % (passed, failed))
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
