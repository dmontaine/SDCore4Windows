#!/usr/bin/env python3
"""scram-probe.py - one SD API session that logs in with SCRAM-SHA-256 over TLS.

RELEASE_1.1 42 (15 Sep 2026), the Windows port of SD Core for Linux's
gplbld/scram-probe.py (its S.19).  A throwaway client that speaks the SD API
wire exchange DIRECTLY - the RFC 5802 / 7677 SCRAM from Python's standard
library and the TLS 1.3 session through libssl by ctypes - with no SD code on
the client side, so a pass cannot be the client agreeing with itself.  It is
what lets verify-scramlogin test the server's request-47/48 refusal logic now
that every API connection is TLS-only (RELEASE_1.1 41): the plaintext .NET
TcpClient it used cannot reach the server, and .NET's SslStream cannot compute
the RFC 9266 tls-exporter binding the login must carry.

  set SD_SCRAM_PASSWORD=... & python scram-probe.py --user <name> [--account <name>] \
      [--host H] [--port P] [MODE] [--open NAME]... [--write NAME ID DATA]... [--] COMMAND...

No elevation of its own.  THE PASSWORD COMES FROM THE ENVIRONMENT, never the
command line; only its length is printed.

TLS (RELEASE_1.1 41/42).  Every API connection is TLS 1.3 and the login binds
to it: GS2 header 'p=tls-exporter,,' and c= base64(header + RFC 9266 binding).
PYTHON'S ssl MODULE CANNOT DO THIS (measured on Linux 15 Sep 2026, python
3.14.7: ssl.CHANNEL_BINDING_TYPES is ['tls-unique'] and nothing exports keying
material), so the TLS session is driven through libssl directly with ctypes.
Still no SD code: the library is a stock OpenSSL.  SD_PROBE_LIBSSL names the
library to load if the default search picks the wrong one; the default is
UCRT64's libssl-3-x64.dll (the same OpenSSL family the client DLLs link
statically), found beside its libcrypto via C:\\msys64\\ucrt64\\bin.

It prints what it did and ONE verdict line whose wording appears only on its
own path:

  SCRAM: server signature VERIFIED          the login succeeded, mutually
  SCRAM: login REFUSED at request <n>: ...   the server refused it
  SCRAM: server signature MISMATCH           the server replied v= wrongly

MODES - at most one.  15 Sep 26, verify-scramlogin's rewiring: every refusal
mode sends a message that is wrong in EXACTLY ONE WAY, so the message the
server names says which of its checks fired.

--final-only    request 48 with no 47 (must be refused as a sequence error).
--legacy        the OLD cleartext request 24 (the client library no longer
                builds it, so this is the only way left to reach request 24):
                LEGACY: login ACCEPTED / LEGACY: login REFUSED at request 24: ...
--no-tls        connects WITHOUT TLS and waits for the plaintext ACK that must
                not come (the transport-refusal control 42 keeps the raw socket
                for): PLAINTEXT: no ACK - connection closed / PLAINTEXT: ACK RECEIVED
--no-binding    logs in over TLS but with the old unbound header 'n,,' and
                c=biws - the downgrade the server must refuse at request 47.
--gs2 TEXT      client-first carries TEXT as its GS2 header instead of the one
                the transport calls for ('y,,', or a header with an m=
                extension appended).  Refused at 47 or the probe says ACCEPTED.
--tamper-nonce  a correct exchange whose client-final answers a nonce the
                server never issued.  Binding and header are correct.
--bad-cbind     a correct exchange whose c= carries this session's binding with
                ONE BIT FLIPPED - a login relayed by a man in the middle.
--replay        a real login on one connection, then a fresh client-first on a
                SECOND connection answered with the first one's client-final.
                c= is rewritten to the second connection's own binding, so the
                stale nonce is the only thing wrong with it:
                REPLAY: the captured client-final was REFUSED at request 48: ...
                REPLAY: the captured client-final was ACCEPTED
For --tamper-nonce and --bad-cbind an accepted client-final prints
"a deliberately wrong client-final was ACCEPTED" and exits 3.

AFTER A LOGIN, with --account (verify-apiidentity's measurements, which ask the
server with one request each and no command parsing in the way):
--open NAME           request 4, vb.open:  OPEN NAME: OPENED fileno <n>
                                           OPEN NAME: REFUSED server_error <e> status <s>: ...
--write NAME ID DATA  request 16, vb.write (opens NAME first if --open did not):
                      WRITE NAME ID: WRITTEN / WRITE NAME ID: REFUSED ... /
                      WRITE NAME ID: NOT SENT - NAME did not open
A refused open or write does NOT change the exit code: each is its own verdict
line, and the caller reads the line.

THE WIRE LINE.  Every session ends with one of
  wire     : password absent from the <n> plaintext byte(s) this client sent
  wire     : password FOUND IN the <n> plaintext byte(s) this client sent
  wire     : password NOT CHECKED - nothing was sent
It searches the logical stream this client handed to TLS - what it MEANT the
server to read, before encryption - which is what the .NET client's Sent
buffer measured before 41.  It is not a packet capture: ciphertext on the
wire is RELEASE_1.1 41's separate witness.  --legacy is its control, because
request 24 carries the password in clear and the same search must find it.

Exit 0 logged in (and the account, if given, entered), 1 refused (login or
account; and --no-tls's "no ACK"), 2 could not run, 3 the server's signature
did not verify, or a deliberately wrong message was accepted (and --no-tls's
"ACK RECEIVED").

Wire format, from gplsrc/sdclilib/sdclilib.c: a request is int32 length
(including its 6-byte header), int16 request type, then the body, all
little-endian; a reply is int32 length (including 10 bytes of header), int16
server_error, int32 status, then the body.  The API server sends one ACK byte
(0x06) first, inside TLS.
"""

