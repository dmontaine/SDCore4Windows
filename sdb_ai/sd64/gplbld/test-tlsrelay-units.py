#!/usr/bin/env python3
"""test-tlsrelay-units.py - drive the real sdtlsrelay.exe over real sockets.
Free: no install, no elevation, no run token, no SD.  RELEASE_1.1 43.

WHAT IT STANDS IN FOR.  sd_tlssrv.c spawns bin\\sdtlsrelay.exe once per API
connection with two inherited sockets and speaks the frame protocol in
sd_tls.h over one of them.  This script is that sd: it accepts a loopback
connection, makes a socketpair, starts the relay with exactly those two
handles inherited (PROC_THREAD_ATTRIBUTE_HANDLE_LIST, as win32relay.c does),
sends the identity frame, reads the status frame, and then is BOTH ends of
the conversation - the TLS client through scram-probe.py's Tls class, and sd
through the socketpair.

THE ROW THAT IS THE POINT: the 32 bytes the relay hands sd are THE SAME 32
bytes the client derives from its own end of the TLS session (RFC 9266
tls-exporter).  That is what lets APISRVR's SCRAM check bind the login to
the channel; a relay that handed sd anything else would refuse every login
with a message that blames the client.  Nothing but a real handshake can
check it, which is why this drives the binary rather than a model of it.

WHAT IT DOES NOT COVER, BY DESIGN: the token.  The relay here runs as the
caller at Medium - the S4U mint, the privilege strip and the Low drop are
win32relay.c's, measured owner-elevated by gplbld/probe-relaydrop.c and
checked on an install by the verify suite.  A relay that is correct here and
still LocalSystem there is a win32relay.c defect, not a relay defect.

Exit 0 every row passed, 1 a row failed, 2 the relay is not built (make sd
builds it into bin\\) or the harness cannot run - never a vacuous pass.
"""

import importlib.util
import os
import socket
import struct
import subprocess
import sys
import tempfile
import threading
import time

HERE = os.path.dirname(os.path.abspath(__file__))
# SD_TLSRELAY names another copy - the installed one, or a mutant build for a
# control run (the binding row was proved live by a copy whose exporter label
# was changed: it went red on that row alone, 16 Sep 2026).
RELAY = os.environ.get("SD_TLSRELAY") or os.path.join(HERE, "..", "bin", "sdtlsrelay.exe")
PROBE = os.path.join(HERE, "scram-probe.py")
OPENSSL = [r"C:\msys64\ucrt64\bin\openssl.exe", r"C:\msys64\usr\bin\openssl.exe"]

# sd_tls.h - the numbers the relay answers with.
SD_RELAY_OK = 0
SD_RELAY_EXIT_IDENTITY = 2
SD_RELAY_EXIT_HANDSHAKE = 4
SD_RELAY_EXIT_USAGE = 6
BINDING_BYTES = 32
BULK = 256 * 1024

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


def cannot(msg):
    print("CANNOT RUN: " + msg)
    sys.exit(2)


