#!/usr/bin/env python3
"""test-scramprobe-units.py - free guard over scram-probe.py (RELEASE_1.1 42).

scram-probe.py drives the server's TLS+SCRAM login directly, and its own SCRAM
arithmetic has to be right or a real red would be blamed on the server.  This
checks the parts that need no server, no install and no elevation:

  1. RFC 7677 section 3 vector: scram_compute() produces exactly the published
     ClientProof and server signature.  A bug in the AuthMessage assembly or
     the proof XOR fails here, not an hour into an elevated run.
  2. libssl loads and every OpenSSL symbol the TLS class declares resolves
     against it (the ABI is right) - the same thing verify-apiport proves live,
     caught here in a fraction of a second.
  3. the mode/precondition decisions: no password -> CANNOT RUN (exit 2),
     commands without --account -> exit 2, --no-tls with no listener -> the
     plaintext path (exit 1, "no ACK"), so the exit-code contract holds.
  4. (15 Sep 26, verify-scramlogin/apiidentity rewiring) the pieces those
     verifiers now read: the wire line's three answers, the request 4 and 16
     packets byte for byte against a scripted socket, and the refusal of two
     modes at once and of --open/--write without --account.  Every one of
     them is otherwise reached only inside an elevated run with a -Prefix.

Controls: a wrong password must make the vector FAIL (so the check is not
vacuous), a mutated AuthMessage must change the proof, the wire search must
FIND a password that is there, and a refused open must send no write.

Exit 0 all passed, 1 a check failed, 2 could not run (libssl absent - which on
a dev box is itself a failure of the RELEASE_1.1 42 prerequisite).
"""

import base64
import contextlib
import importlib.util
import io
import os
import struct
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
PROBE = os.path.join(HERE, "scram-probe.py")

checks = 0
fails = 0


def ok(msg):
    print("  [PASS] " + msg)


def bad(msg):
    global fails
    fails += 1
    print("  [FAIL] " + msg)


def check(cond, msg):
    global checks
    checks += 1
    if cond:
        ok(msg)
    else:
        bad(msg)


def load_probe():
    spec = importlib.util.spec_from_file_location("scram_probe", PROBE)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def test_rfc7677_vector(mod):
    # RFC 7677 section 3: user "user", password "pencil".
    cnonce = "rOprNGfwEbeRWgbNEkqO"
    nonce = "rOprNGfwEbeRWgbNEkqO%hvYDpWUa2RaTCAfuxFIlj)hNlF$k0"
    salt = base64.b64decode("W22ZaJ0SNY7soEsUEjb6gQ==")
    iterations = 4096
    cfirst_bare = "n=user,r=" + cnonce
    sfirst = "r=%s,s=W22ZaJ0SNY7soEsUEjb6gQ==,i=4096" % nonce
    cfinal_bare = "c=biws,r=" + nonce

    proof, expected_v = mod.scram_compute("pencil", salt, iterations,
                                          cfirst_bare, sfirst, cfinal_bare)
    proof_b64 = base64.b64encode(proof).decode("ascii")
    check(proof_b64 == "dHzbZapWIk4jUhN+Ute9ytag9zjfMHgsqmmiz7AndVQ=",
          "RFC 7677 ClientProof (got %s)" % proof_b64)
    check(expected_v == "v=6rriTRBi23WpRR/wtup+mMhUZUn/dB5nLTJRsjl95G4=",
          "RFC 7677 server signature (got %s)" % expected_v)

    # Control: a wrong password must NOT produce the vector's proof.
    wrong, _ = mod.scram_compute("Pencil", salt, iterations, cfirst_bare,
                                 sfirst, cfinal_bare)
    check(base64.b64encode(wrong).decode("ascii") != "dHzbZapWIk4jUhN+Ute9ytag9zjfMHgsqmmiz7AndVQ=",
          "control: wrong password changes the proof")
    # Control: a mutated AuthMessage (different cfinal binding) changes it too.
    mut, _ = mod.scram_compute("pencil", salt, iterations, cfirst_bare,
                               sfirst, "c=bi7s,r=" + nonce)
    check(mut != proof, "control: mutated c= changes the proof")


def test_libssl(mod):
    name = lib = None
    try:
        name, lib = mod.Tls._load()
    except Exception as e:  # noqa: BLE001 - report, do not crash
        check(False, "libssl could not be loaded: %s" % e)
        return
    check(lib is not None, "libssl loaded: %s" % name)
    symbols = ["TLS_client_method", "SSL_CTX_new", "SSL_CTX_ctrl",
               "SSL_CTX_set_verify", "SSL_new", "SSL_set_fd", "SSL_connect",
               "SSL_get_error", "SSL_read", "SSL_write", "SSL_get_version",
               "SSL_export_keying_material", "SSL_shutdown", "SSL_free",
               "SSL_CTX_free"]
    missing = [s for s in symbols if not hasattr(lib, s)]
    check(not missing, "all %d OpenSSL symbols resolve%s"
          % (len(symbols), "" if not missing else " (missing %s)" % missing))


def run_probe(args, env_extra=None):
    env = dict(os.environ)
    env.pop("SD_SCRAM_PASSWORD", None)
    if env_extra:
        env.update(env_extra)
    p = subprocess.run([sys.executable, PROBE] + args, capture_output=True,
                       text=True, env=env, timeout=60)
    return p.returncode, p.stdout + p.stderr