import argparse
import base64
import ctypes
import ctypes.util
import hashlib
import hmac
import os
import socket
import struct
import sys
import time

REQ_QUIT = 1
REQ_GETERROR = 2
REQ_ACCOUNT = 3
REQ_OPEN = 4
REQ_WRITE = 16
REQ_EXECUTE = 21
REQ_LOGIN = 24
REQ_SCRAM_FIRST = 47
REQ_SCRAM_FINAL = 48

MIN_ITER = 4096          # the port's client bounds, sdclilib.c SCRAM_MIN/MAX
MAX_ITER = 10000000

GS2_BOUND = "p=tls-exporter,,"
BINDING_LABEL = b"EXPORTER-Channel-Binding"

# The UCRT64 OpenSSL, same family the client DLLs link statically.  Its
# libcrypto-3-x64.dll lives beside libssl-3-x64.dll here, so the directory is
# added to the DLL search before the load (Windows does not search a loaded
# DLL's own directory for its dependencies by default).
UCRT64_BIN = r"C:\msys64\ucrt64\bin"


def say(text):
    print(text)
    sys.stdout.flush()


class Tls:
    """TLS 1.3 client over a connected socket, through libssl with ctypes.

    No certificate check, as sdclilib: the SCRAM login bound to this session
    is what proves the server (gplsrc/sdclilib/sd_tls.c)."""

    SSL_CTRL_SET_MIN_PROTO_VERSION = 123
    SSL_CTRL_SET_MAX_PROTO_VERSION = 124
    TLS1_3_VERSION = 0x0304
    SSL_ERROR_ZERO_RETURN = 6

    def __init__(self, sock):
        # Every plaintext byte handed to SSL_write, for the wire line.
        self.sent = bytearray()
        self.lib_name, lib = self._load()
        vp, i, sz = ctypes.c_void_p, ctypes.c_int, ctypes.c_size_t
        sig = {
            "TLS_client_method": ([], vp),
            "SSL_CTX_new": ([vp], vp),
            "SSL_CTX_ctrl": ([vp, i, ctypes.c_long, vp], ctypes.c_long),
            "SSL_CTX_set_verify": ([vp, i, vp], None),
            "SSL_CTX_free": ([vp], None),
            "SSL_new": ([vp], vp),
            "SSL_set_fd": ([vp, i], i),
            "SSL_connect": ([vp], i),
            "SSL_get_error": ([vp, i], i),
            "SSL_read": ([vp, ctypes.c_char_p, i], i),
            "SSL_write": ([vp, ctypes.c_char_p, i], i),
            "SSL_get_version": ([vp], ctypes.c_char_p),
            "SSL_export_keying_material": ([vp, ctypes.c_char_p, sz, ctypes.c_char_p,
                                            sz, vp, sz, i], i),
            "SSL_shutdown": ([vp], i),
            "SSL_free": ([vp], None),
        }
        for name, (args, res) in sig.items():
            fn = getattr(lib, name)
            fn.argtypes = args
            fn.restype = res
        self.lib = lib
        self.sock = sock
        self.ctx = lib.SSL_CTX_new(lib.TLS_client_method())
        if not self.ctx:
            raise ConnectionError("TLS: cannot create a context")
        lib.SSL_CTX_ctrl(self.ctx, self.SSL_CTRL_SET_MIN_PROTO_VERSION, self.TLS1_3_VERSION, None)
        lib.SSL_CTX_ctrl(self.ctx, self.SSL_CTRL_SET_MAX_PROTO_VERSION, self.TLS1_3_VERSION, None)
        lib.SSL_CTX_set_verify(self.ctx, 0, None)
        self.ssl = lib.SSL_new(self.ctx)
        # libssl needs a blocking descriptor; a stalled server is bounded by
        # the socket's own timeouts instead of Python's.  Winsock SO_RCVTIMEO/
        # SO_SNDTIMEO take a DWORD of milliseconds, not a Linux timeval.
        sock.setblocking(True)
        if os.name == "nt":
            ms = struct.pack("i", 30000)
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_RCVTIMEO, ms)
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_SNDTIMEO, ms)
        else:
            tv = struct.pack("ll", 30, 0)
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_RCVTIMEO, tv)
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_SNDTIMEO, tv)
        if not self.ssl or lib.SSL_set_fd(self.ssl, sock.fileno()) != 1:
            raise ConnectionError("TLS: cannot attach to the socket")
        r = lib.SSL_connect(self.ssl)
        if r != 1:
            raise ConnectionError("TLS handshake failed (SSL_get_error %d)"
                                  % lib.SSL_get_error(self.ssl, r))
        self.version = lib.SSL_get_version(self.ssl).decode("ascii")
        out = ctypes.create_string_buffer(32)
        if lib.SSL_export_keying_material(self.ssl, out, 32, BINDING_LABEL,
                                          len(BINDING_LABEL), None, 0, 0) != 1:
            raise ConnectionError("TLS: cannot export the channel binding")
        self.binding = out.raw

    @staticmethod
    def _load():
        if os.name == "nt":
            # Windows does not search a loaded DLL's own directory for its
            # dependencies, so make libcrypto-3-x64.dll findable beside libssl.
            try:
                if os.path.isdir(UCRT64_BIN):
                    os.add_dll_directory(UCRT64_BIN)
            except OSError:
                pass
            names = [os.environ.get("SD_PROBE_LIBSSL", ""),
                     "libssl-3-x64.dll",
                     os.path.join(UCRT64_BIN, "libssl-3-x64.dll"),
                     ctypes.util.find_library("libssl-3-x64") or ""]
        else:
            names = [os.environ.get("SD_PROBE_LIBSSL", ""), "libssl.so.4",
                     "libssl.so.3", ctypes.util.find_library("ssl") or ""]
        for name in names:
            if not name:
                continue
            try:
                return name, ctypes.CDLL(name)
            except OSError:
                continue
        raise ConnectionError("TLS: no libssl could be loaded (tried %s)"
                              % ", ".join(n for n in names if n))

    def sendall(self, data):
        self.sent += data
        while data:
            n = self.lib.SSL_write(self.ssl, data, len(data))
            if n <= 0:
                raise ConnectionError("TLS write failed (SSL_get_error %d)"
                                      % self.lib.SSL_get_error(self.ssl, n))
            data = data[n:]

    def recv(self, n):
        buf = ctypes.create_string_buffer(n)
        r = self.lib.SSL_read(self.ssl, buf, n)
        if r > 0:
            return buf.raw[:r]
        e = self.lib.SSL_get_error(self.ssl, r)
        if e == self.SSL_ERROR_ZERO_RETURN:
            return b""
        raise ConnectionError("TLS read failed (SSL_get_error %d)" % e)

    def close(self):
        if self.ssl:
            self.lib.SSL_shutdown(self.ssl)
            self.lib.SSL_free(self.ssl)
            self.ssl = None
        if self.ctx:
            self.lib.SSL_CTX_free(self.ctx)
            self.ctx = None
        self.sock.close()


