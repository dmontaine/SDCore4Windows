#!/usr/bin/env python3
"""probe-pin.py - witness first-use certificate pinning in the INSTALLED client DLL.

RELEASE_1.1 297 (14 Nov 2026; Solo's SOLO 24, Linux S.236).  Loads the real sdclilib.dll from the Core install and connects to
the live API with it, against a SCRATCH known-servers store (SD_KNOWN_SERVERS), so the
user's own store is never touched.  NO REAL PASSWORD IS NEEDED OR USED: the pin is checked
after the TLS handshake and before any login byte, so a deliberately wrong password is
enough to get past it, and the login then fails as it should.

    py -3 probe-pin.py [--dll PATH] [--host 127.0.0.1] [--port 4247]

Every step prints what it did and what SDError said.  Verdict lines, anchored on wording
that appears only on their own path:
    PIN FIRST USE: recorded <host:port> <hex>      the store gained exactly that line
    PIN INDEPENDENT: matches                       equals sha256(DER) read by Python's ssl
    PIN SAME CERT: connected past the pin          no CHANGED / cannot-pin text
    PIN CHANGED: refused ...                       text starts "The certificate of <host:port> has
                                                   changed" (19 Nov 26: the clean-room library's
                                                   wording), names pinned and now, and came
                                                   back fast (no login: a wrong-password login
                                                   sleeps 3 s on the server)
    PIN UNUSABLE STORE: refused ...                "cannot pin the server: cannot open"
Exit 0 only if every step held; 1 otherwise; 2 if it could not run."""

import argparse
import ctypes
import hashlib
import os
import shutil
import ssl
import sys
import tempfile
import time


def say(t):
    print(t, flush=True)


