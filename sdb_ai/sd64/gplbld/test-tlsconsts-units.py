#!/usr/bin/env python3
"""test-tlsconsts-units.py - the API's TLS wire contract is one fact in five
files, kept in step by hand.  RELEASE_1.1 41 (Linux S.19).

Five copies have to agree or a Windows client and a Linux server - or a
Windows client and a Windows server built at different times - fail in ways
nobody can see from the traffic: a different exporter label derives a different
binding, a different GS2 header is refused as a downgrade, a different SDEXT
key number reaches the wrong dispatch arm.  Nothing in the build cross-checks
them; the compiler is happy with any constant.  This does, in a fraction of a
second, with no SD, no install and no elevation.

WHAT IT CHECKS, against the wire contract row 41 fixes (the same numbers as
Linux S.19, which is the point of pinning them here rather than reading one of
the files as the authority):

  gplsrc/sd_tls.h            server + BASIC-socket client (sd.exe)
  gplsrc/sdclilib/sd_tls.h   native client DLLs
      SD_TLS_BINDING_BYTES 32, LABEL EXPORTER-Channel-Binding,
      GS2 p=tls-exporter,, , HANDSHAKE_MS 10000

  gplsrc/keys.h              SKT_TLS 0x01000000, SKT_INFO_TLS_CBIND 8,
                             SD_TLS_CBIND 110
  sdsys/syscom/keys.h        the BASIC mirror: SKT$TLS, SKT$INFO.TLS.CBIND,
                             SD_TLS_CBIND, same three values

And three more hand-kept copies of the GS2 header and binding label (added
15 Sep 26, RELEASE_1.1 42, Linux parity - mailbox 15 Sep 14:20):
  gplbld/scram-probe.py      GS2_BOUND, BINDING_LABEL
  sdsys/gpl.bp/apisrvr       the 'p=tls-exporter,,' code literal
  sdsys/gpl.bp/sdclient      the 'p=tls-exporter,,' code literal
The BASIC pair name the header in a COMMENT too, which does not count.

A CONTROL asserts the scan actually found each constant, so a renamed or
deleted define fails loudly rather than passing because there was nothing to
compare.

Exit 0 all agree, 1 a mismatch, 2 the test could not run (a file or a constant
was not found - the null case, refused).
"""

import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)  # sdb_ai/sd64

# The wire contract, pinned.  These are the values row 41 / Linux S.19 fix.
C_CONSTS = {
    "SD_TLS_BINDING_BYTES": "32",
    "SD_TLS_BINDING_LABEL": '"EXPORTER-Channel-Binding"',
    "SD_TLS_GS2_HEADER": '"p=tls-exporter,,"',
    "SD_TLS_HANDSHAKE_MS": "10000",
}
KEY_CONSTS = {
    "SKT_TLS": "0x01000000",
    "SKT_INFO_TLS_CBIND": "8",
    "SD_TLS_CBIND": "110",
}

checks = 0
fails = 0


def fail(msg):
    global fails
    fails += 1
    print("  [FAIL] " + msg)


def ok(msg):
    print("  [PASS] " + msg)


def read(path):
    p = os.path.join(ROOT, path)
    if not os.path.exists(p):
        print("  [FAIL] missing file: " + path)
        sys.exit(2)
    with open(p, encoding="ISO-8859-1") as f:
        return f.read()


def c_define(text, name):
    """The value of a C `#define NAME value` (value = rest of line, trimmed of
    a trailing comment)."""
    m = re.search(r"^\s*#define\s+" + re.escape(name) + r"\s+(.+?)\s*(/\*.*)?$",
                  text, re.M)
    return m.group(1).strip() if m else None


def basic_define(text, name):
    """The value of a BASIC `$define NAME value` (value up to a ;* comment)."""
    m = re.search(r"^\s*\$define\s+" + re.escape(name) + r"\s+(.+?)\s*(;\*.*)?$",
                  text, re.M)
    return m.group(1).strip() if m else None


def py_assign(text, name):
    """The value of a Python `NAME = value` (value up to a # comment)."""
    m = re.search(r"^\s*" + re.escape(name) + r"\s*=\s*(.+?)\s*(#.*)?$", text, re.M)
    return m.group(1).strip() if m else None