def recv_exact(sock, n):
    data = b""
    while len(data) < n:
        chunk = sock.recv(n - len(data))
        if not chunk:
            raise ConnectionError("connection closed by server after %d of %d bytes"
                                  % (len(data), n))
        data += chunk
    return data


def request_raw(sock, req, body):
    """One request, the reply body as BYTES.  vb.open answers with a 2-byte
    little-endian file number, which is not text and does not survive a
    decode."""
    if isinstance(body, str):
        body = body.encode("utf-8")
    sock.sendall(struct.pack("<ih", 6 + len(body), req) + body)
    length, server_error, status = struct.unpack("<ihi", recv_exact(sock, 10))
    if length < 10 or length > 64 * 1024 * 1024:
        raise ConnectionError("invalid reply length %d" % length)
    data = recv_exact(sock, length - 10)
    say("  request %d -> server_error %d, status %d, %d byte(s)"
        % (req, server_error, status, len(data)))
    return server_error, status, data


def request(sock, req, body):
    server_error, status, data = request_raw(sock, req, body)
    return server_error, status, data.decode("utf-8", errors="replace")


def b64(raw):
    return base64.b64encode(raw).decode("ascii")


def scram_compute(pw, salt, iterations, cfirst_bare, sfirst, cfinal_bare):
    """RFC 5802 client proof and expected server signature.  Pulled out of the
    exchange so test-scramprobe-units.py can drive it against the RFC 7677
    vector - a bug in the AuthMessage assembly or the proof XOR fails there
    rather than only against a live server."""
    salted = hashlib.pbkdf2_hmac("sha256", pw.encode("utf-8"), salt, iterations, 32)
    client_key = hmac.new(salted, b"Client Key", hashlib.sha256).digest()
    stored_key = hashlib.sha256(client_key).digest()
    server_key = hmac.new(salted, b"Server Key", hashlib.sha256).digest()
    auth = ("%s,%s,%s" % (cfirst_bare, sfirst, cfinal_bare)).encode("utf-8")
    client_sig = hmac.new(stored_key, auth, hashlib.sha256).digest()
    proof = bytes(x ^ y for x, y in zip(client_key, client_sig))
    expected_v = "v=" + b64(hmac.new(server_key, auth, hashlib.sha256).digest())
    return proof, expected_v


