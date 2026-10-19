#!/usr/bin/env python3
#
# sandbox-stacked.py - OPTION STACKED.ACCOUNT (openQM 4, QM4 gap 248).  No install, no sudo.
#
#   python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/sandbox-stacked.py <dir> [--build]
#
# <dir> is a sandbox made by sandbox-fromtree.py.  With --build it is built first from THIS tree (it must be empty
# or absent); without it <dir> must already be built.  Exit 0 every row passed, 1 a row failed, 2 it could not run.
#
# START-HISTORY:
# 16 Oct 26 dm  New.  gpl.bp/cproc: an executed command level holds the account it began in (working directory, name, the two
#               OS-access switches) and revert.account puts them back, under the option, when the command ends.
# END-HISTORY
#
# It uses sandbox-gates.py's way of making ordinary sessions in fixture accounts (a CPROC that is not the install build, a register
# record whose group the sandbox user is in, sessions started with sd -a<account>), by loading that file and using its functions.
# Two accounts: zzoff (SH and OS.EXECUTE off, and a VOC verb zzoffonly that no other account has) and zzon (both on).  A program in
# zzoff runs EXECUTE 'LOGTO zzon' and then looks at where the session is: @path, the two switches (the ZZKF probe) and whether the
# verb only zzoff's VOC holds still runs.  THE INSTRUMENT.  Every command sent and the lines returned are printed.  The controls: the
# option off (the session stays in zzon, as it always did), the option on with an EXECUTE that does not change account, and a LOGTO
# typed at the prompt with the option on (which only EXECUTE reverts).

import importlib.util
import os
import re
import subprocess
import sys

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
    say("sandbox-stacked: CANNOT RUN - " + msg)
    sys.exit(2)


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) != 1:
        bail("usage: sandbox-stacked.py <dir> [--build]")
    g.BOX = os.path.abspath(args[0])
    g.SYS = os.path.join(g.BOX, "sys")
    g.SD = os.path.join(g.SYS, "bin", "sd")
    say("sandbox-stacked: sandbox %s" % g.BOX)
    if "--build" in sys.argv:
        if os.path.exists(g.BOX) and os.listdir(g.BOX):
            bail("%s is not empty" % g.BOX)
        r = subprocess.run([sys.executable, g.TOOL, g.BOX, "all"], capture_output=True, text=True, errors="replace", timeout=900)
        if "[FAIL]" in r.stdout or r.returncode != 0 or "[PASS] THIRD.COMPILE" not in r.stdout:
            bail("the sandbox build did not pass:\n" + r.stdout[-800:])
        say("sandbox-stacked: built, bootstrap passed")
    elif not os.path.isfile(g.SD):
        bail("%s holds no built sandbox (use --build, or point it at one)" % g.BOX)
    subprocess.run([sys.executable, g.TOOL, g.BOX, "start"], capture_output=True, text=True, errors="replace", timeout=120)

    say("\n--- preparation: a CPROC that is not the install build, the probes, two fixture accounts --------------------")
    g.prepare()
    for name in ("zzoff", "zzon"):
        g.build_account(name)
    # a verb only zzoff's VOC holds: the same probe as ZZKF under another name
    g.put(os.path.join(g.SYS, "bp", "zzfix2"), "\n".join([
        "$internal",
        "   openpath '%s' to v else crt 'FIX2 open voc failed' ; stop" % os.path.join(g.BOX, "user_accounts", "zzoff", "voc"),
        "   write 'V':@fm:'CA':@fm:'$zzkf' to v, 'zzoffonly'",
        "   crt 'FIX2 done'", "end", ""]))
    out = g.adm(["BASIC bp zzfix2", "RUN bp zzfix2"], internal=True)
    if not g.has(out, r"^FIX2 done$"):
        bail("the zzoffonly verb was not made:\n" + "\n".join(out[-6:]))

    prog = "zzstk" + RUN
    d = os.path.join(g.BOX, "user_accounts", "zzoff")
    g.put(os.path.join(d, "bp", prog), "\n".join([
        "   execute 'LOGTO zzon'",
        "   crt 'PATH ':@path",
        "   execute 'ZZKF' capturing kf",
        "   crt 'FLAGS ':trim(kf)",
        "   execute 'ZZOFFONLY' capturing o2",
        "   crt 'OFFONLY ':(if index(o2, 'KFLAGS', 1) then 'RAN' else 'UNKNOWN')",
        "end", ""]))
    prog2 = "zzstn" + RUN
    g.put(os.path.join(d, "bp", prog2), "\n".join([
        "   execute 'ZZKF' capturing kf",
        "   crt 'PATH ':@path",
        "   crt 'FLAGS ':trim(kf)",
        "end", ""]))
    out = g.plain("zzoff", ["BASIC bp " + prog, "BASIC bp " + prog2])
    row("setup: both programs compiled with no errors", len([l for l in out if re.search(r"^Compiled 1 program\(s\) with no errors", l)]) == 2, "\n".join(out[-6:]))

    def info(lines):
        path = next((l[5:].strip() for l in lines if l.startswith("PATH ")), None)
        fl = next((l for l in lines if l.startswith("FLAGS ")), "")
        m = re.search(r"sh=(\d+) osx=(\d+)", fl)
        return path, (m.groups() if m else None), next((l[8:].strip() for l in lines if l.startswith("OFFONLY ")), None)

    say("\n--- the option off: the process stays in the account the command went to, as it always did ----------------------")
    out = g.plain("zzoff", ["RUN bp " + prog])
    path, sw, vo = info(out)
    row("CONTROL, the option off: after EXECUTE 'LOGTO zzon' the session is in zzon", path is not None and path.endswith("/zzon"), repr(path))
    row("...with zzon's switches (sh=1 osx=1)", sw == ("1", "1"), repr(sw))
    row("...and zzoff's own verb is not known there", vo == "UNKNOWN", repr(vo))

    say("\n--- OPTION STACKED.ACCOUNT -----------------------------------------------------------------------------------")
    out = g.plain("zzoff", ["OPTION STACKED.ACCOUNT", "RUN bp " + prog])
    path, sw, vo = info(out)
    row("after EXECUTE 'LOGTO zzon' the session is back in zzoff", path is not None and path.endswith("/zzoff"), repr(path))
    row("...with zzoff's switches: what zzon granted is NOT carried back (sh=0 osx=0)", sw == ("0", "0"), repr(sw))
    row("...and zzoff's own verb is known again (its VOC is the one in use)", vo == "RAN", repr(vo))

    out = g.plain("zzoff", ["OPTION STACKED.ACCOUNT", "RUN bp " + prog2])
    path, sw, vo = info(out)
    row("CONTROL, the option on and an EXECUTE that does not change account: nothing moves", path is not None and path.endswith("/zzoff") and sw == ("0", "0"), repr((path, sw)))

    out = g.plain("zzoff", ["OPTION STACKED.ACCOUNT", "LOGTO zzon", "ZZKF"])
    fl = g.flags(out)
    row("CONTROL, the option on and a LOGTO typed at the prompt (no EXECUTE): the session stays in zzon (sh=1 osx=1)",
        fl is not None and fl[1] == "1" and fl[2] == "1", repr(fl))

    for p in (prog, prog2):
        for q in (os.path.join(d, "bp", p), os.path.join(d, "bp.out", p)):
            if os.path.exists(q):
                os.remove(q)
    say("")
    say("sandbox-stacked: %d passed, %d failed" % (passed, failed))
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
