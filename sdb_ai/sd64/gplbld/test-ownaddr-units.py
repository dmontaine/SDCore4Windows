#!/usr/bin/env python3
# test-ownaddr-units.py - RELEASE_1.1 344, from Linux 02507803 (S.264, 18 Nov 2026; owner: "yes" to closing it in the code).  A connection
# from one of THIS machine's own addresses came from this machine (an ssh tunnel aimed at its own network address is the case), so APISRVR's
# SDSYS sign-in sends it to the local door (RELEASE_1.1 339) instead of remote.sdsys api's address list.
#   O   gplsrc/sd_ownaddr.c built with -Wall -Wextra -Werror together with gplbld/verify-ownaddr.c by the MSYS gcc that builds sd (the
#       server's POSIX runtime: getifaddrs, inet_pton) and driven as a black box: equal addresses match as BITS (IPv4, IPv6 in any
#       compression, IPv4-mapped IPv6 as its IPv4 form), different ones do not, a non-address and a leading zero are -1, an empty list is 0;
#       the LIVE call answers 1 for 127.0.0.1 and 0 for a TEST-NET-3 address (203.0.113.1)
#   K   the key is 176 in keys.h and int$keys.h; op_kernel.c answers it from sd_own_address(); gpl.src lists sd_ownaddr
#   A   apisrvr asks kernel(K$OWN.ADDR, api.loop) and an own-address peer takes the local door (the loopback branch), before the remote list
# Windows differs from Linux's guard in form only: no !peer_local here (APISRVR tests the peer itself), and the compiler is MSYS2's.
# FREE CHECK: exit 2 (NO TREE) without the MSYS gcc.  It cannot say a real tunnel is refused: that is a VM row.
#
#   python C:/Users/Don/SDCoreProject/SDCore4Windows/sdb_ai/sd64/gplbld/test-ownaddr-units.py
#   python C:/Users/Don/SDCoreProject/SDCore4Windows/sdb_ai/sd64/gplbld/test-ownaddr-units.py --selftest
import os
import re
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
SD64 = os.path.normpath(os.path.join(HERE, ".."))
GPLSRC = os.path.join(SD64, "gplsrc")
BP = os.path.join(SD64, "sdsys", "gpl.bp")
MSYS = os.environ.get("SD_MSYS_ROOT", os.path.join("C:" + os.sep, "msys64"))
BASH = os.path.join(MSYS, "usr", "bin", "bash.exe")
CASES = [  # (address, own list, expected)
    ("10.0.2.15", ["127.0.0.1", "10.0.2.15"], 1),
    ("10.0.2.16", ["127.0.0.1", "10.0.2.15"], 0),
    ("::ffff:10.0.2.15", ["10.0.2.15"], 1),
    ("10.0.2.15", ["::ffff:10.0.2.15"], 1),
    ("fe80::1", ["fe80:0:0:0:0:0:0:1"], 1),
    ("fe80::2", ["fe80::1"], 0),
    ("2001:db8::1", ["10.0.2.15"], 0),
    ("010.0.2.15", ["10.0.2.15"], -1),
    ("::ffff:010.0.2.15", ["10.0.2.15"], -1),
    ("not-an-address", ["10.0.2.15"], -1),
    ("", ["10.0.2.15"], -1),
    ("10.0.2.15", [], 0),
    ("0.0.0.0", ["0.0.0.0"], 1),
]


def read(p):
    with open(p, encoding="latin-1", newline="") as f:
        return f.read()


def posix(p):
    p = p.replace(os.sep, "/")
    return "/" + p[0].lower() + p[2:] if len(p) > 1 and p[1] == ":" else p


def msys(cmd):
    env = dict(os.environ, MSYSTEM="MSYS", CHERE_INVOKING="1")
    return subprocess.run([BASH, "-lc", cmd], capture_output=True, text=True, env=env)


def build(src_c, d):
    with open(os.path.join(d, "sd_ownaddr.c"), "w", encoding="latin-1", newline="") as f:
        f.write(src_c)
    with open(os.path.join(d, "sd_ownaddr.h"), "w", encoding="latin-1", newline="") as f:
        f.write(read(os.path.join(GPLSRC, "sd_ownaddr.h")))
    exe = posix(os.path.join(d, "verify-ownaddr.exe"))
    p = msys("gcc -Wall -Wextra -Werror -I'%s' '%s' '%s' -o '%s'" % (posix(d), posix(os.path.join(d, "sd_ownaddr.c")),
                                                                    posix(os.path.join(HERE, "verify-ownaddr.c")), exe))
    return (exe if p.returncode == 0 else None), p.stdout + p.stderr


def run_all(exe, calls):
    # one bash for every call (each bash -l costs about a second): a line "N result=R" per call
    script = "; ".join("printf '%d '; '%s' %s" % (i, exe, " ".join("'%s'" % a for a in args)) for i, args in enumerate(calls))
    out = msys(script).stdout
    got = {}
    for m in re.finditer(r"^(\d+) result=(-?\d+)$", out, re.M):
        got[int(m.group(1))] = int(m.group(2))
    return [got.get(i) for i in range(len(calls))]