def wire_verdict(sent, pw):
    """The wire line.  Pure, so test-scramprobe-units.py drives both answers
    and the null case without a server."""
    if not sent:
        return "  wire     : password NOT CHECKED - nothing was sent"
    found = pw.encode("utf-8") in bytes(sent)
    return ("  wire     : password %s the %d plaintext byte(s) this client sent"
            % ("FOUND IN" if found else "absent from", len(sent)))


def binding_attr(binding):
    return b64(GS2_BOUND.encode("ascii") + binding)


def parse_server_first(sfirst, cnonce):
    """(nonce, salt, iterations), or ValueError naming what was wrong."""
    attrs = {}
    for part in sfirst.split(","):
        if len(part) > 2 and part[1] == "=":
            attrs[part[0]] = part[2:]
    nonce, salt_b64, iter_s = attrs.get("r", ""), attrs.get("s", ""), attrs.get("i", "")
    if not nonce.startswith(cnonce) or len(nonce) <= len(cnonce):
        raise ValueError("server nonce does not extend ours - refusing to continue")
    try:
        iterations = int(iter_s)
        salt = base64.b64decode(salt_b64, validate=True)
    except ValueError:
        raise ValueError("malformed server-first")
    if not MIN_ITER <= iterations <= MAX_ITER:
        raise ValueError("iteration count %d outside %d..%d" % (iterations, MIN_ITER, MAX_ITER))
    return nonce, salt, iterations