def basic_code_literal(text, bare):
    """`bare` if the quoted literal 'bare' appears on a NON-comment line of a
    BASIC program, else None.  15 Sep 26 - the point of "comments do not count"
    (Linux, mailbox 15 Sep 14:20): apisrvr and sdclient each name the header in
    a comment as well as in code, and a guard that matched the comment would
    pass on a program whose code had drifted.  A whole-line comment starts with
    * or ! after optional whitespace; an inline comment starts ;* or ;!."""
    needle = "'" + bare + "'"
    for line in text.splitlines():
        if line.strip()[:1] in ("*", "!"):
            continue
        for marker in (";*", ";!"):
            i = line.find(marker)
            if i != -1:
                line = line[:i]
        if needle in line:
            return bare
    return None


def expect(where, got, want, label):
    global checks
    checks += 1
    if got is None:
        fail("%s: %s not found (control)" % (where, label))
    elif got != want:
        fail("%s: %s is %r, expected %r" % (where, label, got, want))
    else:
        ok("%s %s = %s" % (where, label, got))


def main():
    server_h = read("gplsrc/sd_tls.h")
    client_h = read("gplsrc/sdclilib/sd_tls.h")
    keys_h = read("gplsrc/keys.h")
    syscom_h = read("sdsys/syscom/keys.h")

    for name, want in C_CONSTS.items():
        expect("gplsrc/sd_tls.h", c_define(server_h, name), want, name)
        expect("gplsrc/sdclilib/sd_tls.h", c_define(client_h, name), want, name)

    for name, want in KEY_CONSTS.items():
        expect("gplsrc/keys.h", c_define(keys_h, name), want, name)

    # BASIC uses $define and SKT$TLS / SKT$INFO.TLS.CBIND spellings.
    expect("sdsys/syscom/keys.h", basic_define(syscom_h, "SKT$TLS"),
           "0x01000000", "SKT$TLS")
    expect("sdsys/syscom/keys.h", basic_define(syscom_h, "SKT$INFO.TLS.CBIND"),
           "8", "SKT$INFO.TLS.CBIND")
    expect("sdsys/syscom/keys.h", basic_define(syscom_h, "SD_TLS_CBIND"),
           "110", "SD_TLS_CBIND")

    # 15 Sep 26 - RELEASE_1.1 42, Linux parity (mailbox 15 Sep 14:20).  The GS2
    # header and its binding label are hand-copied into three more places the
    # compiler never cross-checks: the probe, and the two BASIC programs that
    # build and check the login.  Pinned to the SAME contract as the headers
    # above (not read from one of them as authority), so a drift on any side is
    # what fails.  The bare strings come from the C values already pinned.
    probe = read("gplbld/scram-probe.py")
    apisrvr = read("sdsys/gpl.bp/apisrvr")
    sdclient = read("sdsys/gpl.bp/sdclient")

    gs2_bare = C_CONSTS["SD_TLS_GS2_HEADER"].strip('"')        # p=tls-exporter,,
    label_bare = C_CONSTS["SD_TLS_BINDING_LABEL"].strip('"')   # EXPORTER-Channel-Binding

    expect("gplbld/scram-probe.py", py_assign(probe, "GS2_BOUND"),
           '"%s"' % gs2_bare, "GS2_BOUND")
    expect("gplbld/scram-probe.py", py_assign(probe, "BINDING_LABEL"),
           'b"%s"' % label_bare, "BINDING_LABEL")
    expect("sdsys/gpl.bp/apisrvr", basic_code_literal(apisrvr, gs2_bare),
           gs2_bare, "GS2 header literal (code, not comment)")
    expect("sdsys/gpl.bp/sdclient", basic_code_literal(sdclient, gs2_bare),
           gs2_bare, "GS2 header literal (code, not comment)")

    print("\n%d checks, %d failed" % (checks, fails))
    if checks < len(C_CONSTS) * 2 + len(KEY_CONSTS) + 3 + 4:
        print("  [FAIL] fewer checks ran than expected (null case)")
        sys.exit(2)
    sys.exit(1 if fails else 0)


if __name__ == "__main__":
    main()
