#!/usr/bin/env python3
"""test-tlsrelay-units.py - drive the real sdtlsrelay.exe over real sockets.
Free: no install, no elevation, no run token, no SD.  RELEASE_1.1 43.

WHAT IT STANDS IN FOR.  sd_tlssrv.c spawns bin\\sdtlsrelay.exe once per API
connection with three inherited sockets and speaks the frame protocol in
sd_tls.h over two of them.  This script is that sd: it accepts a loopback
connection, makes the two socketpairs, starts the relay with exactly those
three handles inherited (PROC_THREAD_ATTRIBUTE_HANDLE_LIST, as win32relay.c
does), sends the identity frame, reads the status frame, and then is BOTH
ends of the conversation - the TLS client through scram-probe.py's Tls class,
and sd through the socketpair.

THE THIRD SOCKET is the control channel RELEASE_1.1 55 added: the front uses
it, after SCRAM, to have the relay stand up the pipe the authenticated
session will own.  It is silent through every row that never authenticates,
which is the point - such a connection must behave exactly as it did before
the channel existed.  The handover rows below drive it for real, and one of
them - test_handover_pre_request_byte, RELEASE_1.1 57 - drives APISRVR's OWN
order around it: server-final first, the client's next byte second, the
request last.  Read that function before touching either the relay's
reading_net or APISRVR's handoff block.

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
# The control channel, RELEASE_1.1 55.
CTL_PIPE = 1
CTL_READY = 2
CTL_FAILED = 3
PIPE_PREFIX = r"\\.\pipe\sd-api-"

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
    """One connection: the client socket, the accepted socket, the two
    socketpairs and the relay process.  spawn() hands the relay its three
    handles."""

    def __init__(self, timeout_ms=10000):
        self.timeout_ms = timeout_ms
        lst = socket.socket()
        lst.bind(("127.0.0.1", 0))
        lst.listen(1)
        self.client = socket.create_connection(lst.getsockname())
        self.net, _ = lst.accept()
        lst.close()
        self.sd_end, self.relay_end = socket.socketpair()
        # RELEASE_1.1 55's control channel, the second socketpair.  Nothing is
        # said on it in these rows; sd_ctl is held open because the relay would
        # otherwise read EOF on a channel the front is supposed to still hold.
        self.sd_ctl, self.relay_ctl = socket.socketpair()
        # sd's sockets are non-blocking at the Winsock level and cannot be
        # made otherwise; the relay now sets FIONBIO itself, so this is the
        # faithful shape rather than a requirement.
        self.net.setblocking(False)
        self.relay_end.setblocking(False)
        self.relay_ctl.setblocking(False)
        self.proc = None

    def spawn(self, args=None, capture=False):
        for s in (self.net, self.relay_end, self.relay_ctl):
            s.set_inheritable(True)
        handles = [self.net.fileno(), self.relay_end.fileno(),
                   self.relay_ctl.fileno()]
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
                                     stderr=(subprocess.PIPE if capture
                                             else subprocess.DEVNULL))
        # The relay is the only holder now - sd_tlssrv.c closes its copies too.
        self.net.close()
        self.relay_end.close()
        self.relay_ctl.close()
        return self.proc

    def send_identity(self, pem):
        self.sd_end.sendall(struct.pack(">I", len(pem)) + pem)

    def recv_exact(self, n, deadline_s=15.0):
        self.sd_end.settimeout(deadline_s)
        buf = b""
        while len(buf) < n:
            # A relay that exits without shutting the socketpair down - which
            # is every refusal that happens before it touches the app side -
            # reaches this end as WSAECONNRESET, not as a clean EOF.  Both
            # mean "the relay is gone and said nothing more"; raising here
            # would end the run with a traceback instead of a failed row.
            try:
                chunk = self.sd_end.recv(n - len(buf))
            except ConnectionResetError:
                return buf
            if not chunk:
                return buf
            buf += chunk
        return buf

    # ---- RELEASE_1.1 55's control channel (sd_tls.h) ------------------
    def ctl_send_pipe(self, name):
        """Ask for the handover pipe, the way sd_tls_relay_pipe() does."""
        b = name.encode("ascii")
        self.sd_ctl.sendall(struct.pack(">BH", CTL_PIPE, len(b)) + b)

    def ctl_recv(self, deadline_s=15.0):
        """(opcode, payload) or (None, b'') if the relay said nothing."""
        self.sd_ctl.settimeout(deadline_s)
        buf = b""
        while len(buf) < 3:
            try:
                chunk = self.sd_ctl.recv(3 - len(buf))
            except ConnectionResetError:
                return None, b""
            if not chunk:
                return None, b""
            buf += chunk
        op, n = struct.unpack(">BH", buf)
        body = b""
        while len(body) < n:
            chunk = self.sd_ctl.recv(n - len(body))
            if not chunk:
                break
            body += chunk
        return op, body

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
        for s in (self.client, self.sd_end, self.sd_ctl):
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


def with_deadline(fn, seconds=15.0):
    """Run a blocking read and give up rather than hang.

    A PIPE HAS NO recv TIMEOUT, AND WITHOUT THIS EVERY HANDOVER ROW BELOW
    WOULD HANG INSTEAD OF FAILING.  That is not a convenience: both of the
    obvious defects these rows exist to catch - the relay not stopping its
    net reads at the handover request, and phase B not draining what arrived
    during the switch - show up as a byte that NEVER ARRIVES, so the row must
    be able to say so.  Both mutants were run against this and each failed a
    row instead of stopping the suite.  Daemon so a thread still stuck in
    read() cannot hold the interpreter open."""
    out = {}

    def run():
        try:
            out["v"] = fn()
        except Exception as e:  # noqa: BLE001
            out["e"] = e

    t = threading.Thread(target=run, daemon=True)
    t.start()
    t.join(seconds)
    if t.is_alive():
        return None                    # nothing came: the caller reports it
    if "e" in out:
        return None
    return out["v"]


def my_sid():
    """This process's user SID.  The harness plays the FRONT, so this is the
    SID it tells the relay may open the handover pipe's client end."""
    r = subprocess.run(["whoami", "/user", "/fo", "csv", "/nh"],
                       stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                       creationflags=subprocess.CREATE_NO_WINDOW)
    if r.returncode != 0:
        cannot("whoami /user failed: %s" % r.stderr.decode("latin-1").strip())
    parts = r.stdout.decode("latin-1").strip().strip('"').split('","')
    if len(parts) != 2 or not parts[1].startswith("S-1-"):
        cannot("cannot read this process's SID from whoami: %r" % r.stdout)
    return parts[1]