def open_file(sock, name, files):
    """Request 4.  Returns the file number, or None; prints the verdict line."""
    err, status, data = request_raw(sock, REQ_OPEN, name.encode("ascii"))
    if err == 0 and len(data) >= 2:
        fno = struct.unpack("<h", data[:2])[0]
        files[name] = fno
        say("OPEN %s: OPENED fileno %d" % (name, fno))
        return fno
    if err == 0:
        say("OPEN %s: REFUSED server_error 0 status %d: reply carried %d byte(s), no file number"
            % (name, status, len(data)))
        return None
    say("OPEN %s: REFUSED server_error %d status %d: %s"
        % (name, err, status, data.decode("utf-8", errors="replace").strip()))
    return None


def write_record(sock, name, rid, text, files):
    """Request 16.  Payload fileno (2, LE) | id length (2, LE) | id | data,
    which is what APISRVR's vb.write reads back off the wire."""
    fno = files.get(name)
    if fno is None:
        fno = open_file(sock, name, files)
    if fno is None:
        say("WRITE %s %s: NOT SENT - %s did not open" % (name, rid, name))
        return
    idb = rid.encode("ascii")
    payload = struct.pack("<hh", fno, len(idb)) + idb + text.encode("utf-8")
    err, status, data = request_raw(sock, REQ_WRITE, payload)
    if err == 0:
        say("WRITE %s %s: WRITTEN" % (name, rid))
    else:
        say("WRITE %s %s: REFUSED server_error %d status %d: %s"
            % (name, rid, err, status, data.decode("utf-8", errors="replace").strip()))


def open_session(a):
    """Connect, TLS, ACK.  (0, sock) or (2, None) having said why."""
    try:
        raw = socket.create_connection((a.host, a.port), timeout=30)
    except OSError as e:
        say("scram-probe: CANNOT RUN - cannot connect: %s" % e)
        return 2, None
    try:
        sock = Tls(raw)
    except (OSError, ConnectionError) as e:
        raw.close()
        say("scram-probe: CANNOT RUN - %s" % e)
        return 2, None
    say("  tls      : %s via %s, binding %s..." % (sock.version, sock.lib_name,
                                                  sock.binding[:8].hex()))
    try:
        ack = recv_exact(sock, 1)
    except (OSError, ConnectionError) as e:
        sock.close()
        say("scram-probe: CANNOT RUN - no ACK inside TLS: %s" % e)
        return 2, None
    if ack != b"\x06":
        sock.close()
        say("scram-probe: CANNOT RUN - expected ACK 0x06, got %r" % ack)
        return 2, None
    return 0, sock


def client_first(sock, gs2, user):
    cnonce = b64(os.urandom(18))
    cfirst_bare = "n=%s,r=%s" % (user, cnonce)
    say("  client-first: %s%s" % (gs2, cfirst_bare))
    err, _, sfirst = request(sock, REQ_SCRAM_FIRST, gs2 + cfirst_bare)
    return err, cnonce, cfirst_bare, sfirst


