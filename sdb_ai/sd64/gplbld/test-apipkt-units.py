#!/usr/bin/env python3
"""test-apipkt-units.py - Linux S.71 as carried (RELEASE_1.1 163): a lost API connection ends, a packet length is bounded, as invariants.

  python gplbld/test-apipkt-units.py
  python gplbld/test-apipkt-units.py --selftest

No install, no elevation, no sd.  Exit 0 all checks passed, 1 a check failed, 2 it could not run.

20 Oct 26 Windows port - CARRIED FROM SD CORE FOR LINUX 1c2d0af, NOT COPIED.  Linux tests this with gplbld/sandbox-apispin.py, which drives a
real sd -n -q over a socket and reads /proc; Windows has neither, so this reads the repaired functions as TEXT (rows K, R, P) and runs the
length rule itself as C (rows A, only when MSYS2's gcc is on this machine; otherwise they are reported NOT RUN, never passed).  The live
witness (an API client that closes mid-packet, then CPU and memory of the sd process) is not here and is owed on an install - row 163.

  K1  keyin() leaves its wait loop when the connection is lost, before it polls again
  K2  keyready() says FALSE for a lost connection whose ring is empty, before it polls
  K3  read_socket() stops with ER_EOF when keyin() gives up, and no longer returns 1 for everything
  R1  op_readpkt() tests the declared length before it allocates anything
  R2  process_client_input() tests it too, and ends the session (K_TERMINATE)
  R3  both free the half-read string when read_socket() fails
  R4  api_before_login() is the LocalSystem front: is_sdApiSrvr && !api_preauth
  R5  op_tio.c includes apipkt.h and refuses to compile if its largest string differs from sddefs.h's
  A1-A9  api_packet_length_ok(): under 6 refused, 65,536 before login, MAX_STRING_SIZE + 10 after (compiled and run)

--selftest breaks each fact in turn and requires the check to say so.
"""
import os
import re
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
GPLSRC = os.path.normpath(os.path.join(HERE, "..", "gplsrc"))
LINUXIO = os.path.join(GPLSRC, "linuxio.c")
OPTIO = os.path.join(GPLSRC, "op_tio.c")
APIPKT = os.path.join(GPLSRC, "apipkt.h")
SDDEFS = os.path.join(GPLSRC, "sddefs.h")
MSYS_BASH = r"C:\msys64\usr\bin\bash.exe"

BEFORE_LOGIN = "return is_sdApiSrvr && !api_preauth;"


def slurp(p):
    with open(p, encoding="latin-1") as f:
        return f.read()


def between(text, start, end):
    i = text.find(start)
    if i < 0:
        return ""
    j = text.find(end, i + len(start))
    return text[i:j] if j >= 0 else text[i:]


def functions(linuxio, optio):
    return {
        "keyin": between(linuxio, "int16_t keyin(timeout)", "void io_handler("),
        "keyready": between(linuxio, "bool keyready() {", "int32_t type_ahead_count()"),
        "read_socket": between(linuxio, "bool read_socket(str, bytes)", "char socket_byte()"),
        "op_readpkt": between(optio, "void op_readpkt() {", "op_writepkt()"),
        "pci": between(optio, "Private void process_client_input() {", "\n}\n"),
        "before_login": between(optio, "Private bool api_before_login() {", "\n}\n"),
    }


def checks(linuxio, optio):
    res = []

    def ck(name, ok, detail=""):
        res.append((name, bool(ok), detail))

    f = functions(linuxio, optio)

    kin = f["keyin"]
    loop = kin.find("while (ring_in == ring_out)")
    lost = kin.find("if (connection_lost) {", loop) if loop >= 0 else -1
    poll = kin.find("sdpoll(0,", loop) if loop >= 0 else -1  # the call, not the word in a comment
    body = kin[lost:poll] if 0 <= lost < poll else ""
    ck("K1 keyin() ends a lost connection before it polls",
       0 <= lost < poll and "k_exit_cause = K_TERMINATE;" in body and "return 0;" in body, "loop %d, lost %d, poll %d" % (loop, lost, poll))

    kr = f["keyready"]
    kl = kr.find("if (connection_lost && (ring_in == ring_out))")
    kp = kr.find("sdpoll(0,")  # the call, not the word in a comment
    ck("K2 keyready() is FALSE for a lost connection, before it polls",
       0 <= kl < kp and "return FALSE;" in kr[kl:kp] and "K_TERMINATE" in kr[kl:kp], "lost %d, poll %d" % (kl, kp))

    rs = f["read_socket"]
    ck("K3 read_socket() stops with ER_EOF when keyin() gives up",
       "c = keyin(0);" in rs and "process.status = ER_EOF;" in rs and "return FALSE;" in rs and "return 1;" not in rs
       and "K_INTERRUPT" in rs)

    rp = f["op_readpkt"]
    t1 = rp.find("api_packet_length_ok(packet_bytes, api_before_login())")
    a1 = rp.find("s_alloc(")
    ck("R1 op_readpkt() tests the declared length before it allocates", 0 <= t1 < a1, "test %d, alloc %d" % (t1, a1))

    pc = f["pci"]
    t2 = pc.find("api_packet_length_ok(packet_bytes, api_before_login())")
    a2 = pc.find("s_alloc(")
    ck("R2 process_client_input() tests it and ends the session",
       0 <= t2 < a2 and "k_exit_cause = K_TERMINATE;" in pc[t2:a2], "test %d, alloc %d" % (t2, a2))

    fr = re.compile(r"if \(!read_socket\(str->data, n\)\) \{[^}]*s_free\(str_hdr\)")
    ck("R3 both free the half-read string when read_socket() fails", fr.search(rp) is not None and fr.search(pc) is not None,
       "op_readpkt %s, process_client_input %s" % (fr.search(rp) is not None, fr.search(pc) is not None))

    ck("R4 api_before_login() is the LocalSystem front", BEFORE_LOGIN in f["before_login"])

    ck("R5 op_tio.c includes apipkt.h and checks the largest string",
       '#include "apipkt.h"' in optio and "#if API_PKT_MAX_STRING != MAX_STRING_SIZE" in optio and "#error" in optio)
    return res


