#!/usr/bin/env python3
"""relay-hold.py - open one API connection, finish the TLS handshake, read the
ACK, and HOLD the connection open for a while.  RELEASE_1.1 43.

verify-relayidentity.ps1 runs this in the background so that, while it sleeps,
there is exactly one live sdtlsrelay.exe on the machine to inspect - as the
bare account, at Low, with no privilege.  No login: the relay exists from the
handshake on, and a login would need an account this check has no use for.

  python relay-hold.py [--host 127.0.0.1] [--port 4243] [--hold 20]

Prints one line per step and "HELD <binding hex>" once the ACK is in, so the
caller can anchor on a line only a completed handshake produces.  Exit 0 when
the hold ran its course, 2 when the connection could not be made.
"""

import argparse
import importlib.util
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--port", type=int, default=4243)
    ap.add_argument("--hold", type=float, default=20.0)
    a = ap.parse_args()

    spec = importlib.util.spec_from_file_location(
        "scram_probe", os.path.join(HERE, "scram-probe.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)

    a.commands = []
    rc, sock = mod.open_session(a)
    if rc != 0 or sock is None:
        return 2
    print("HELD %s" % sock.binding.hex())
    sys.stdout.flush()
    time.sleep(a.hold)
    mod.quit_session(sock)
    sock.close()
    print("RELEASED")
    return 0


if __name__ == "__main__":
    sys.exit(main())