def login(sock, a, pw):
    """The exchange in whichever mode was asked for.  (rc, client-final sent);
    rc 0 means the signature verified."""
    if a.no_binding:
        gs2, cbind = "n,,", "biws"
    else:
        gs2 = a.gs2 if a.gs2 is not None else GS2_BOUND
        cbind = binding_attr(sock.binding)
    if a.bad_cbind:
        flipped = bytes([sock.binding[0] ^ 1]) + sock.binding[1:]
        cbind = binding_attr(flipped)
    say("  c=       : %s%s" % (cbind, "  (ONE BIT FLIPPED - not this session's binding)"
                                if a.bad_cbind else ""))

    if a.legacy:
        def field(text):
            raw_field = text.encode("utf-8")
            return (struct.pack("<h", len(raw_field)) + raw_field
                    + (b"\0" if len(raw_field) & 1 else b""))
        err, _, text = request(sock, REQ_LOGIN, field(a.user) + field(pw))
        if err != 0:
            say("LEGACY: login REFUSED at request 24: %s" % text)
            return 1, ""
        say("LEGACY: login ACCEPTED")
        return 0, ""

    if a.final_only:
        cnonce = b64(os.urandom(18))
        err, _, text = request(sock, REQ_SCRAM_FINAL,
                               "c=%s,r=%sAAAA,p=%s" % (cbind, cnonce, b64(b"\0" * 32)))
        if err != 0:
            say("SCRAM: login REFUSED at request 48: %s" % text)
            return 1, ""
        say("scram-probe: request 48 without 47 was ACCEPTED - server_error 0")
        return 3, ""

    err, cnonce, cfirst_bare, sfirst = client_first(sock, gs2, a.user)
    if err != 0:
        say("SCRAM: login REFUSED at request 47: %s" % sfirst)
        return 1, ""
    say("  server-first: %s" % sfirst)
    if a.gs2 is not None or a.no_binding:
        say("scram-probe: client-first with header %r was ACCEPTED" % gs2)
        return 3, ""

    try:
        nonce, salt, iterations = parse_server_first(sfirst, cnonce)
    except ValueError as e:
        say("scram-probe: %s" % e)
        return 3, ""

    sent_nonce = nonce
    if a.tamper_nonce:
        sent_nonce = b64(os.urandom(18))
        say("  r=       : %s  (TAMPERED - not the nonce the server issued)" % sent_nonce)
    cfinal_bare = "c=%s,r=%s" % (cbind, sent_nonce)
    t0 = time.time()
    proof, expected_v = scram_compute(pw, salt, iterations, cfirst_bare,
                                      sfirst, cfinal_bare)
    say("  PBKDF2 %d iterations: %.2f s" % (iterations, time.time() - t0))

    cfinal = "%s,p=%s" % (cfinal_bare, b64(proof))
    err, _, sfinal = request(sock, REQ_SCRAM_FINAL, cfinal)
    if err != 0:
        say("SCRAM: login REFUSED at request 48: %s" % sfinal)
        return 1, cfinal
    if a.tamper_nonce or a.bad_cbind:
        say("scram-probe: a deliberately wrong client-final was ACCEPTED")
        return 3, cfinal
    if not hmac.compare_digest(sfinal, expected_v):
        say("SCRAM: server signature MISMATCH (got %r)" % sfinal)
        return 3, cfinal
    say("SCRAM: server signature VERIFIED")
    return 0, cfinal