def test_handover_pre_request_byte(mod, pem):
    """RELEASE_1.1 57 - APISRVR's OWN order around the handover, measured.

    THE PRODUCT'S ORDER, read from the source: APISRVR writes the SCRAM
    server-final (writepkt, apisrvr:473) and only THEN calls K$HANDOFF, which
    asks the relay for the handover pipe (sd_tls_relay_pipe -> SD_RELAY_CTL_
    PIPE).  This test drives that order: server-final first, the client's
    first post-auth byte next, the request LAST.

    WHAT HAPPENS IN THAT WINDOW is what sd_tlsrelay.c's own comment forbids:
    reading_net is still 1 (no request has arrived), so the relay reads the
    client's byte off the net and forwards it to the FRONT's app side - the
    comment says so outright: "Forwarding one of those to the front would
    lose it: the front is about to exit and will never read it."  The first
    row below asserts the byte ARRIVES AT THE FRONT; the last asserts the
    SESSION never gets it.  Both are deterministic here because the harness
    controls every send.

    WHY THIS IS A PASSING ROW AND NOT A RED ONE.  The relay is correct: while
    no request has been made it must keep serving an ordinary connection, and
    this file's test_handover already proves the fixed order (request first,
    server-final second - its "byte sent during the switch" row) delivers
    the byte to the session.  THE DEFECT IS THE ORDER THE PRODUCT CALLS THEM
    IN: it puts the client's first post-auth byte in exactly this window,
    where a Python-speed client misses it (its reply lands after the request)
    and a C-speed client hits it (the reply lands first).  The fix is in
    APISRVR/K$HANDOFF, not here.  These rows exist so the hazard stays named:
    if a relay change ever starts silently swallowing a pre-request byte
    instead of delivering it somewhere the test can see, the first row goes
    red and this comment is the argument that follows.
    """
    print("handover: the product's order - a byte sent before the request")
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
    if status != SD_RELAY_OK or "error" in result:
        bad("pre-request byte: the session did not start (%r, %s)"
            % (status, result.get("error", "")))
        h.close()
        return
    tls = result["tls"]

    # The SCRAM window, both ways, as it is today.
    tls.sendall(b"SCRAM-client-final")
    check(h.recv_exact(18) == b"SCRAM-client-final", "the SCRAM window works")

    # APISRVR STEP ONE: the server-final reaches the client while the
    # handover request has NOT been made.
    h.sd_end.sendall(b"v=server-final")
    check(with_deadline(lambda: tls.recv(64)) == b"v=server-final",
          "the server-final reaches the client before the request")

    # APISRVR STEP TWO: the client's first post-auth byte, in the window the
    # product's order opens.  The relay is still reading the net, so this one
    # goes to the front's app side rather than waiting for a session.
    tls.sendall(b"FIRST-POST-AUTH-BYTE")
    got = h.recv_exact(20, deadline_s=5.0)
    check(got == b"FIRST-POST-AUTH-BYTE",
          "THE BYTE SENT BEFORE THE REQUEST REACHED THE FRONT (got %r)" % got)
    if got != b"FIRST-POST-AUTH-BYTE":
        h.close()
        return

    # APISRVR STEP THREE: only now the request - and it is too late for the
    # byte above, which no session will ever see.
    name = PIPE_PREFIX + "unittest-pre-%d" % os.getpid()
    h.ctl_send_pipe(name + "\0" + my_sid())
    op, body = h.ctl_recv()
    check(op == CTL_READY,
          "the relay answered SD_RELAY_CTL_READY (got %r, %r)" % (op, body))

    # The front opens the client end, then closes the app side - the cutover.
    try:
        pipe = open(name, "r+b", buffering=0)
    except OSError as e:
        bad("the front could not open the handover pipe %s: %s" % (name, e))
        h.close()
        return
    h.sd_end.close()

    # THE HARM, PINNED: the session never receives the byte - it was consumed
    # by the front.  A read with a deadline; a timed-out pipe read leaves the
    # handle unusable (measured, see test_handover), so this ends the test.
    got = with_deadline(lambda: pipe.read(20), seconds=3.0)
    check(got is None or got == b"",
          "and the session did NOT receive it - the byte was consumed by "
          "the front (got %r)" % got)
    h.close()