def limit_row(pkt, sdd):
    a = re.search(r"#define API_PKT_MAX_STRING (\d+)", pkt)
    s = re.search(r"#define MAX_STRING_SIZE\s+(\d+)", sdd)
    return ("R6 apipkt.h's largest string is sddefs.h's MAX_STRING_SIZE",
            bool(a and s and a.group(1) == s.group(1)), "apipkt %s, sddefs %s" % (a and a.group(1), s and s.group(1)))


# ---- the length rule, compiled and run ------------------------------------------------------------------------------------------
CASES = [  # declared, before_login, expected
    (-2147483648, 0, 0), (-1, 0, 0), (0, 0, 0), (5, 0, 0), (6, 0, 1), (6, 1, 1),
    (65536, 1, 1), (65537, 1, 0), (65537, 0, 1),
    (1073741832, 0, 1), (1073741833, 0, 0), (2147483647, 0, 0), (1073741832, 1, 0),
]
HARNESS = """#include <stdio.h>
#include "apipkt.h"
int main(void) {
  static const long long d[] = {%s};
  static const int b[] = {%s};
  for (unsigned i = 0; i < sizeof d / sizeof d[0]; i++)
    printf("%%lld %%d %%d\\n", d[i], b[i], api_packet_length_ok((int32_t)d[i], b[i]));
  return 0;
}
"""


def msys_path(p):
    p = os.path.abspath(p).replace("\\", "/")
    return "/" + p[0].lower() + p[2:] if len(p) > 2 and p[1] == ":" else p


def run_length_rule(apipkt_text, sddefs_text):
    """Returns (rows, note).  rows: list of (name, ok, detail); note says why none were run."""
    if not os.path.isfile(MSYS_BASH):
        return [], "NOT RUN: no %s (MSYS2's gcc compiles the length rule)" % MSYS_BASH
    with tempfile.TemporaryDirectory() as tmp:
        with open(os.path.join(tmp, "apipkt.h"), "w", encoding="latin-1", newline="") as f:
            f.write(apipkt_text)
        src = HARNESS % (", ".join(str(c[0]) + "LL" for c in CASES), ", ".join(str(c[1]) for c in CASES))
        with open(os.path.join(tmp, "h.c"), "w", encoding="latin-1", newline="") as f:
            f.write(src)
        t = msys_path(tmp)
        cmd = "cd '%s' && gcc -std=gnu17 -Wall -I'%s' -o h.exe h.c && ./h.exe" % (t, t)
        env = dict(os.environ, MSYSTEM="MSYS")
        p = subprocess.run([MSYS_BASH, "-lc", cmd], capture_output=True, text=True, env=env, timeout=120)
        if p.returncode != 0:
            return [("A0 the length rule compiles and runs", False, (p.stderr or p.stdout)[-300:])], ""
        got = {}
        for line in p.stdout.splitlines():
            parts = line.split()
            if len(parts) == 3:
                got[(int(parts[0]), int(parts[1]))] = int(parts[2])
        rows = []
        for n, (d, b, want) in enumerate(CASES, 1):
            have = got.get((d, b))
            rows.append(("A%d length %d %s login -> %s" % (n, d, "before" if b else "after", "ok" if want else "refused"),
                         have == want, "got %r" % have))
        return rows, ""


