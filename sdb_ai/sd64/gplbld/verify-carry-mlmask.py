#!/usr/bin/env python3
#
# sandbox-mlmask.py - OPTION PICK.ML.CONV.MASK (openQM 4 release item, sheet 49).  No install, no sudo.
#
#   python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/sandbox-mlmask.py <dir> [--build]
#
# <dir> is a sandbox made by sandbox-fromtree.py.  With --build it is built first from THIS tree (it must be empty
# or absent); without it <dir> must already be built.  Exit 0 every row passed, 1 a row failed, 2 it could not run.
#
# START-HISTORY:
# 14 Oct 26 dm  New.  op_oconv.c and op_iconv.c (masked_decimal_conversion): under the option a left bracket after the
#               decimal places and flags starts a parenthesised fx element instead of asking for negative values in
#               round brackets.
# END-HISTORY
#
# The verdicts are relations, not remembered strings: the bracketed mask must give exactly what the same mask without
# brackets gives, the old reading must still be the old reading with the option off, and the option must turn the
# round bracket negative style off.

import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.path.join(HERE, "sandbox-fromtree.py")
ANSI = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]")
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
    say("sandbox-mlmask: CANNOT RUN - " + msg)
    sys.exit(2)


def sess(box, *cmds):
    say("    > " + " | ".join(cmds))
    p = subprocess.run([sys.executable, TOOL, box, "sess", os.path.join(box, "user_accounts")] + list(cmds),
                       capture_output=True, text=True, errors="replace", timeout=600)
    out = ANSI.sub("", p.stdout + p.stderr)
    return out.split(":TERM 200,9999", 1)[-1]


PROGRAM = """   crt 'OFF-NEG [':oconv(-1234, 'MR2('):']'
   crt 'OFF-POS [':oconv(1234, 'MR2('):']'
   execute 'OPTION PICK.ML.CONV.MASK'
   crt 'ON-NEG [':oconv(-1234, 'MR2('):']'
   crt 'ON-POS-PAREN [':oconv(1234, 'MR2(#10)'):']'
   crt 'ON-POS-PLAIN [':oconv(1234, 'MR2#10'):']'
   crt 'ON-NEG-PAREN [':oconv(-1234, 'MR2(#10)'):']'
   crt 'ON-NEG-PLAIN [':oconv(-1234, 'MR2#10'):']'
   crt 'ON-ML-PAREN [':oconv(1234, 'ML2(#10)'):']'
   crt 'ON-ML-PLAIN [':oconv(1234, 'ML2#10'):']'
   crt 'ON-WIDTH-PAREN [':oconv(1234, 'MR2P(12*)'):']'
   crt 'ON-WIDTH-PLAIN [':oconv(1234, 'MR2P12*'):']'
   crt 'ON-COMMA-PAREN [':oconv(1234567, 'MR2,(#12)'):']'
   crt 'ON-COMMA-PLAIN [':oconv(1234567, 'MR2,#12'):']'
   crt 'ON-ICONV-PAREN [':iconv('     12.34', 'MR2(#10)'):']'
   crt 'ON-ICONV-PLAIN [':iconv('     12.34', 'MR2#10'):']'
   crt 'ON-OTHER-NEG [':oconv(-1234, 'MR2<'):']'
end
"""