def after_login(sock, a):
    if a.account:
        err, _, text = request(sock, REQ_ACCOUNT, a.account)
        if err != 0:
            _, _, detail = request(sock, REQ_GETERROR, "")
            say("account %s: REFUSED: %s" % (a.account, detail or text))
            return 1
        say("account %s: entered" % a.account)

    files = {}
    for name in a.open:
        open_file(sock, name, files)
    for name, rid, text in a.write:
        write_record(sock, name, rid, text, files)

    if a.pause > 0:
        say("pausing %gs before the commands" % a.pause)
        time.sleep(a.pause)

    for cmd in a.commands:
        say("> %s" % cmd)
        err, _, out = request(sock, REQ_EXECUTE, cmd)
        for line in out.replace("\r\n", "\n").replace("\r", "\n").split("\n"):
            if line != "":
                say("| %s" % line)
        say("  (server_error %d)" % err)

    if a.hold > 0:
        say("holding the connection %gs" % a.hold)
        time.sleep(a.hold)
    return 0


def quit_session(sock):
    try:
        sock.sendall(struct.pack("<ih", 6, REQ_QUIT))
    except (OSError, ConnectionError):
        pass
    say("disconnected")


def run_replay(a, pw):
    say("  replay 1/2: a real login, to capture its client-final")
    rc, s1 = open_session(a)
    if rc:
        return rc
    try:
        rc, captured = login(s1, a, pw)
        if rc == 0:
            quit_session(s1)
    except (OSError, ConnectionError) as e:
        say("scram-probe: connection failed part way: %s" % e)
        rc, captured = 1, ""
    finally:
        say(wire_verdict(s1.sent, pw))
        s1.close()
    if rc != 0 or captured.count(",") != 2:
        say("scram-probe: CANNOT RUN - the login whose client-final was to be replayed did not succeed")
        return 2

    say("  replay 2/2: a fresh client-first on a NEW connection, answered with the captured client-final")
    rc, s2 = open_session(a)
    if rc:
        return rc
    try:
        err, _, _, sfirst = client_first(s2, GS2_BOUND, a.user)
        if err != 0:
            say("scram-probe: CANNOT RUN - the replay connection's client-first was refused: %s" % sfirst)
            return 2
        say("  server-first: %s" % sfirst)
        # c= IS THIS CONNECTION'S, so the binding check passes and the nonce
        # is the one stale thing - otherwise the binding would refuse it first
        # and the nonce check would never be reached.
        _, r_attr, p_attr = captured.split(",", 2)
        replayed = "c=%s,%s,%s" % (binding_attr(s2.binding), r_attr, p_attr)
        say("  replayed : %s" % replayed)
        err, _, text = request(s2, REQ_SCRAM_FINAL, replayed)
        if err != 0:
            say("REPLAY: the captured client-final was REFUSED at request 48: %s" % text)
            return 1
        say("REPLAY: the captured client-final was ACCEPTED")
        return 3
    except (OSError, ConnectionError) as e:
        say("scram-probe: connection failed part way: %s" % e)
        return 1
    finally:
        say(wire_verdict(s2.sent, pw))
        s2.close()