def selftest(have_c):
    lio, opt, pkt, sdd = slurp(LINUXIO), slurp(OPTIO), slurp(APIPKT), slurp(SDDEFS)
    base = checks(lio, opt)
    bad = [n for n, ok, _ in base if not ok]
    if bad:
        print("selftest: the real files already fail: %s" % bad)
        return False
    mutants = [
        ("keyin: no lost-connection exit", lio.replace("      if (connection_lost) {\n        k_exit_cause = K_TERMINATE;\n        input_handler_enabled = TRUE;\n        return 0;\n      }\n",
                                                         ""), opt, "K1"),
        ("keyready: no lost-connection test", lio.replace("if (connection_lost && (ring_in == ring_out))", "if (0)"), opt, "K2"),
        ("read_socket: result ignored", lio.replace("c = keyin(0);", "c = (keyin(0), 1);").replace("process.status = ER_EOF;", "process.status = 0;"), opt, "K3"),
        ("op_readpkt: length believed", lio, opt.replace("if (!api_packet_length_ok(packet_bytes, api_before_login())) {\n    api_packet_refused(packet_bytes);\n    goto exit_op_readpkt;",
                                                          "if (0) {\n    api_packet_refused(packet_bytes);\n    goto exit_op_readpkt;"), "R1"),
        ("process_client_input: no K_TERMINATE", lio, opt.replace("    api_packet_refused(packet_bytes);\n    k_exit_cause = K_TERMINATE;\n    return;",
                                                                   "    api_packet_refused(packet_bytes);\n    return;"), "R2"),
        ("op_readpkt: partial string kept", lio, opt.replace("      s_free(str_hdr);\n      str_hdr = NULL;\n      goto exit_op_readpkt;", "      goto exit_op_readpkt;"), "R3"),
        ("before login: always after", lio, opt.replace(BEFORE_LOGIN, "return 0;"), "R4"),
        ("no string-size check", lio, opt.replace("#if API_PKT_MAX_STRING != MAX_STRING_SIZE", "#if 0"), "R5"),
    ]
    ok = True
    for name, l, o, want in mutants:
        if (l, o) == (lio, opt):
            print("  [FAIL] selftest: %s (the mutation changed nothing)" % name)
            ok = False
            continue
        failed = [n.split()[0] for n, passed, _ in checks(l, o) if not passed]
        caught = want in failed
        print("  [%s] selftest: %s%s" % ("PASS" if caught else "FAIL", name, "" if caught else " (NOT CAUGHT; failed: %s)" % failed))
        ok = ok and caught
    if not limit_row(pkt, sdd)[1]:
        print("selftest: the real apipkt.h/sddefs.h already disagree")
        return False
    lm = limit_row(pkt.replace("API_PKT_MAX_STRING 1073741822", "API_PKT_MAX_STRING 1073741821"), sdd)
    print("  [%s] selftest: apipkt.h string limit differs from sddefs.h" % ("PASS" if not lm[1] else "FAIL"))
    ok = ok and not lm[1]
    if have_c:
        cmut = [
            ("apipkt.h: header size 5", pkt.replace("#define API_PKT_HDR_BYTES 6", "#define API_PKT_HDR_BYTES 5")),
            ("apipkt.h: pre-login limit 65537", pkt.replace("#define API_PKT_MAX_PRELOGIN 65536", "#define API_PKT_MAX_PRELOGIN 65537")),
            ("apipkt.h: no pre-login rule", pkt.replace("    return declared <= API_PKT_MAX_PRELOGIN;", "    return 1;")),
            ("apipkt.h: string limit without the header", pkt.replace("(int32_t)API_PKT_MAX_STRING + 10", "(int32_t)API_PKT_MAX_STRING")),
        ]
        for name, text in cmut:
            if text == pkt:
                print("  [FAIL] selftest: %s (the mutation changed nothing)" % name)
                ok = False
                continue
            rows, _ = run_length_rule(text, sdd)
            failed = [n for n, passed, _ in rows if not passed]
            caught = bool(failed)
            print("  [%s] selftest: %s%s" % ("PASS" if caught else "FAIL", name, "" if caught else " (NOT CAUGHT)"))
            ok = ok and caught
    else:
        print("  [NOTE] selftest: the C mutants were NOT RUN (no MSYS2 gcc)")
    return ok


def main():
    for p in (LINUXIO, OPTIO, APIPKT, SDDEFS):
        if not os.path.isfile(p):
            print("test-apipkt-units: CANNOT RUN - %s missing" % os.path.normpath(p))
            return 2
    print("test-apipkt-units: reading %s, %s and %s" % tuple(os.path.normpath(p) for p in (LINUXIO, OPTIO, APIPKT)))
    have_c = os.path.isfile(MSYS_BASH)
    if "--selftest" in sys.argv:
        return 0 if selftest(have_c) else 1
    res = checks(slurp(LINUXIO), slurp(OPTIO))
    res.append(limit_row(slurp(APIPKT), slurp(SDDEFS)))
    crows, note = run_length_rule(slurp(APIPKT), slurp(SDDEFS))
    res += crows
    failed = 0
    for name, ok, detail in res:
        print("  [%s] %s%s" % ("PASS" if ok else "FAIL", name, "" if ok else "   <- " + detail))
        failed += 0 if ok else 1
    if note:
        print("  [NOTE] A1-A%d %s" % (len(CASES), note))
    print("\ntest-apipkt-units: %d passed, %d failed%s" % (len(res) - failed, failed, "" if not note else ", the C rows not run"))
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