def value(out, tag):
    m = re.search(r"(?m)^%s \[(.*)\]\s*$" % re.escape(tag), out)
    return None if m is None else m.group(1)


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) != 1:
        bail("usage: sandbox-mlmask.py <dir> [--build]")
    box = os.path.abspath(args[0])
    sysd = os.path.join(box, "sys")
    say("sandbox-mlmask: sandbox %s" % box)
    if "--build" in sys.argv:
        if os.path.exists(box) and os.listdir(box):
            bail("%s is not empty" % box)
        r = subprocess.run([sys.executable, TOOL, box, "all"], capture_output=True, text=True, errors="replace", timeout=900)
        if "[FAIL]" in r.stdout or r.returncode != 0 or "[PASS] THIRD.COMPILE" not in r.stdout:
            bail("the sandbox build did not pass:\n" + r.stdout[-800:])
        say("sandbox-mlmask: built, bootstrap passed")
    elif not os.path.isfile(os.path.join(sysd, "bin", "sd")):
        bail("%s holds no built sandbox (use --build, or point it at one)" % box)
    subprocess.run([sys.executable, TOOL, box, "start"], capture_output=True, text=True, errors="replace", timeout=120)

    prog = "zzml" + RUN
    with open(os.path.join(sysd, "bp", prog), "w") as fh:
        fh.write(PROGRAM)

    say("\n--- OPTION PICK.ML.CONV.MASK ------------------------------------------------------------------------------")
    out = sess(box, "BASIC bp %s" % prog, "RUN bp %s" % prog)
    row("setup: the program compiled with no errors", "Compiled 1 program(s) with no errors" in out, out[-500:])
    v = {t: value(out, t) for t in (
        "OFF-NEG", "OFF-POS", "ON-NEG", "ON-POS-PAREN", "ON-POS-PLAIN", "ON-NEG-PAREN", "ON-NEG-PLAIN", "ON-ML-PAREN",
        "ON-ML-PLAIN", "ON-WIDTH-PAREN", "ON-WIDTH-PLAIN", "ON-COMMA-PAREN", "ON-COMMA-PLAIN", "ON-ICONV-PAREN",
        "ON-ICONV-PLAIN", "ON-OTHER-NEG")}
    row("every line the program printed was found (nothing was a run-time error)", all(x is not None for x in v.values()), repr(v))
    row("CONTROL, option off: MR2( asks for round bracket negatives, as ever: (12.34)",
        v["OFF-NEG"] == "(12.34)" and v["OFF-POS"] is not None and v["OFF-POS"].strip() == "12.34",
        repr((v["OFF-NEG"], v["OFF-POS"])))
    row("option on: MR2( is no longer the round bracket style - the value is -12.34",
        v["ON-NEG"] == "-12.34", repr(v["ON-NEG"]))
    row("option on: a parenthesised mask gives what the same mask gives without the brackets (MR2(#10) = MR2#10)",
        v["ON-POS-PAREN"] is not None and v["ON-POS-PAREN"] == v["ON-POS-PLAIN"] and len(v["ON-POS-PAREN"]) == 10
        and v["ON-POS-PAREN"].strip() == "12.34", repr((v["ON-POS-PAREN"], v["ON-POS-PLAIN"])))
    row("...for a negative value too", v["ON-NEG-PAREN"] == v["ON-NEG-PLAIN"] and v["ON-NEG-PAREN"].strip() == "-12.34",
        repr((v["ON-NEG-PAREN"], v["ON-NEG-PLAIN"])))
    row("...for ML (left justified)", v["ON-ML-PAREN"] == v["ON-ML-PLAIN"] and v["ON-ML-PAREN"].startswith("12.34")
        and len(v["ON-ML-PAREN"]) == 10, repr((v["ON-ML-PAREN"], v["ON-ML-PLAIN"])))
    row("...for the width and pad character style (12*)", v["ON-WIDTH-PAREN"] == v["ON-WIDTH-PLAIN"]
        and v["ON-WIDTH-PAREN"] is not None and len(v["ON-WIDTH-PAREN"]) == 12, repr((v["ON-WIDTH-PAREN"], v["ON-WIDTH-PLAIN"])))
    row("...after the thousands comma (MR2,(#12))", v["ON-COMMA-PAREN"] == v["ON-COMMA-PLAIN"]
        and v["ON-COMMA-PAREN"] is not None and "12,345.67" in v["ON-COMMA-PAREN"], repr((v["ON-COMMA-PAREN"], v["ON-COMMA-PLAIN"])))
    row("input conversion reads a parenthesised mask the same way (12.34 as 1234)",
        v["ON-ICONV-PAREN"] == v["ON-ICONV-PLAIN"] == "1234", repr((v["ON-ICONV-PAREN"], v["ON-ICONV-PLAIN"])))
    row("the other negative styles are not touched by the option (MR2< is <12.34>)", v["ON-OTHER-NEG"] == "<12.34>", repr(v["ON-OTHER-NEG"]))

    say("")
    say("sandbox-mlmask: %d passed, %d failed" % (passed, failed))
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