def main(argv):
    ap = argparse.ArgumentParser(description="One SCRAM-SHA-256 SD API session.")
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--port", type=int, default=4243)
    ap.add_argument("--user", required=True)
    ap.add_argument("--account", default="")
    ap.add_argument("--hold", type=float, default=0.0)
    ap.add_argument("--pause", type=float, default=0.0,
                    help="wait this long AFTER login and account, BEFORE the commands")
    mode = ap.add_mutually_exclusive_group()
    mode.add_argument("--final-only", action="store_true",
                      help="send request 48 without 47 (must be refused)")
    mode.add_argument("--legacy", action="store_true",
                      help="send the old cleartext request 24 instead of SCRAM")
    mode.add_argument("--no-tls", action="store_true",
                      help="connect without TLS and wait for a plaintext ACK (must not come)")
    mode.add_argument("--no-binding", action="store_true",
                      help="log in over TLS with the unbound 'n,,' header (must be refused)")
    mode.add_argument("--gs2", default=None,
                      help="send this GS2 header in client-first (must be refused)")
    mode.add_argument("--tamper-nonce", action="store_true",
                      help="answer a nonce the server never issued (must be refused)")
    mode.add_argument("--bad-cbind", action="store_true",
                      help="c= with one bit of the binding flipped (must be refused)")
    mode.add_argument("--replay", action="store_true",
                      help="replay a captured client-final on a new connection (must be refused)")
    ap.add_argument("--open", action="append", default=[], metavar="NAME",
                    help="after login and account, open this VOC name (request 4)")
    ap.add_argument("--write", action="append", default=[], nargs=3,
                    metavar=("NAME", "ID", "DATA"),
                    help="after login and account, write a record (request 16)")
    ap.add_argument("commands", nargs="*")
    a = ap.parse_args(argv)

    pw = os.environ.get("SD_SCRAM_PASSWORD")
    say("scram-probe")
    say("  transport: tcp %s port %d" % (a.host, a.port))
    say("  user     : %s" % a.user)
    say("  account  : %s" % (a.account or "(none - authentication only)"))
    say("  password : %s" % ("from SD_SCRAM_PASSWORD, %d characters" % len(pw)
                             if pw is not None else "SD_SCRAM_PASSWORD is not set"))
    say("  mode     : %s" % ("connect WITHOUT TLS, expect no ACK" if a.no_tls
                             else "request 24, the old cleartext login" if a.legacy
                             else "request 48 ONLY, no 47" if a.final_only
                             else "47 then 48, UNBOUND 'n,,' over TLS" if a.no_binding
                             else "47 with GS2 header %r" % a.gs2 if a.gs2 is not None
                             else "47 then 48 answering a TAMPERED nonce" if a.tamper_nonce
                             else "47 then 48 with a FLIPPED binding in c=" if a.bad_cbind
                             else "login, then REPLAY its client-final on a new connection" if a.replay
                             else "47 then 48, bound to TLS"))
    say("  commands : %d   open: %d   write: %d   hold: %gs   pause: %gs"
        % (len(a.commands), len(a.open), len(a.write), a.hold, a.pause))
    for name in a.open:
        say("  open     : %s" % name)
    for name, rid, _ in a.write:
        say("  write    : %s %s" % (name, rid))
    if pw is None or pw == "":
        say("scram-probe: CANNOT RUN - SD_SCRAM_PASSWORD is not set or empty.")
        return 2
    if a.commands and not a.account:
        say("scram-probe: CANNOT RUN - commands need --account.")
        return 2
    if (a.open or a.write) and not a.account:
        say("scram-probe: CANNOT RUN - --open and --write need --account.")
        return 2

    if a.no_tls:
        try:
            raw = socket.create_connection((a.host, a.port), timeout=30)
        except OSError as e:
            say("scram-probe: CANNOT RUN - cannot connect: %s" % e)
            return 2
        try:
            ack = raw.recv(1)
        except OSError as e:
            ack = b""
            say("  recv: %s" % e)
        finally:
            raw.close()
        if ack == b"\x06":
            say("PLAINTEXT: ACK RECEIVED - the server spoke without TLS")
            return 3
        say("PLAINTEXT: no ACK - connection closed (got %r)" % ack)
        return 1

    if a.replay:
        return run_replay(a, pw)

    rc, sock = open_session(a)
    if rc:
        return rc
    try:
        rc, _ = login(sock, a, pw)
        if rc == 0 and not a.legacy:
            rc = after_login(sock, a)
        elif rc == 0 and a.account:
            err, _, text = request(sock, REQ_ACCOUNT, a.account)
            if err != 0:
                say("account %s: REFUSED" % a.account)
                rc = 1
            else:
                say("account %s: entered" % a.account)
        if rc == 0:
            quit_session(sock)
        return rc
    except (OSError, ConnectionError) as e:
        say("scram-probe: connection failed part way: %s" % e)
        return 1
    finally:
        say(wire_verdict(sock.sent, pw))
        sock.close()


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
