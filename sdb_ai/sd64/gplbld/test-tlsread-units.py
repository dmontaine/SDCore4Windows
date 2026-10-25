#!/usr/bin/env python3
"""test-tlsread-units.py - the READ of a TLS socket gives up at the caller's timeout (S.73 item 2, the silent server), as invariants read off the source.

  python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/test-tlsread-units.py
  python3 .../test-tlsread-units.py --selftest

No sudo, no install, no sd.  Exit 0 every check passed, 1 a check failed, 2 it could not run.  Written 20 Oct 26.

THE FAULT (found 19 Oct 26 by sandbox-netfile.py, fixed 20 Oct 26 on the owner's word "silent-server your choice"): READ.SOCKET waited on the descriptor for its timeout and then called
sd_tls_client_read(), which blocks in SSL_read.  What had made the descriptor readable need not be application data: the session tickets a TLS 1.3 server sends after the handshake, or half
of a TLS record, so SSL_read took them and waited for the rest with no limit of its own (5.0 s against a server that closes a silent connection after 5, with NETREPLY=3; 12 s for one that
held the connection).  The TLS handshake of OPEN.SOCKET was also bound by 15 seconds fixed, whatever the fourth argument (NETWAIT) said; and a reply cut in the middle of its BODY left
server.error and ServerStatus set from the header it had read, so the $netfile handler took it for an answer.

THE CURE: the TLS read never waits (sd_tls_client_read_now, the descriptor non-blocking for the one call and put back, WANT_READ answered SD_TLS_NOT_YET), op_readskt waits on the
descriptor for the time that is LEFT (tls_read_by_deadline, counted from before the first wait), the handshake gets the fourth argument when there is one, and read.packet of the
class assigns the reply's error and status only when the body is in.

***WHAT THIS IS, AND WHAT IT IS NOT.***  It reads the C and BASIC as text with the comments removed.  IT RUNS NOTHING, so it cannot say that anything gives up on time: that is
sandbox-netfile.py section timeout (a fake that never answers the hello, one that never sends the Ack, two that send half of a TLS record, one that answers late, and the mid-reply
rows, each with the real seconds printed) and netfake.py --selftest (the fakes themselves).  What a text check is for here is the SHAPE no runtime row sees: the blocking call is not
reachable from READ.SOCKET, the descriptor is given back in the mode it was in on every path, the deadline is counted from the start and not restarted, and the order of the
assignments in read.packet.

--selftest runs every check on the real sources and then on a copy with one deliberate fault at a time: each must make a check fail.
"""

import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SD64 = os.path.normpath(os.path.join(HERE, ".."))
FILES = {"op_skt.c": os.path.join(SD64, "gplsrc", "op_skt.c"), "sd_tls.c": os.path.join(SD64, "gplsrc", "sd_tls.c"), "sd_tls.h": os.path.join(SD64, "gplsrc", "sd_tls.h"),
         "sdclient": os.path.join(SD64, "sdsys", "gpl.bp", "sdclient")}


def strip_c(src):
    """Comments out of C (a /* */ block, then a // line), strings left alone: nothing here has a comment marker in a string."""
    src = re.sub(r"/\*.*?\*/", "", src, flags=re.S)
    return re.sub(r"//[^\n]*", "", src)


def strip_bas(src):
    out = []
    for line in src.split("\n"):
        s = line.lstrip()
        if s.startswith("*") or s.startswith("!"):
            out.append("")
            continue
        cut = line.find(";*")
        out.append(line if cut < 0 else line[:cut])
    return "\n".join(out)


def squeeze(text):
    return re.sub(r"\s+", " ", text).strip()


def ordered(text, *needles):
    pos = -1
    for n in needles:
        p = text.find(n, pos + 1)
        if p < 0:
            return False
        pos = p
    return True


def c_function(text, header):
    """The text from HEADER (the start of a definition, up to its opening brace) to the brace that closes it; empty when not found."""
    i = text.find(header)
    if i < 0:
        return ""
    j = text.find("{", i)
    depth, k = 0, j
    while k < len(text):
        if text[k] == "{":
            depth += 1
        elif text[k] == "}":
            depth -= 1
            if depth == 0:
                return text[i:k + 1]
        k += 1
    return ""