def setenv(name, value):
    """19 Nov 26 (RELEASE_1.1 351/350): the clean-room sdclilib.dll is built on msvcrt.dll, which keeps its OWN copy of the
    environment, taken when it loaded; os.environ reaches only Python's UCRT copy and the process block.  Run against it with
    os.environ alone, the DLL read the user's real known_servers instead of the scratch store.  So set msvcrt's copy too."""
    os.environ[name] = value
    try:
        rc = ctypes.cdll.msvcrt._putenv_s(name.encode(), value.encode())
        say("  setenv: %s set in os.environ and msvcrt (_putenv_s %d)" % (name, rc))
    except (OSError, AttributeError) as e:
        say("  setenv: %s set in os.environ only (msvcrt: %s)" % (name, e))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dll", default=os.path.join(os.environ.get("ProgramFiles", r"C:\Program Files"), "SD", "usr", "clients", "client64", "sdclilib.dll"))
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--port", type=int, default=4247)
    a = ap.parse_args()

    say("probe-pin")
    say("  dll   : %s   exists: %s" % (a.dll, os.path.exists(a.dll)))
    say("  server: %s:%d" % (a.host, a.port))
    if not os.path.exists(a.dll):
        say("probe-pin: CANNOT RUN - no DLL")
        return 2

    work = tempfile.mkdtemp(prefix="sdpin-probe-")
    store = os.path.join(work, "known_servers")
    setenv("SD_KNOWN_SERVERS", store)
    say("  store : %s   (scratch; the user's own is untouched)" % store)

    try:
        lib = ctypes.CDLL(a.dll)
    except OSError as e:
        say("probe-pin: CANNOT RUN - cannot load the DLL: %s" % e)
        return 2
    lib.SDConnect.argtypes = [ctypes.c_char_p, ctypes.c_int, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p]
    lib.SDConnect.restype = ctypes.c_int
    lib.SDError.restype = ctypes.c_char_p

    def attempt(label):
        t0 = time.time()
        r = lib.SDConnect(a.host.encode(), a.port, b"sduser", b"not-the-password-pin-probe", b"")
        dt = time.time() - t0
        err = (lib.SDError() or b"").decode("utf-8", "replace")
        try:
            lib.SDDisconnectAll()
        except Exception:
            pass
        say("  %s: SDConnect returned %d in %.2fs; SDError: %s" % (label, r, dt, err))
        return r, dt, err

    ok = True
    key = "%s:%d" % (a.host.lower(), a.port)

    # 1. First use: connect (login fails, as it must), the store gains our line.
    if os.path.exists(store):
        say("probe-pin: CANNOT RUN - the scratch store already exists")
        return 2
    r, dt, err = attempt("first connection")
    lines = open(store).read().split("\n") if os.path.exists(store) else []
    lines = [l for l in lines if l.strip()]
    first = lines[0].split(" ") if len(lines) == 1 else None
    if first and first[0] == key and len(first[1]) == 64 and "CHANGED" not in err and "cannot pin" not in err:
        say("PIN FIRST USE: recorded %s %s" % (first[0], first[1]))
    else:
        say("PIN FIRST USE: FAILED - store lines: %r" % lines)
        return 1
    hexv = first[1]

    # 2. The recorded value is the SHA-256 of the DER certificate, read independently.
    pem = ssl.get_server_certificate((a.host, a.port))
    want = hashlib.sha256(ssl.PEM_cert_to_DER_cert(pem)).hexdigest()
    if want == hexv:
        say("PIN INDEPENDENT: matches (python ssl read the same certificate: %s)" % want)
    else:
        say("PIN INDEPENDENT: MISMATCH - DLL recorded %s, python ssl computed %s" % (hexv, want))
        ok = False

    # 3. Same certificate again: connects past the pin; the store is unchanged.
    r, dt, err = attempt("second connection")
    same = open(store).read().split("\n")
    same = [l for l in same if l.strip()]
    if "CHANGED" not in err and "cannot pin" not in err and same == lines:
        say("PIN SAME CERT: connected past the pin, store unchanged")
    else:
        say("PIN SAME CERT: FAILED")
        ok = False

    # 4. The pinned value is replaced: refused, FAST (no login), store untouched.
    bad = "0" * 64 if hexv != "0" * 64 else "1" * 64
    with open(store, "w") as f:
        f.write("%s %s\n" % (key, bad))
    r, dt, err = attempt("after the pinned value was changed")
    # 19 Nov 26 (RELEASE_1.1 351): the clean-room library's wording, measured that day against the host's Core; the GPL client's
    # "THE SERVER'S CERTIFICATE HAS CHANGED since this client first connected to ..." went with it.
    want_start = "The certificate of %s has changed since the first connection (pinned %s, now %s)." % (key, bad, hexv)
    untouched = open(store).read().strip() == "%s %s" % (key, bad)
    if err.startswith(want_start) and "No password was sent." in err and dt < 2.5 and untouched:
        say("PIN CHANGED: refused in %.2fs with the shared wording, store untouched" % dt)
    else:
        say("PIN CHANGED: FAILED - starts-with-expected: %s, fast: %s, store untouched: %s" % (err.startswith(want_start), dt < 2.5, untouched))
        ok = False
    # CONTROL for 'fast': the same server with the right pin takes the wrong-password path.
    with open(store, "w") as f:
        f.write("%s %s\n" % (key, hexv))
    r, dt2, err = attempt("control: right pin, wrong password")
    if dt2 >= 2.5:
        say("PIN CONTROL: a login that reaches the server takes %.2fs (so %.2fs above was refused before login)" % (dt2, dt))
    else:
        say("PIN CONTROL: the login was not slow (%.2fs) - the 'fast refusal' evidence is void" % dt2)
        ok = False

    # 5. A store that cannot be opened refuses.
    os.makedirs(os.path.join(work, "adir"))
    setenv("SD_KNOWN_SERVERS", os.path.join(work, "adir"))
    r, dt, err = attempt("store is a directory")
    if err.startswith("cannot pin the server: cannot open "):
        say("PIN UNUSABLE STORE: refused (%s)" % err)
    else:
        say("PIN UNUSABLE STORE: FAILED")
        ok = False

    shutil.rmtree(work, ignore_errors=True)
    say("probe-pin: " + ("ALL STEPS HELD" if ok else "A STEP FAILED"))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