def test_handover(mod, pem):
    """RELEASE_1.1 55's cutover, driven end to end.

    THE HARNESS IS BOTH HALVES OF THE FRONT'S JOB AND THEN THE SESSION.  It
    runs the SCRAM window on the app-side socketpair, asks for the handover
    pipe on the control channel, opens the pipe's client end the way
    win32_session_spawn does, closes the app side gracefully - which is the
    cutover signal - and from then on is the SESSION at the other end of the
    pipe, with the front gone.

    THE ROW THAT IS THE POINT is the byte the client sends DURING the switch:
    after the handover has been asked for and before the app side closes.  It
    must come out at the SESSION.  Nothing but driving the real binary can
    check it; the window it lands in exists only between those two events."""
    print("handover: the cutover from the front's socketpair to the session's pipe")
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
    if status != SD_RELAY_OK or "error" in result:
        bad("handover: the session did not start (%r, %s)"
            % (status, result.get("error", "")))
        h.close()
        return
    tls = result["tls"]

    # The SCRAM window, both ways, as it is today.
    tls.sendall(b"SCRAM-client-final")
    check(h.recv_exact(18) == b"SCRAM-client-final", "the SCRAM window works")

    # The front asks for the pipe.
    name = PIPE_PREFIX + "unittest-%d" % os.getpid()
    h.ctl_send_pipe(name + "\0" + my_sid())
    op, body = h.ctl_recv()
    check(op == CTL_READY,
          "the relay answered SD_RELAY_CTL_READY (got %r, %r)" % (op, body))

    # The front still has the server-final to flush: app side -> client must
    # keep working after the handover has been asked for.
    h.sd_end.sendall(b"v=server-final")
    check(with_deadline(lambda: tls.recv(64)) == b"v=server-final",
          "the server-final still reaches the client after the request")

    # THE BYTE SENT DURING THE SWITCH.  The relay has stopped reading the net
    # by now, so this sits in the socket until the session is on the far end.
    tls.sendall(b"FIRST-POST-AUTH-BYTE")

    # The front opens the client end and hands it to the session (here, keeps
    # it), then closes the app side GRACEFULLY - the cutover signal.
    try:
        pipe = open(name, "r+b", buffering=0)
    except OSError as e:
        bad("the front could not open the handover pipe %s: %s" % (name, e))
        h.close()
        return
    check(True, "the front opened the client end of %s" % name)
    h.sd_end.close()

    # A read that times out leaves a thread stuck INSIDE the pipe's raw file
    # object, and every later use of it then answers EINVAL - so a failure
    # here has to end this test, or one red row becomes a traceback and no
    # tally.  Measured against mutant C.
    got = with_deadline(lambda: pipe.read(20))
    if got != b"FIRST-POST-AUTH-BYTE":
        bad("THE BYTE SENT DURING THE SWITCH REACHED THE SESSION (got %r)" % got)
        print("  (stopping this test: a timed-out pipe read leaves the handle "
              "unusable)")
        h.close()
        return
    check(True, "THE BYTE SENT DURING THE SWITCH REACHED THE SESSION")

    # Both ways through the pipe, with the front gone.
    tls.sendall(b"client-to-session")
    got = with_deadline(lambda: pipe.read(17))
    if got != b"client-to-session":
        bad("client -> relay -> session (got %r)" % got)
        h.close()
        return
    check(True, "client -> relay -> session")
    pipe.write(b"session-to-client")
    check(with_deadline(lambda: tls.recv(64)) == b"session-to-client",
          "session -> relay -> client")

    # A burst each way, to exercise the drain discipline and the overlapped
    # write rather than one-message-at-a-time.
    pattern = bytes((65 + (i % 26)) for i in range(8192))
    payload = pattern * (BULK // 8192)
    seen = {}

    def drain_pipe():
        buf = b""
        while len(buf) < BULK:
            chunk = pipe.read(min(16384, BULK - len(buf)))
            if not chunk:
                break
            buf += chunk
        seen["session"] = buf

    t = threading.Thread(target=drain_pipe)
    t.start()
    tls.sendall(payload)
    t.join(35)
    check(seen.get("session") == payload,
          "client -> session bulk %d bytes intact" % BULK)

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
    pipe.write(payload)
    t.join(35)
    check(seen.get("client") == payload,
          "session -> client bulk %d bytes intact" % BULK)

    # The session ends: the client must see the session end, and the relay
    # must exit 0 rather than hang on a pipe nobody holds.
    pipe.close()
    check(with_deadline(lambda: tls.recv(64)) == b"",
          "the session closing ends the client's session")
    code = h.exit_code()
    check(code == 0, "relay exit 0 after the session closed (got %r)" % code)
    h.close()


def test_handover_refusals(mod, pem):
    """The relay must refuse a handover it cannot honour, ON THE CONTROL
    CHANNEL, so the front fails the login closed.  A relay that answered
    READY and had no pipe would leave the session waiting for ever - and the
    front would have already exited, so nothing would be left to say why."""
    print("handover: refusals come back as SD_RELAY_CTL_FAILED")

    for label, payload, want in (
            ("a name without the sd-api prefix",
             r"\\.\pipe\somebody-elses-pipe" + "\0" + "S-1-5-18",
             b"does not begin with"),
            ("a name that is only the prefix",
             PIPE_PREFIX + "\0" + "S-1-5-18", b"does not begin with"),
            ("no SID at all", PIPE_PREFIX + "nosid", b"carries no SID"),
            ("a SID that is not one",
             PIPE_PREFIX + "badsid" + "\0" + "not-a-sid", b"does not parse"),
    ):
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
        status, _ = h.read_status()
        t.join(20)
        if status != SD_RELAY_OK:
            bad("%s: the session did not start" % label)
            h.close()
            continue
        h.ctl_send_pipe(payload)
        op, body = h.ctl_recv()
        check(op == CTL_FAILED, "%s -> SD_RELAY_CTL_FAILED (got %r)" % (label, op))
        check(want in body, "  and it says why: %r" % body)
        h.close()

    # AND THE CONNECTION SURVIVES A REFUSED HANDOVER.  The front is expected
    # to fail the login and close, but the relay must not have damaged the
    # session in the meantime - otherwise a refusal here would present as a
    # dropped connection somewhere else.
    h = Harness()
    h.spawn()
    h.send_identity(pem)
    result = {}

    def client_side2():
        try:
            result["tls"] = mod.Tls(h.client)
        except Exception as e:  # noqa: BLE001
            result["error"] = str(e)

    t = threading.Thread(target=client_side2)
    t.start()
    status, _ = h.read_status()
    t.join(20)
    if status != SD_RELAY_OK:
        bad("the session did not start for the survival row")
        h.close()
        return
    tls = result["tls"]
    h.ctl_send_pipe(PIPE_PREFIX + "nosid")
    op, _ = h.ctl_recv()
    check(op == CTL_FAILED, "a refused handover answers FAILED (got %r)" % op)
    tls.sendall(b"still-here")
    check(h.recv_exact(10) == b"still-here",
          "and the connection still carries bytes afterwards")
    h.close()


def test_usage():
    print("refusal: started wrongly")
    r = subprocess.run([RELAY], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                       creationflags=subprocess.CREATE_NO_WINDOW)
    check(r.returncode == SD_RELAY_EXIT_USAGE,
          "no arguments -> exit 6 (got %d)" % r.returncode)
    check(b"not a command" in r.stderr, "and says it is not a command")
    # Three handles that are not sockets: the relay must not carry on.
    h = Harness()
    h.spawn(args=["1", "2", "3", "10000"])
    code = h.exit_code()
    check(code == SD_RELAY_EXIT_USAGE, "non-socket handles -> exit 6 (got %r)" % code)
    h.close()

    # THE ROW THAT PROVES THE RELAY LOOKED AT THE CONTROL HANDLE.  net and the
    # app side are real and only the third is not, so a relay that took argv[3]
    # and never examined it would pass every other row in this file and fail
    # here alone.  The refusal comes back on the app side and names it.
    h = Harness()
    real = [str(h.net.fileno()), str(h.relay_end.fileno())]
    h.spawn(args=real + ["1", "10000"])
    status, text = h.read_status()
    check(status == SD_RELAY_EXIT_USAGE,
          "a bad control handle -> status 6 (got %r)" % status)
    check(b"control handle" in text, "and the refusal names it: %r" % text)
    code = h.exit_code()
    check(code == SD_RELAY_EXIT_USAGE, "and the relay exits 6 (got %r)" % code)
    h.close()

    # THE ARITY ITSELF.  The pre-55 form - two handles and a timeout - must be
    # refused, not run with no control channel: a relay that quietly accepted
    # it would hand back a connection nothing can ever take over, and the
    # session would stay LocalSystem with every other row still green.
    #
    # EXIT 6 ALONE DOES NOT SAY THAT, AND THIS ROW WAS WRITTEN WRONG ONCE.  A
    # relay that took the pre-55 form and carried on reads the TIMEOUT as the
    # control handle, and the control-handle check then refuses it - exit 6,
    # for a completely different reason, and the row passed against a mutant
    # built to defeat it.  The arity refusal is the one that happens BEFORE
    # the app side is touched, so it is told apart by what it did, not by its
    # number: "not a command" on stderr, and NO status frame at all.
    h = Harness()
    real = [str(h.net.fileno()), str(h.relay_end.fileno())]
    h.spawn(args=real + ["10000"], capture=True)
    err = h.proc.communicate(timeout=15)[1]
    code = h.proc.returncode
    check(code == SD_RELAY_EXIT_USAGE,
          "the pre-55 two-handle form -> exit 6 (got %r)" % code)
    check(b"not a command" in err,
          "and it refused on ARITY, saying so on stderr (got %r)" % err)
    status, text = h.read_status()
    check(status is None,
          "and it never reached the app side (got status %r, %r)"
          % (status, text))
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
        test_handover_pre_request_byte(mod, pem)
        test_handover(mod, pem)
        test_handover_refusals(mod, pem)
        test_usage()

    print()
    print("test-tlsrelay-units: %d checks, %d failed" % (checks, fails))
    if checks == 0:
        cannot("no check ran")
    sys.exit(1 if fails else 0)


if __name__ == "__main__":
    main()