def load():
    raw = {}
    for n, p in FILES.items():
        with open(p, encoding="utf-8", errors="replace") as f:
            raw[n] = f.read()
    return raw


def checks(raw):
    skt = squeeze(strip_c(raw["op_skt.c"]))
    tls = squeeze(strip_c(raw["sd_tls.c"]))
    hdr = squeeze(strip_c(raw["sd_tls.h"]))
    cls = strip_bas(raw["sdclient"])
    readskt = squeeze(c_function(strip_c(raw["op_skt.c"]), "void op_readskt()"))
    helper = squeeze(c_function(strip_c(raw["op_skt.c"]), "Private int tls_read_by_deadline("))
    now = squeeze(c_function(strip_c(raw["sd_tls.c"]), "int sd_tls_client_read_now("))
    rp = ""
    a = re.search(r"^local function read\.packet\(\)\s*$", cls, re.M)
    b = re.search(r"^local subroutine disconnect\.session\s*$", cls, re.M)
    if a and b and b.start() > a.start():
        rp = squeeze(cls[a.start():b.start()])
    out = []

    def add(i, what, ok, detail=""):
        out.append((i, what, bool(ok), detail))

    add("T0", "NULL CASE: op_readskt, tls_read_by_deadline, sd_tls_client_read_now and read.packet were all found (a check on nothing would pass)",
        len(readskt) > 500 and len(helper) > 150 and len(now) > 200 and len(rp) > 300, "%d / %d / %d / %d bytes" % (len(readskt), len(helper), len(now), len(rp)))
    add("T1", "READ.SOCKET'S TLS BRANCH is the deadline read, which gives the descriptor's wait the caller's timeout (0 for a non-blocking read) and the start counted before the first wait; the blocking sd_tls_client_read() is called nowhere in op_skt.c",
        "tls_read_by_deadline((SD_TLS_CLIENT*)sock->tls, skt, skt_buff, max_len, (blocking) ? timeout : 0, wait_start, &gave_up)" in readskt and "sd_tls_client_read(" not in skt
        and "if (gave_up) goto exit_op_readskt;" in readskt, "")
    add("T2", "THE START IS TAKEN BEFORE THE FIRST WAIT: wait_start, then the wait on the descriptor, then the deadline read (so what the first wait used is not given back)",
        ordered(readskt, "wait_start = net_now_ms();", "socket_wait(skt, TRUE, (blocking) ? timeout : 0)", "tls_read_by_deadline("), "")
    add("T3", "THE DEADLINE READ loops, asks the non-waiting read, gives up with ER_TIMEOUT when nothing is left of the time counted from the START, and otherwise waits on the descriptor for what IS left",
        ordered(helper, "for (;;) {", "sd_tls_client_read_now(tls, buf, len)", "if (n != SD_TLS_NOT_YET) return n;", "left = (int)((start_ms + wait_ms) - net_now_ms());",
                "if (left <= 0) { process.status = ER_TIMEOUT; *gave_up = TRUE; return 0; }", "socket_wait(skt, TRUE, left)") and "sd_tls_client_read(" not in helper, "")
    add("T4", "THE NON-WAITING READ makes the descriptor non-blocking for the one call, and gives back the mode it had on EVERY path (one restore, after the loop, before the one return)",
        ordered(now, "fcntl(c->fd, F_SETFL, flags | O_NONBLOCK)", "for (;;) {", "SSL_read(", "fcntl(c->fd, F_SETFL, flags);", "return result;") and now.count("return result;") == 1
        and now.count("return -1;") == 1 and now.count("F_SETFL, flags);") == 1, "")
    add("T5", "THE CASES: want-read comes back as SD_TLS_NOT_YET and is never waited for inside; want-write is waited for a bounded number of times; zero return is a closed session",
        ordered(now, "SSL_ERROR_ZERO_RETURN", "result = 0;", "SSL_ERROR_WANT_READ", "result = SD_TLS_NOT_YET;", "SSL_ERROR_WANT_WRITE", "waited_for_write++ >= 10)", "result = SD_TLS_NOT_YET;")
        and "SSL_ERROR_WANT_READ) { result = SD_TLS_NOT_YET; break; }" in now, "")
    add("T6", "THE HEADER declares SD_TLS_NOT_YET as -2 (below zero, so a caller that treated it as 'bytes' could not) and the read", "#define SD_TLS_NOT_YET (-2)" in hdr and "int sd_tls_client_read_now(" in hdr, "")
    add("T7", "THE HANDSHAKE is bound by the fourth argument of OPEN.SOCKET (NETWAIT) when there is one, and by the 15 seconds that were there before when there is not",
        "sd_tls_client_start(skt, (connect_timeout > 0) ? (connect_timeout * 1000) : (SD_TLS_HANDSHAKE_MS + 5000)," in skt, "")
    body_pos = rp.find("n -= len(s) repeat")
    err_pos = rp.find("server.error = hdr.error")
    st_pos = rp.find("ServerStatus = hdr.status")
    add("T8", "THE CLASS TAKES A REPLY'S ERROR AND STATUS FROM THE HEADER ONLY WHEN THE BODY IS IN: they are kept in hdr.error and hdr.status while the body is read, and assigned after the loop that reads it; "
        "no other assignment of server.error or ServerStatus is in read.packet",
        body_pos > 0 and err_pos > body_pos and st_pos > body_pos and rp.count("server.error =") == 1 and rp.count("ServerStatus =") == 1 and "hdr.error = oconv(" in rp and "hdr.status = oconv(" in rp,
        "body at %d, error at %d, status at %d" % (body_pos, err_pos, st_pos))
    add("T9", "THE EARLY EXITS of read.packet (a header that is not a length, a body that does not come) return false before either is assigned",
        ordered(rp, "if pkt.bytes < 10 then return @false", "if maxpacket > 0 and pkt.bytes > maxpacket then return @false", "hdr.error = oconv(", "if status() then return @false", "server.error = hdr.error"), "")
    return out