def load_probe():
    spec = importlib.util.spec_from_file_location("scram_probe", PROBE)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def make_identity(tmp):
    """One PEM holding an Ed25519 key and a self-signed certificate - the
    shape create_identity() writes.  From the OpenSSL CLI, since the standard
    library cannot make a key."""
    exe = next((p for p in OPENSSL if os.path.isfile(p)), None)
    if exe is None:
        cannot("no openssl.exe in %s" % ", ".join(OPENSSL))
    key = os.path.join(tmp, "k.pem")
    crt = os.path.join(tmp, "c.pem")
    r = subprocess.run([exe, "req", "-x509", "-newkey", "ed25519", "-nodes",
                        "-keyout", key, "-out", crt, "-days", "2",
                        "-subj", "/CN=test-tlsrelay"],
                       stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if r.returncode != 0:
        cannot("openssl req failed: %s" % r.stderr.decode("latin-1").strip())
    with open(key, "rb") as f:
        pem = f.read()
    with open(crt, "rb") as f:
        pem += f.read()
    return pem


class Harness:
    """One connection: the client socket, the accepted socket, the socketpair
    and the relay process.  spawn() hands the relay its two handles."""

    def __init__(self, timeout_ms=10000):
        self.timeout_ms = timeout_ms
        lst = socket.socket()
        lst.bind(("127.0.0.1", 0))
        lst.listen(1)
        self.client = socket.create_connection(lst.getsockname())
        self.net, _ = lst.accept()
        lst.close()
        self.sd_end, self.relay_end = socket.socketpair()
        # sd's sockets are non-blocking at the Winsock level and cannot be
        # made otherwise; the relay now sets FIONBIO itself, so this is the
        # faithful shape rather than a requirement.
        self.net.setblocking(False)
        self.relay_end.setblocking(False)
        self.proc = None

    def spawn(self, args=None):
        for s in (self.net, self.relay_end):
            s.set_inheritable(True)
        handles = [self.net.fileno(), self.relay_end.fileno()]
        si = subprocess.STARTUPINFO()
        si.lpAttributeList = {"handle_list": handles}
        si.dwFlags |= subprocess.STARTF_USESHOWWINDOW
        cmd = [RELAY] + ([str(h) for h in handles] + [str(self.timeout_ms)]
                         if args is None else args)
        self.cmdline = " ".join(cmd)
        self.proc = subprocess.Popen(cmd, startupinfo=si, close_fds=True,
                                     creationflags=subprocess.CREATE_NO_WINDOW,
                                     stdin=subprocess.DEVNULL,
                                     stdout=subprocess.DEVNULL,
                                     stderr=subprocess.DEVNULL)
        # The relay is the only holder now - sd_tlssrv.c closes its copies too.
        self.net.close()
        self.relay_end.close()
        return self.proc

    def send_identity(self, pem):
        self.sd_end.sendall(struct.pack(">I", len(pem)) + pem)

    def recv_exact(self, n, deadline_s=15.0):
        self.sd_end.settimeout(deadline_s)
        buf = b""
        while len(buf) < n:
            chunk = self.sd_end.recv(n - len(buf))
            if not chunk:
                return buf
            buf += chunk
        return buf

    def read_status(self):
        """(status, binding-or-text)."""
        st = self.recv_exact(1)
        if len(st) != 1:
            return None, b""
        status = st[0]
        if status == SD_RELAY_OK:
            return status, self.recv_exact(BINDING_BYTES)
        ln = self.recv_exact(2)
        if len(ln) != 2:
            return status, b""
        n = struct.unpack(">H", ln)[0]
        return status, self.recv_exact(n)

    def exit_code(self, wait_s=15.0):
        try:
            return self.proc.wait(wait_s)
        except subprocess.TimeoutExpired:
            self.proc.kill()
            return None

    def close(self):
        for s in (self.client, self.sd_end):
            try:
                s.close()
            except OSError:
                pass
        if self.proc and self.proc.poll() is None:
            self.proc.kill()


def test_session(mod, pem):
    print("session: handshake, binding, echo, bulk, EOF from the client")
    h = Harness()
    h.spawn()
    h.send_identity(pem)

    # The client's half runs in a thread: SSL_connect needs the relay to be
    # reading the socketpair frame and answering at the same time.
    result = {}

    def client_side():
        try:
            result["tls"] = mod.Tls(h.client)
        except Exception as e:  # noqa: BLE001 - reported as a row
            result["error"] = str(e)

    t = threading.Thread(target=client_side)
    t.start()
    status, binding = h.read_status()
    t.join(20)
    check(status == SD_RELAY_OK, "status frame is SD_RELAY_OK (got %r)" % status)
    check(len(binding) == BINDING_BYTES, "binding is %d bytes (got %d)"
          % (BINDING_BYTES, len(binding)))
    if "error" in result:
        bad("client handshake: " + result["error"])
        h.close()
        return
    tls = result["tls"]
    check(tls.version == "TLSv1.3", "the session is TLS 1.3 (got %s)" % tls.version)
    check(tls.binding == binding,
          "THE BINDING THE RELAY HANDED sd IS THE CLIENT'S tls-exporter VALUE")
    # Control for the row above: 32 bytes of anything would not match.
    check(binding != b"\0" * BINDING_BYTES and binding != tls.binding[::-1],
          "control: the binding is not zero and not a reversal")

    # network -> sd, sd -> network, one line each.
    tls.sendall(b"HELLO-from-client")
    got = h.recv_exact(len(b"HELLO-from-client"))
    check(got == b"HELLO-from-client", "client -> relay -> sd: %r" % got)
    h.sd_end.sendall(b"HELLO-from-sd")
    got = tls.recv(64)
    check(got == b"HELLO-from-sd", "sd -> relay -> client: %r" % got)

    # Bulk both ways, the reader in a thread so the writer can fill buffers -
    # the relay's WSAEWOULDBLOCK paths, both directions.
    pattern = bytes((65 + (i % 26)) for i in range(8192))
    payload = (pattern * (BULK // 8192))
    seen = {}

    def drain_sd():
        seen["sd"] = h.recv_exact(BULK, 30)

    t = threading.Thread(target=drain_sd)
    t.start()
    tls.sendall(payload)
    t.join(35)
    check(seen.get("sd") == payload, "client -> sd bulk %d bytes intact" % BULK)

    def drain_client():
        buf = b""
        while len(buf) < BULK:
            chunk = tls.recv(16384)
            if not chunk:
                break
            buf += chunk
        seen["client"] = buf

    t = threading.Thread(target=drain_client)
    t.start()
    h.sd_end.sendall(payload)
    t.join(35)
    check(seen.get("client") == payload, "sd -> client bulk %d bytes intact" % BULK)

    # The client ends: sd must read EOF and the relay must exit 0.
    tls.close()
    got = h.recv_exact(1)
    check(got == b"", "client close reaches sd as EOF (read %r)" % got)
    code = h.exit_code()
    check(code == 0, "relay exit 0 after the client closed (got %r)" % code)
    h.close()


def test_sd_closes(mod, pem):
    print("session: EOF from sd")
    h = Harness()
    h.spawn()
    h.send_identity(pem)
    result = {}

    def client_side():
        try:
            result["tls"] = mod.Tls(h.client)
        except Exception as e:  # noqa: BLE001
            result["error"] = str(e)

    t = threading.Thread(target=client_side)
    t.start()
    status, binding = h.read_status()
    t.join(20)
    if status != SD_RELAY_OK or "tls" not in result:
        bad("could not reach the session (status %r, %s)" % (status, result.get("error")))
        h.close()
        return
    tls = result["tls"]
    h.sd_end.close()
    try:
        got = tls.recv(16)
        ended = got == b""
    except ConnectionError:
        ended = True           # a reset rather than close_notify still ends it
    check(ended, "sd close reaches the client as end of session")
    code = h.exit_code()
    check(code == 0, "relay exit 0 after sd closed (got %r)" % code)
    h.close()


def test_bad_identity(pem):
    print("refusal: an identity that is not one")
    h = Harness()
    h.spawn()
    h.send_identity(b"-----BEGIN NOTHING-----\nnot a key\n-----END NOTHING-----\n")
    status, text = h.read_status()
    check(status == SD_RELAY_EXIT_IDENTITY,
          "status SD_RELAY_EXIT_IDENTITY=2 (got %r)" % status)
    check(b"identity" in text, "refusal names the identity: %r" % text)
    check(b"not found" not in text and b"syntax" not in text,
          "control: the text is the relay's own, not a stray tool message")
    code = h.exit_code()
    check(code == SD_RELAY_EXIT_IDENTITY, "relay exit 2 (got %r)" % code)
    h.close()


def test_silent_client(pem):
    print("refusal: a client that connects and says nothing (1500 ms deadline)")
    h = Harness(timeout_ms=1500)
    h.spawn()
    h.send_identity(pem)
    t0 = time.time()
    status, text = h.read_status()
    took = time.time() - t0
    check(status == SD_RELAY_EXIT_HANDSHAKE,
          "status SD_RELAY_EXIT_HANDSHAKE=4 (got %r)" % status)
    check(b"no answer within 1500 ms" in text, "refusal names the deadline: %r" % text)
    check(1.0 <= took <= 6.0, "it WAITED: %.1f s (a deadline nobody fired is not one)" % took)
    code = h.exit_code()
    check(code == SD_RELAY_EXIT_HANDSHAKE, "relay exit 4 (got %r)" % code)
    h.close()


def test_plaintext_client(pem):
    print("refusal: a client that speaks plaintext, not TLS")
    h = Harness()
    h.spawn()
    h.send_identity(pem)
    h.client.sendall(b"GET / HTTP/1.0\r\n\r\n")
    status, text = h.read_status()
    check(status == SD_RELAY_EXIT_HANDSHAKE,
          "status SD_RELAY_EXIT_HANDSHAKE=4 (got %r)" % status)
    check(b"TLS handshake" in text, "refusal is a handshake failure: %r" % text)
    code = h.exit_code()
    check(code == SD_RELAY_EXIT_HANDSHAKE, "relay exit 4 (got %r)" % code)
    h.close()


def test_usage():
    print("refusal: started wrongly")
    r = subprocess.run([RELAY], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                       creationflags=subprocess.CREATE_NO_WINDOW)
    check(r.returncode == SD_RELAY_EXIT_USAGE,
          "no arguments -> exit 6 (got %d)" % r.returncode)
    check(b"not a command" in r.stderr, "and says it is not a command")
    # Two handles that are not sockets: the relay must not carry on.
    h = Harness()
    h.spawn(args=["1", "2", "10000"])
    code = h.exit_code()
    check(code == SD_RELAY_EXIT_USAGE, "non-socket handles -> exit 6 (got %r)" % code)
    h.close()


def main():
    print("test-tlsrelay-units: %s" % RELAY)
    if os.name != "nt":
        cannot("Windows only - the relay is a Windows program")
    if not os.path.isfile(RELAY):
        cannot("%s is not built; 'make sd' (or 'make sdtlsrelay') from sdb_ai/sd64 builds it"
               % os.path.normpath(RELAY))
    if not os.path.isfile(PROBE):
        cannot("no %s beside this script (the TLS client comes from it)" % PROBE)
    mod = load_probe()
    try:
        mod.Tls._load()
    except Exception as e:  # noqa: BLE001
        cannot("libssl for the client half: %s" % e)

    with tempfile.TemporaryDirectory() as tmp:
        pem = make_identity(tmp)
        print("identity: %d PEM bytes from openssl req (ed25519, self-signed)" % len(pem))
        test_session(mod, pem)
        test_sd_closes(mod, pem)
        test_bad_identity(pem)
        test_silent_client(pem)
        test_plaintext_client(pem)
        test_usage()

    print()
    print("test-tlsrelay-units: %d checks, %d failed" % (checks, fails))
    if checks == 0:
        cannot("no check ran")
    sys.exit(1 if fails else 0)


if __name__ == "__main__":
    main()