def checks(src):
    rows = []
    with tempfile.TemporaryDirectory() as d:
        exe, err = build(src["c"], d)
        if exe is None:
            rows.append(("O0 sd_ownaddr.c builds with -Wall -Wextra -Werror", False, err[-300:]))
            return rows
        calls = [[a] + o for a, o, _ in CASES] + [["--live", "127.0.0.1"], ["--live", "203.0.113.1"]]
        res = run_all(exe, calls)
        print("  inputs: %s" % "; ".join("%s -> %s" % (" ".join(c) or "''", r) for c, r in zip(calls, res)))
        bad = [(a, o, e, r) for (a, o, e), r in zip(CASES, res) if r != e]
        rows.append(("O1 %d cases: bits compared, mapped IPv4 as IPv4, a non-address and a leading zero -1, an empty list 0" % len(CASES),
                     not bad, repr(bad)))
        rows.append(("O2 LIVE: 127.0.0.1 is one of this machine's own", res[-2] == 1, repr(res[-2])))
        rows.append(("O3 LIVE CONTROL: 203.0.113.1 (TEST-NET-3) is not", res[-1] == 0, repr(res[-1])))
    rows.append(("K1 the key is 176 in gplsrc/keys.h and gpl.bp/int$keys.h",
                 re.search(r"#define K_OWN_ADDR\s+176\b", src["ck"]) is not None and re.search(r"\$define K\$OWN\.ADDR\s+176\b", src["bk"]) is not None, ""))
    opk = src["opk"]
    i = opk.find("case K_OWN_ADDR:")
    case = opk[i:opk.find("break;", i)] if i >= 0 else ""
    rows.append(("K2 op_kernel.c answers K_OWN_ADDR from sd_own_address(), -1 for an argument it cannot read",
                 "result.data.value = sd_own_address(own_arg);" in case and "result.data.value = -1;" in case, case[:120]))
    rows.append(("K3 gpl.src lists sd_ownaddr", re.search(r"^sd_ownaddr\s*$", src["src"], re.M) is not None, ""))
    api = "\n".join(l for l in src["api"].split("\n") if not l.lstrip().startswith("*"))
    own = api.find("api.own.addr = (kernel(K$OWN.ADDR, api.loop) = 1)")
    door = api.find("if downcase(scram.user) = 'sdsys' and (field(api.loop, '.', 1) = '127' or api.loop = '::1' or api.own.addr) then")
    remote = api.find("end else if downcase(scram.user) = 'sdsys' then")
    rows.append(("A1 apisrvr: an own-address peer takes the local door (with loopback), before the remote list",
                 0 <= own < door < remote and api.find("api.loop = downcase(trim(system(42)))") < own, "own %d door %d remote %d" % (own, door, remote)))
    return rows


MUTANTS = [
    ("only the first byte compared", "c", lambda t: t.replace("return memcmp(a, b, (fa == AF_INET) ? 4 : 16) == 0;", "return memcmp(a, b, 1) == 0;", 1)),
    ("mapped not folded", "c", lambda t: t.replace("if (memcmp(a6.s6_addr, mapped, 12) == 0) {", "if ((memcmp(a6.s6_addr, mapped, 12) == 0) && (a6.s6_addr[0] == 0xfe)) {", 1)),
    ("empty is mine", "c", lambda t: t.replace("  return 0;\n}\n\nint sd_own_address(", "  return 1;\n}\n\nint sd_own_address(", 1)),
    ("a leading zero is let through", "c", lambda t: t.replace("      return 0;\n    while ((*p != '\\0') && (*p != '.'))", "      return 1;\n    while ((*p != '\\0') && (*p != '.'))", 1)),
    ("apisrvr does not ask", "api", lambda t: t.replace(" or api.loop = '::1' or api.own.addr) then", " or api.loop = '::1') then", 1)),
    ("key number differs", "bk", lambda t: t.replace("$define K$OWN.ADDR       176", "$define K$OWN.ADDR       177", 1)),
]


def report(rows, quiet=False):
    bad = [n for n, ok, _ in rows if not ok]
    if not quiet:
        for n, ok, why in rows:
            print("  [%s] %s%s" % ("PASS" if ok else "FAIL", n, ("   <- " + why) if (not ok and why) else ""))
    return bad


def main():
    if not os.path.isfile(BASH) or not os.path.isfile(os.path.join(MSYS, "usr", "bin", "gcc.exe")):
        print("test-ownaddr-units: NO TREE - needs the MSYS gcc under %s" % MSYS)
        return 2
    src = {"c": read(os.path.join(GPLSRC, "sd_ownaddr.c")), "ck": read(os.path.join(GPLSRC, "keys.h")), "bk": read(os.path.join(BP, "int$keys.h")),
           "opk": read(os.path.join(GPLSRC, "op_kernel.c")), "src": read(os.path.join(SD64, "gpl.src")), "api": read(os.path.join(BP, "apisrvr"))}
    print("test-ownaddr-units: gplsrc %s, gpl.bp %s, compiler %s" % (GPLSRC, BP, os.path.join(MSYS, "usr", "bin", "gcc.exe")))
    rows = checks(src)
    bad = report(rows)
    if "--selftest" in sys.argv:
        missed = 0
        for name, key, f in MUTANTS:
            m = dict(src)
            m[key] = f(src[key])
            if m[key] == src[key]:
                print("  [MUTANT %s] DID NOT APPLY" % name)
                missed += 1
                continue
            b = report(checks(m), quiet=True)
            print("  [MUTANT %s] %s" % (name, ("killed by " + ", ".join(x.split()[0] for x in b)) if b else "MISSED"))
            missed += 0 if b else 1
        if missed:
            print("test-ownaddr-units: SELFTEST FAILED - %d mutant(s) missed or not applied" % missed)
            return 1
        print("test-ownaddr-units: selftest - %d of %d mutants killed" % (len(MUTANTS), len(MUTANTS)))
    print("test-ownaddr-units: %d passed, %d failed" % (len(rows) - len(bad), len(bad)))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