def run(raw, quiet=False):
    rows = checks(raw)
    bad = [r for r in rows if not r[2]]
    if not quiet:
        for i, what, ok, detail in rows:
            print("  [%s] %s %s%s" % ("PASS" if ok else "FAIL", i, what, ("   <- " + detail) if (detail and not ok) else ""))
    return rows, bad


MUT = [
    ("op_skt.c", "READ.SOCKET calls the blocking read again", "rcvd_bytes = tls_read_by_deadline((SD_TLS_CLIENT*)sock->tls, skt, skt_buff, max_len, (blocking) ? timeout : 0, wait_start, &gave_up);",
     "rcvd_bytes = sd_tls_client_read((SD_TLS_CLIENT*)sock->tls, skt_buff, max_len); gave_up = FALSE;"),
    ("op_skt.c", "the deadline read is told a different timeout (the caller's is lost)", "(blocking) ? timeout : 0, wait_start, &gave_up);", "30000, wait_start, &gave_up);"),
    ("op_skt.c", "a gave-up read is read on", "    if (gave_up)\n      goto exit_op_readskt;\n    ts_init(&head, max_len);\n  } else {", "    ts_init(&head, max_len);\n  } else {"),
    ("op_skt.c", "the start is taken after the first wait", "  wait_start = net_now_ms();\n  if ((sock->tls == NULL) ||\n      (sd_tls_client_pending((SD_TLS_CLIENT*)sock->tls) <= 0)) {\n    if (!socket_wait(skt, TRUE, (blocking) ? timeout : 0))\n      goto exit_op_readskt;\n  }\n",
     "  if ((sock->tls == NULL) ||\n      (sd_tls_client_pending((SD_TLS_CLIENT*)sock->tls) <= 0)) {\n    if (!socket_wait(skt, TRUE, (blocking) ? timeout : 0))\n      goto exit_op_readskt;\n  }\n  wait_start = net_now_ms();\n"),
    ("op_skt.c", "the deadline is restarted at every wait", "left = (int)((start_ms + wait_ms) - net_now_ms());", "left = wait_ms;"),
    ("op_skt.c", "nothing left of the time is not a timeout", "process.status = ER_TIMEOUT;\n        *gave_up = TRUE;\n        return 0;", "continue;"),
    ("op_skt.c", "the helper hands SD_TLS_NOT_YET to the caller", "    if (n != SD_TLS_NOT_YET)\n      return n;", "    return n;"),
    ("op_skt.c", "the handshake is fixed at 15 seconds again", "(connect_timeout > 0) ? (connect_timeout * 1000) : (SD_TLS_HANDSHAKE_MS + 5000)", "(SD_TLS_HANDSHAKE_MS + 5000)"),
    ("sd_tls.c", "the descriptor is not given back (blocking mode is not restored)", "  (void)fcntl(c->fd, F_SETFL, flags);\n  return result;", "  return result;"),
    ("sd_tls.c", "the descriptor is never made non-blocking", "fcntl(c->fd, F_SETFL, flags | O_NONBLOCK) < 0", "0"),
    ("sd_tls.c", "want-read is waited for inside the read", "    if (e == SSL_ERROR_WANT_READ) {\n      result = SD_TLS_NOT_YET;\n      break;\n    }", "    if (e == SSL_ERROR_WANT_READ)\n      continue;"),
    ("sd_tls.c", "want-write is waited for without a bound", "if (waited_for_write++ >= 10) {", "if (waited_for_write++ >= 100000000) {"),
    ("sd_tls.c", "a closed session is an error", "    if (e == SSL_ERROR_ZERO_RETURN) {\n      result = 0;", "    if (e == SSL_ERROR_ZERO_RETURN) {\n      result = -1;"),
    ("sd_tls.h", "SD_TLS_NOT_YET is a number of bytes", "#define SD_TLS_NOT_YET (-2)", "#define SD_TLS_NOT_YET (2)"),
    ("sdclient", "a reply's error is assigned from the header before the body", "   hdr.error = oconv(pkt.header[5,2], 'ISL')\n", "   hdr.error = oconv(pkt.header[5,2], 'ISL')\n   server.error = hdr.error\n"),
    ("sdclient", "a reply's status is assigned from the header before the body", "   hdr.status = oconv(pkt.header[7,4], 'ILL')\n", "   hdr.status = oconv(pkt.header[7,4], 'ILL')\n   ServerStatus = hdr.status\n"),
    ("sdclient", "the status is never assigned", "   server.error = hdr.error\n   ServerStatus = hdr.status\n   return @true", "   server.error = hdr.error\n   return @true"),
]


def selftest():
    raw = load()
    rows, bad = run(raw)
    if bad:
        print("selftest: the real sources already fail %d check(s)" % len(bad))
        return 1
    killed, missed = 0, []
    for fname, what, old, new in MUT:
        if raw[fname].count(old) != 1:
            print("  [CANNOT] %s: the text to change is found %d times in %s, not once" % (what, raw[fname].count(old), fname))
            return 2
        m = dict(raw)
        m[fname] = raw[fname].replace(old, new)
        rows_m, bad_m = run(m, quiet=True)
        if bad_m:
            killed += 1
            print("  [killed] %s  <- %s" % (what, ", ".join(r[0] for r in bad_m)))
        else:
            missed.append(what)
            print("  [MISSED] %s" % what)
    print("selftest: %d mutants, %d killed, %d missed" % (len(MUT), killed, len(missed)))
    return 0 if not missed else 1


def main():
    for p in FILES.values():
        if not os.path.isfile(p):
            print("CANNOT RUN: %s is not there" % p)
            return 2
    if "--selftest" in sys.argv:
        return selftest()
    rows, bad = run(load())
    print("test-tlsread-units: %d passed, %d failed" % (len(rows) - len(bad), len(bad)))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