def test_modes():
    # No password -> CANNOT RUN, exit 2.
    rc, out = run_probe(["--user", "x"])
    check(rc == 2 and "SD_SCRAM_PASSWORD is not set" in out,
          "no password -> exit 2 (got %d)" % rc)
    # Commands without --account -> exit 2.
    rc, out = run_probe(["--user", "x", "WHO"], {"SD_SCRAM_PASSWORD": "p"})
    check(rc == 2 and "commands need --account" in out,
          "commands without account -> exit 2 (got %d)" % rc)
    # --no-tls with nothing listening -> cannot connect (exit 2) or no ACK
    # (exit 1); either way NOT a success, and never the TLS path.
    rc, out = run_probe(["--user", "x", "--no-tls", "--port", "4"],
                        {"SD_SCRAM_PASSWORD": "p"})
    check(rc in (1, 2) and "PLAINTEXT: ACK RECEIVED" not in out,
          "--no-tls to a dead port is not a pass (got %d)" % rc)
    # --open without --account -> exit 2, and it says which.
    rc, out = run_probe(["--user", "x", "--open", "ZZ"], {"SD_SCRAM_PASSWORD": "p"})
    check(rc == 2 and "--open and --write need --account" in out,
          "--open without account -> exit 2 (got %d)" % rc)
    # Two modes at once -> argparse refuses, exit 2, before connecting.  A
    # probe that silently picked one would report the wrong refusal.
    rc, out = run_probe(["--user", "x", "--replay", "--legacy"], {"SD_SCRAM_PASSWORD": "p"})
    check(rc == 2 and "not allowed with" in out,
          "two modes at once -> exit 2 (got %d)" % rc)


class FakeSock:
    """Scripted replies, every byte sent kept - the shape Tls presents."""

    def __init__(self, replies):
        self.sent = bytearray()
        self.inbox = b"".join(struct.pack("<ihi", 10 + len(body), err, status) + body
                              for err, status, body in replies)

    def sendall(self, data):
        self.sent += data

    def recv(self, n):
        chunk, self.inbox = self.inbox[:n], self.inbox[n:]
        return chunk


def quiet(fn, *args):
    """Run fn with its output captured.  AN EXCEPTION BECOMES OUTPUT, not a
    traceback: the mutant that sends a write after a refused open died here
    reading a reply the script never scripted, which was red but named no row
    and skipped every row after it."""
    buf = io.StringIO()
    result = None
    with contextlib.redirect_stdout(buf):
        try:
            result = fn(*args)
        except Exception as e:  # noqa: BLE001 - reported through the row
            print("EXCEPTION %s: %s" % (type(e).__name__, e))
    return result, buf.getvalue()


def test_wire(mod):
    check(mod.wire_verdict(bytearray(), "secret").endswith("NOT CHECKED - nothing was sent"),
          "wire: nothing sent is NOT CHECKED, never 'absent' (the null case)")
    scram_like = bytearray(b"p=tls-exporter,,n=zz,r=abc")
    check("absent from the 26 plaintext" in mod.wire_verdict(scram_like, "secret"),
          "wire: SCRAM bytes -> password absent")
    legacy = bytearray(struct.pack("<h", 6) + b"secret")
    check("FOUND IN" in mod.wire_verdict(legacy, "secret"),
          "control: wire search FINDS a password that is there")


def test_open_write(mod):
    # Open answers fileno 5; the write to it succeeds.
    s = FakeSock([(0, 0, struct.pack("<h", 5)), (0, 0, b"")])
    files = {}
    fno, out = quiet(mod.open_file, s, "ZZIDOWN", files)
    check(fno == 5 and "OPEN ZZIDOWN: OPENED fileno 5" in out,
          "open: fileno read from the 2-byte LE reply (got %r)" % fno)
    check(bytes(s.sent) == struct.pack("<ih", 13, 4) + b"ZZIDOWN",
          "open: request 4 packet is length, type, name")
    s.sent = bytearray()
    _, out = quiet(mod.write_record, s, "ZZIDOWN", "ZZAPI", "hi there", files)
    want = struct.pack("<ih", 6 + 4 + 5 + 8, 16) + struct.pack("<hh", 5, 5) + b"ZZAPI" + b"hi there"
    check(bytes(s.sent) == want and "WRITE ZZIDOWN ZZAPI: WRITTEN" in out,
          "write: request 16 packet is fileno, id length, id, data")

    # A refused open: its verdict names the error, and the write sends NOTHING.
    s = FakeSock([(2, 3007, b"not found"), ])
    files = {}
    _, out = quiet(mod.write_record, s, "ZZIDDENY", "ZZAPI", "x", files)
    check("OPEN ZZIDDENY: REFUSED server_error 2 status 3007: not found" in out,
          "open refused: server_error, status and text all printed")
    check("WRITE ZZIDDENY ZZAPI: NOT SENT - ZZIDDENY did not open" in out
          and bytes(s.sent) == struct.pack("<ih", 14, 4) + b"ZZIDDENY",
          "control: a refused open sends no write packet")

    # A refused write is REFUSED, not WRITTEN.
    s = FakeSock([(1, 0, b"denied")])
    _, out = quiet(mod.write_record, s, "ZZIDOWN", "ZZAPI", "x", {"ZZIDOWN": 5})
    check("WRITE ZZIDOWN ZZAPI: REFUSED server_error 1" in out and "WRITTEN" not in out,
          "write refused: REFUSED, and no WRITTEN on the failure path")


def main():
    if not os.path.exists(PROBE):
        print("  [FAIL] scram-probe.py not found at %s" % PROBE)
        sys.exit(2)
    mod = load_probe()
    test_rfc7677_vector(mod)
    test_libssl(mod)
    test_modes()
    test_wire(mod)
    test_open_write(mod)
    print("\ntest-scramprobe-units: %d passed, %d failed"
          % (checks - fails, fails))
    # Refuse the null case: vector 4, libssl 2, modes 5, wire 3, open/write 6.
    if checks < 20:
        print("  [FAIL] fewer checks ran than expected (null case)")
        sys.exit(2)
    sys.exit(1 if fails else 0)


if __name__ == "__main__":
    main()
