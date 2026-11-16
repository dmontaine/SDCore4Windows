"""RELEASE_1.1 331 (Linux S.256): SDSYS through the API from another computer, shut as delivered.

WHAT IT PROTECTS.  The owner, 16 Nov 2026: "deliver closed and secure and let the admin decide to loosen"; "Full admin rights only if
API into SDSYS, and normal limited rights if API into other accounts"; for Windows, "SDSYS, SD password".  Windows Core's form of
Linux's template (3f8d2fa2, 42e05d2a, 2fd1731f):

  - the FRONT (apisrvr vb.scram.final, LocalSystem): a SCRAM login as sdsys is the remote door; shut (10174) unless
    <ProgramData>/SD/sd-tls/sdsys-api says on, refused by name (15116) unless an entry holds the client's address (!addrmatch, the
    IPv4-mapped peer as IPv4); sdsys skips the sdapi/sdfiles routes only through that door; the grant's audit line comes after the
    handover succeeded.
  - the READER: OPENSEQ READONLY (never OSREAD: Linux measured it reads nothing before an account is entered), the parent of @SDSYS
    with either slash, the first line must be "on", closed on both paths.
  - the SESSION (the handed-over process): an SDSYS pre-authenticated session is the administrator only while K$API.PREAUTH <3> says
    its own token is elevated, and is refused (10174) otherwise; ONE K$ADMINISTRATOR grant in apisrvr; the flag is in the common
    block; account.entry.check admits sdsys for the local door or this flag, and still asks SDSYS and the administrator.
  - the KERNEL (op_kernel.c K_API_PREAUTH): the third field is IsElevated() for a pre-authenticated session, 0 when undetermined.
  - REMOTE.SDSYS API: words from @sentence, character-checked, at most 64 a word and 32 entries, ANY only alone, never in the
    broker's job, through sd-sdsysapi.ps1; no keyword reports both doors.
  - !addrmatch: the code section is Linux 3f8d2fa2's byte for byte (SHA-256 below), so it is tested there (identical code, tested once).
  - the messages: 10174 (Linux's id and text), 15116-15120 (Linux's 14116-14120), 12928's API lines.
  - sd-sdsysapi.ps1, RUN: its normalisation agrees with Python's ipaddress.ip_network(strict=False), the rule of Linux's helper; /0,
    "any" with another entry, 33 entries and a bad entry are refused (exit 1); in a scratch directory it writes "on" then the entries
    (ASCII, LF), replaces the list in one step leaving no temporary file, reports, and deletes it for off; a directory that is a link
    (a junction) is refused (exit 2).  It never touches <ProgramData>: every run passes -Dir or -DryRun.

HOW IT WAS PROVED.  --selftest applies mutants to in-memory copies of the sources (the live files are only read) and one to a
temporary copy of the helper; each must turn its row red.

  python gplbld/test-sdsysapi-units.py [--selftest]

Exit 0 all passed, 1 a check failed, 2 the tree is not there to measure.
"""

import hashlib
import ipaddress
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
SD64 = os.path.normpath(os.path.join(HERE, os.pardir))
GPLBP = os.path.join(SD64, "sdsys", "gpl.bp")
MSGDIR = os.path.join(SD64, "sdsys", "messages")
FILES = {
    "apisrvr": os.path.join(GPLBP, "apisrvr"),
    "remotesdsys": os.path.join(GPLBP, "remotesdsys"),
    "radmin": os.path.join(GPLBP, "radmin"),
    "addrmatch": os.path.join(GPLBP, "addrmatch"),
    "op_kernel": os.path.join(SD64, "gplsrc", "op_kernel.c"),
    "stage": os.path.join(HERE, "stage.py"),
}
HELPER = os.path.join(HERE, "sd-sdsysapi.ps1")

# Linux 3f8d2fa2's sdsys/gpl.bp/addrmatch, the lines from "* START-CODE" to "* END-CODE" inclusive (LF), measured 16 Nov 2026
ADDRMATCH_CODE_SHA = "c0f24b7070dd03b62a021242a1799b1f3e0edd178893176af5bfbf2239491675"


def read(p):
    with open(p, "rb") as f:
        return f.read().decode("latin-1")


def squeeze(text):
    """Each line stripped of leading and trailing blanks, full-line BASIC comments dropped: the checks below are about statements and
    their order, not indentation."""
    out = []
    for line in text.split("\n"):
        s = line.strip()
        if s.startswith("*") and not s.startswith("*/"):
            continue
        out.append(s)
    return "\n".join(out)


def ordered(text, parts, start=0):
    pos = []
    at = start
    for p in parts:
        i = text.find(p, at)
        if i < 0:
            return False, pos + ["missing: " + p[:60]]
        pos.append(i)
        at = i + len(p)
    return True, pos


def region(text, begin, end):
    a = text.find(begin)
    if a < 0:
        return ""
    b = text.find(end, a + len(begin))
    return text[a:] if b < 0 else text[a:b]


def checks(src):
    rows = []

    def ck(key, label, ok, detail=""):
        rows.append((key, label, bool(ok), detail))

    a = squeeze(src["apisrvr"])
    final = region(a, "vb.scram.final:", "\nscram.bad.message:")

    # D1 the front door, after the proof and before the identity
    ok, pos = ordered(final, [
        "if SDEXT(scram.derived : @FM : scram.storedkey, @TRUE, SD_CTEQUAL) # '1' then",
        "if downcase(scram.user) = 'sdsys' then\napi.peer.addr = system(42)\ngosub read.sdsys.api",
        "if not(sdsys.api.on) then",
        "abort.message = sysmsg(10174)", "goto exit.vb.scram.fail",
        "call !addrmatch(sdsys.api.peer, sdsys.api.list, sdsys.api.listed)",
        "if not(sdsys.api.listed) then",
        "abort.message = sysmsg(15116, api.peer.addr)", "goto exit.vb.scram.fail",
        "sdsys.api.from = sdsys.api.peer\napi.in.sdapi = @true\napi.route.stat = 0\nend else\napi.in.sdapi = is_grp_member(scram.user, 'sdapi')",
        "set.name = kernel(K$SET.USERNAME, scram.user)"])
    ck("D1", "the front: a SCRAM login as sdsys meets the remote door after the proof and before the identity - shut is refused (10174), "
       "an address no entry holds is refused by name (15116, !addrmatch); only an admitted sdsys skips the sdapi/sdfiles routes", ok, str(pos))

    ck("D2", "the client's address is system(42), and an IPv4-mapped IPv6 peer is compared as its IPv4 form",
       "if sdsys.api.peer[1,7] = '::ffff:' and index(sdsys.api.peer, '.', 1) then sdsys.api.peer = sdsys.api.peer[8,999]" in final
       and final.find("sdsys.api.peer = downcase(trim(api.peer.addr))") < final.find("call !addrmatch("), "")

    rd = region(a, "\nread.sdsys.api:", "\nscram.bad.message:")
    ok, pos = ordered(rd, [
        "sdsys.api.on = @false\nsdsys.api.list = ''",
        "sdsys.api.sp = convert(char(92), '/', @sdsys)",
        "sdsys.api.path = sdsys.api.sp[1, index(sdsys.api.sp, '/', sdsys.api.n) - 1] : '/sd-tls/sdsys-api'",
        "openseq sdsys.api.path readonly to sdsys.api.f then",
        "if downcase(trim(sdsys.api.line)) = 'on' then\nsdsys.api.on = @true",
        "close sdsys.api.f\nend else\nclose sdsys.api.f\nend\nreturn"])
    no_osread = all(not ln.lower().startswith("osread ") and " osread " not in ln.lower() for ln in a.split("\n"))
    ck("D3", "the reader: off unless the first line is on; <parent of @SDSYS>/sd-tls/sdsys-api, found with either slash; OPENSEQ READONLY, "
       "closed on both paths; no OSREAD anywhere in apisrvr (Linux's A5: it reads nothing before an account is entered)", ok and no_osread,
       str(pos) + ("" if no_osread else " OSREAD found"))

    start = region(a, "api.preauth = kernel(K$API.PREAUTH, 0)", "openpath \"voc\" to voc else")
    ok, pos = ordered(start, [
        "sdsys.api.remote = @false",
        "if api.preauth<1> = 1 and downcase(logname) = 'sdsys' then",
        "if api.preauth<3> # 1 then",
        "abort.message = sysmsg(10174)", "goto connection.failed",
        "void kernel(K$ADMINISTRATOR, 1)\nsdsys.api.remote = @true",
        "if api.preauth<1> = 1 and downcase(logname) # 'sdsys' then"])
    grants = a.count("kernel(K$ADMINISTRATOR, 1)")
    ck("D4", "the session: an SDSYS pre-authenticated session is refused (10174) unless its own token is elevated (K$API.PREAUTH <3>), "
       "and only then is the administrator; apisrvr grants K$ADMINISTRATOR in that one place", ok and grants == 1, str(pos) + " grants=%d" % grants)

    common = region(a, "common /$APISRVR/", "deffun ")
    ck("D5", "sdsys.api.remote is in the /$APISRVR/ common block, so an abort keeps it", "sdsys.api.remote" in common, "")

    ck("D6", "account.entry.check admits sdsys for the local door or the remote door's session, and still only for the Windows user SDSYS "
       "holding K$ADMINISTRATOR",
       "ent.member = (local.session or sdsys.api.remote) and (ent.who = 'SDSYS') and kernel(K$ADMINISTRATOR, -1)" in a, "")

    disp = region(a, "handoff.ok = kernel(K$HANDOFF, scram.user)", "until done")
    ok1, pos1 = ordered(disp, ["if not(handoff.ok) then", "end else",
                               "if sdsys.api.from # '' then\nvoid kernel(K$AUDIT, 'elevation granted reason=sdsys api from=' : sdsys.api.from)"])
    loc = region(a, "\nvb.local.login:", "\nexit.vb.local.login:")
    ok2, pos2 = ordered(loc, ["local.session = @true", "if local.who = 'sdsys' and kernel(K$ADMINISTRATOR, -1) then",
                              "void kernel(K$AUDIT, 'elevation granted reason=sdsys api from=this machine')"])
    ok3 = a.count("'elevation granted reason=sdsys api from=") == 2
    ck("D7", "the audit lines, Linux's words: 'elevation granted reason=sdsys api from=<address>' only after a handover that succeeded, "
       "'from=this machine' for the local door only when it is the administrator; nowhere else", ok1 and ok2 and ok3, str(pos1) + str(pos2))

    ck("D8", "sdsys.api.from is emptied before the request loop, so only this connection's door can set it",
       a.find("sdsys.api.from = ''") >= 0 and a.find("sdsys.api.from = ''") < a.find("\nloop\nunload.object"), "")

    k = src["op_kernel"]
    kc = region(k, "    case K_API_PREAUTH:", "      break;")
    ok, pos = ordered(kc, ["int elevated = 0;", "if (api_preauth) {", "elevated = IsElevated(&why) ? 1 : 0;",
                           "if (why != PRIV_ANSWERED) {", "elevated = 0;", "\"%d%c%s%c%d\"", "FIELD_MARK,", "who, FIELD_MARK, elevated);"])
    ck("K1", "K$API.PREAUTH <3>: IsElevated() of a pre-authenticated session's own token, 0 for any other session and 0 when undetermined",
       ok, str(pos))

    r = squeeze(src["remotesdsys"])
    ar = region(r, "\napi.request:", "\napi.status:")
    ok, pos = ordered(ar, [
        "if not(in.job) then\nwords = trim(@sentence)\nconvert ' ' to @fm in words\napi.words = field(words, @fm, 3, 9999)",
        "if downcase(a) = 'any' then\nif nwords # 2 then", "crt sysmsg(15119)", "return",
        "convert '0123456789abcdefABCDEF.:/' to '' in chk\nif chk # '' or len(a) < 1 or len(a) > 64 then", "crt sysmsg(15118, a)", "return",
        "if addrs = '' or dcount(addrs, @fm) > 32 then", "crt sysmsg(15119)", "return",
        "helper.args = '-Action on -Entries ' : q : change(addrs, @fm, q : ',' : q) : q",
        "helper.script = '/sd-sdsysapi.ps1'\ngosub run.helper\nhelper.script = '/remote-admin.ps1'",
        "crt sysmsg(15120)", "crt sysmsg(15117, change(addrs, @fm, ','))",
        "void kernel(K$AUDIT, 'remote.sdsys api ' : api.action"])
    ck("R1", "REMOTE.SDSYS API: at the console the words after API from @sentence (in the job, RUN.REQUEST's); each address only hex, '.', ':' "
       "and '/', at most 64; ANY only alone; one to 32 entries; a refusal RETURNS (the job's exit status says so); quoted into "
       "sd-sdsysapi.ps1's command; 15120 for any, 15117 for a list; audited",
       ok and "stop sysmsg(" not in ar, str(pos))
    rr = r[r.find("\nrun.request:"):] if "\nrun.request:" in r else ""      # to the end of the program: run.request is its last routine
    ok, pos = ordered(rr, [
        "run.api = (run.verb = 'remote.sdsys' and run.words<1> = 'api')",
        "if run.api then\nsw = trim(@sentence)\nconvert ' ' to @fm in sw\nrun.words = 'api'\nfor i = 5 to dcount(sw, @fm)",
        "if run.api and i >= 3 and run.words<2> = 'on' then",
        "if w # 'any' and (len(w) < 1 or len(w) > 64 or convert('0123456789abcdef.:/', '', w) # '') then run.ok = @false",
        "end else\nif len(w) < 1 or len(w) > 32 or convert('abcdefghijklmnopqrstuvwxyz0123456789._-', '', w) # '' then run.ok = @false",
        "case action = 'ssh' and run.words<2> = 'off' and dcount(run.words, @fm) = 2\ngosub off.request",
        "case action = 'ssh' and dcount(run.words, @fm) = 1\ngosub show.status",
        "case action = 'api'\napi.words = field(run.words, @fm, 2, 9999)\ngosub api.request"])
    ck("R3", "the broker's job (Linux mail 2000): REMOTE.SDSYS API's words are taken whole from the job's sentence; only after API ON may a word "
       "be an address (hex, '.', ':', '/', at most 64) or any, every other word keeps the word rule; SSH OFF is OFF, SSH alone the report; "
       "SSH ON is not offered", ok and "case action = 'ssh' and run.words<2> = 'on'" not in rr, str(pos))
    cl = squeeze(src["radmin"])
    ok, pos = ordered(cl, [
        "if verb = 'remote.sdsys' and i >= 3 and downcase(words<1>) = 'api' and downcase(words<2>) = 'on' then",
        "if len(w) < 1 or len(w) > 64 or convert('0123456789abcdef.:/', '', w) # '' then\nif w # 'any' then stop sysmsg(2018, words<i>)",
        "end else\nif len(w) < 1 or len(w) > 32 or index('._-', w[1, 1], 1)",
        "if words<1> = 'on' then stop sysmsg(12847, 'remote.sdsys on')",
        "if words<1> = 'ssh' and words<2> = 'on' then stop sysmsg(12847, 'remote.sdsys ssh on')"])
    ck("R4", "SDRADMIN's verb: an address-shaped word only after REMOTE.SDSYS API ON; SSH ON refused here as ON is (the console's)", ok, str(pos))
    top = r[:r.find("\nrun.request:")] if "\nrun.request:" in r else r
    ck("R2", "no keyword reports both doors (remote-admin.ps1 -Status, then the API's); SSH ON | OFF is ON | OFF; API goes to api.request",
       "gosub show.status\nif action = '' then gosub api.status" in top and "if action = 'ssh' then" in top
       and "if action = 'api' then\ngosub api.request" in top, "")

    m = src["addrmatch"]
    code = m[m.find("* START-CODE"):]
    code = code[:code.find("* END-CODE") + len("* END-CODE")] + "\n"
    sha = hashlib.sha256(code.encode("latin-1")).hexdigest()
    ck("A1", "!addrmatch's code is Linux 3f8d2fa2's byte for byte (so it is tested there: identical code, tested once)",
       sha == ADDRMATCH_CODE_SHA, sha)

    msgs = src["messages"]
    want = {"15116": "%1", "15117": "%1", "15118": "%1", "15119": "", "15120": ""}
    mok = all(i in msgs and msgs[i].endswith("\n") and "\r" not in msgs[i] and msgs[i].count("\n") == 1 and (w == "" or w in msgs[i])
              for i, w in want.items())
    mok = mok and "10174" in msgs and msgs["10174"].startswith("SDSYS may be reached through the API from another computer only when the\n")
    mok = mok and "remote.sdsys api {on address ... | off}" in msgs.get("12928", "") and "SDRADMIN" in msgs.get("12928", "")
    ck("M1", "the messages: 15116-15120 one line each (LF, no CR) with their %1; 10174 in Linux's words (test-msgreserved-units.py holds "
       "the whole text); 12928 names the API words and keeps SDRADMIN", mok, "")

    ck("S1", "stage.py ships sd-sdsysapi.ps1 to the program folder", "'sd-sdsysapi.ps1'," in src["stage"], "")
    return rows


# ---------------------------------------------------------------- the helper, run

def ps(helper, args):
    cmd = ["powershell", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", helper] + args
    r = subprocess.run(cmd, capture_output=True, text=True)
    print("    ran: sd-sdsysapi.ps1 " + " ".join(args) + "  -> exit %d" % r.returncode)
    for line in (r.stdout + r.stderr).strip().splitlines():
        print("        | " + line)
    return r.returncode, r.stdout.strip().splitlines()


def py_norm(e):
    n = ipaddress.ip_network(e, strict=False)
    return str(n)


VALID = ["192.168.1.5", "192.168.1.5/24", "10.1.2.3/255.0.0.0", "10.1.2.3/0.0.0.255", "FD00:0:0:0:0:0:0:1",
         "2001:db8::1/48", "1:0:0:2:0:0:0:3", "fe80::1/10", "1.2.3.4/024", "192.168.1.9/24"]
REFUSED = [("010.0.0.1", "not an address or a range: 010.0.0.1"), ("1.2.3.4/0", "a /0 range is every address, and is refused: 1.2.3.4/0"),
           ("::/0", "a /0 range is every address, and is refused: ::/0"), ("1.2.3.4/255.0.255.0", "not an address or a range: 1.2.3.4/255.0.255.0"),
           # 16 Nov 26 (Linux db29dcc7): a mapped /96 is every IPv4 address once written in its IPv4 form
           ("::ffff:0.0.0.0/96", "a /0 range is every address, and is refused: ::ffff:0.0.0.0/96")]
# 16 Nov 26 (Linux db29dcc7, Windows' finding): an IPv4-mapped IPv6 entry of length 96 or more is written as its IPv4 form, which is how
# APISRVR compares a mapped peer; Linux's H1b, the same two entries.
MAPPED = ("::ffff:192.168.1.5,::ffff:10.1.2.0/120", ["192.168.1.5/32", "10.1.2.0/24"])


def helper_rows(helper):
    rows = []

    def ck(key, label, ok, detail=""):
        rows.append((key, label, bool(ok), detail))

    expect = []
    for e in VALID:
        n = py_norm(e)
        if n not in expect:
            expect.append(n)
    rc, out = ps(helper, ["-Action", "on", "-Entries", ",".join(VALID), "-DryRun"])
    got = out[-1].split("then ", 1)[1].split(" ") if rc == 0 and out and "then " in out[-1] else []
    ck("H1", "-DryRun: %d entries give the %d networks Python's ipaddress.ip_network(strict=False) gives, in order, repeats kept once"
       % (len(VALID), len(expect)), rc == 0 and got == expect, "py=%s ps=%s" % (expect, got))
    rc, out = ps(helper, ["-Action", "on", "-Entries", MAPPED[0], "-DryRun"])
    got = out[-1].split("then ", 1)[1].split(" ") if rc == 0 and out and "then " in out[-1] else []
    ck("H1b", "an IPv4-mapped IPv6 entry is written as its IPv4 form (a single address /32, a /120 as /24), the form a mapped peer is "
       "compared in (Linux db29dcc7)", rc == 0 and got == MAPPED[1], "want=%s got=%s" % (MAPPED[1], got))

    bad = []
    for e, line in REFUSED:
        rc, out = ps(helper, ["-Action", "on", "-Entries", e, "-DryRun"])
        if not (rc == 1 and line in out and out[-1] == "sdsys-api on: nothing was changed"):
            bad.append(e)
    rc1, out1 = ps(helper, ["-Action", "on", "-Entries", "any,1.2.3.4", "-DryRun"])
    rc2, out2 = ps(helper, ["-Action", "on", "-Entries", ",".join("10.0.0.%d" % i for i in range(1, 34)), "-DryRun"])
    rc3, out3 = ps(helper, ["-Action", "on", "-Entries", "any", "-DryRun"])
    ck("H2", "refused, exit 1 and 'nothing was changed': a leading zero, /0 (IPv4, IPv6, and a mapped /96), a mask that is neither a "
       "netmask nor a hostmask, any with another entry, 33 entries; any alone is accepted as itself",
       bad == [] and rc1 == 1 and rc2 == 1 and rc3 == 0 and out3 and out3[-1].endswith(": on, then any"),
       "bad=%s any+=%d n33=%d any=%d" % (bad, rc1, rc2, rc3))

    tmp = tempfile.mkdtemp(prefix="sdsysapi-")
    try:
        d = os.path.join(tmp, "sd-tls")
        os.mkdir(d)
        f = os.path.join(d, "sdsys-api")
        rc_a, out_a = ps(helper, ["-Action", "on", "-Entries", "192.168.1.5/24,fd00::1", "-Dir", d])
        body_a = open(f, "rb").read() if os.path.isfile(f) else b""
        rc_b, out_b = ps(helper, ["-Action", "status", "-Dir", d])
        rc_c, out_c = ps(helper, ["-Action", "on", "-Entries", "10.0.0.0/8", "-Dir", d])
        body_c = open(f, "rb").read() if os.path.isfile(f) else b""
        left = sorted(os.listdir(d))
        rc_d, out_d = ps(helper, ["-Action", "off", "-Dir", d])
        gone = not os.path.exists(f)
        rc_e, out_e = ps(helper, ["-Action", "status", "-Dir", d])
        ok = (rc_a == 0 and body_a == b"on\n192.168.1.0/24\nfd00::1/128\n"
              and out_a[-1:] == ["sdsys over the API from other computers: on, from 192.168.1.0/24 fd00::1/128"]
              and rc_b == 0 and out_b[-1:] == ["sdsys over the API from other computers: on, from 192.168.1.0/24 fd00::1/128"]
              and rc_c == 0 and body_c == b"on\n10.0.0.0/8\n" and left == ["sdsys-api"]
              and rc_d == 0 and gone and out_d[-1:] == ["sdsys over the API from other computers: off"]
              and rc_e == 0 and out_e[-1:] == ["sdsys over the API from other computers: off"])
        ck("H3", "in a scratch directory: on writes 'on' then the entries (ASCII, LF) and says so; status reads it back; a second on "
           "REPLACES the list and leaves no temporary file; off deletes it; status then says off",
           ok, "first=%r second=%r left=%s gone=%s" % (body_a, body_c, left, gone))

        target = os.path.join(tmp, "elsewhere")
        os.mkdir(target)
        link = os.path.join(tmp, "linked")
        mk = subprocess.run(["cmd", "/c", "mklink", "/J", link, target], capture_output=True, text=True)
        print("    made a junction for H4: exit %d %s" % (mk.returncode, mk.stdout.strip()))
        rc_f, out_f = ps(helper, ["-Action", "on", "-Entries", "1.2.3.4", "-Dir", link])
        ck("H4", "a directory that is a link (a junction) is refused, exit 2, and nothing is written behind it",
           mk.returncode == 0 and rc_f == 2 and os.listdir(target) == [] and any("is a link" in x for x in out_f),
           "mklink=%d rc=%d target=%s" % (mk.returncode, rc_f, os.listdir(target)))
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    return rows


def load():
    src = {}
    for k, p in FILES.items():
        if not os.path.isfile(p):
            return None, p
        src[k] = read(p)
    msgs = {}
    for i in ("10174", "12928", "15116", "15117", "15118", "15119", "15120"):
        p = os.path.join(MSGDIR, i)
        if os.path.isfile(p):
            msgs[i] = read(p)
    src["messages"] = msgs
    if not os.path.isfile(HELPER):
        return None, HELPER
    return src, None


def report(rows):
    fails = 0
    for key, label, ok, detail in rows:
        print("  [%s] %s %s%s" % ("PASS" if ok else "FAIL", key, label, ("" if ok or not detail else "  -- " + detail)))
        if not ok:
            fails += 1
    return fails


def sub(key, old, new):
    def f(src):
        s = dict(src)
        if old not in s[key]:
            raise KeyError("mutant text not found in %s: %s" % (key, old[:70]))
        s[key] = s[key].replace(old, new, 1)
        return s
    return f


MUTANTS = [
    ("the door is skipped for sdsys", "D1", sub("apisrvr", "               if downcase(scram.user) = 'sdsys' then\n                  api.peer.addr = system(42)",
                                                 "               if 0 then\n                  api.peer.addr = system(42)")),
    ("a shut door admits", "D1", sub("apisrvr", "                  if not(sdsys.api.on) then", "                  if 0 then")),
    ("an unlisted address is admitted", "D1", sub("apisrvr", "                  if not(sdsys.api.listed) then", "                  if 0 then")),
    ("the mapped peer is matched as IPv6", "D2", sub("apisrvr", "if sdsys.api.peer[1,7] = '::ffff:' and index(sdsys.api.peer, '.', 1) then sdsys.api.peer = sdsys.api.peer[8,999]", "null")),
    ("the setting is read with OSREAD", "D3", sub("apisrvr", "               openseq sdsys.api.path readonly to sdsys.api.f then", "               osread sdsys.api.all from sdsys.api.path then")),
    ("any first line is on", "D3", sub("apisrvr", "                     if downcase(trim(sdsys.api.line)) = 'on' then", "                     if 1 then")),
    ("an unelevated SDSYS session is the administrator", "D4", sub("apisrvr", "      if api.preauth<3> # 1 then", "      if 0 then")),
    ("a second grant", "D4", sub("apisrvr", "               local.session = @true\n", "               local.session = @true\n               void kernel(K$ADMINISTRATOR, 1)\n")),
    ("the flag is a plain variable", "D5", sub("apisrvr", "seq.unbuf(SEQ.MAX), ;* 1 when it was opened unbuffered: every line written is flushed\nsdsys.api.remote    ;*", "seq.unbuf(SEQ.MAX)  ;* 1 when it was opened unbuffered: every line written is flushed\n*sdsys.api.remote   ;*")),
    ("any session enters sdsys", "D6", sub("apisrvr", "(local.session or sdsys.api.remote) and (ent.who = 'SDSYS')", "(local.session or 1) and (ent.who = 'SDSYS')")),
    ("the grant is audited before the handover", "D7", sub("apisrvr", "            if sdsys.api.from # '' then\n               void kernel(K$AUDIT, 'elevation granted reason=sdsys api from=' : sdsys.api.from)\n            end\n", "")),
    ("the address outlives the connection", "D8", sub("apisrvr", "\nsdsys.api.from = ''\n", "\n")),
    ("an undetermined elevation counts", "K1", sub("op_kernel", "            elevated = 0;\n", "")),
    ("a refusal stops the job without its status", "R1", sub("remotesdsys", "            crt sysmsg(15118, a)  ;* not an address or a range\n            return", "            stop sysmsg(15118, a)")),
    ("the job reads its words through the parser", "R3", sub("remotesdsys", "   if run.api then\n      sw = trim(@sentence)", "   if 0 then\n      sw = trim(@sentence)")),
    ("an address-shaped word anywhere in the job", "R3", sub("remotesdsys", "      if run.api and i >= 3 and run.words<2> = 'on' then", "      if run.api then")),
    ("the client lets an address through anywhere", "R4", sub("radmin", "      if verb = 'remote.sdsys' and i >= 3 and downcase(words<1>) = 'api' and downcase(words<2>) = 'on' then", "      if verb = 'remote.sdsys' then")),
    ("ssh on is sent", "R4", sub("radmin", "         if words<1> = 'ssh' and words<2> = 'on' then stop sysmsg(12847, 'remote.sdsys ssh on')", "         null")),
    ("a word is not checked", "R1", sub("remotesdsys", "         convert '0123456789abcdefABCDEF.:/' to '' in chk", "         chk = ''")),
    ("any with others", "R1", sub("remotesdsys", "         if nwords # 2 then", "         if 0 then")),
    ("33 entries", "R1", sub("remotesdsys", "      if addrs = '' or dcount(addrs, @fm) > 32 then", "      if addrs = '' then")),
    ("no keyword reports ssh only", "R2", sub("remotesdsys", "      if action = '' then gosub api.status\n", "")),
    ("addrmatch drifts from Linux", "A1", sub("addrmatch", "if len(g) < 1 or len(g) > 3 then return", "if len(g) < 1 or len(g) > 4 then return")),
    ("the helper is not shipped", "S1", sub("stage", "'sd-sdsysapi.ps1',", "")),
]


def selftest(src):
    holes = 0
    for name, want, mut in MUTANTS:
        rows = checks(mut(src))
        red = [k for k, _, ok, _ in rows if not ok]
        caught = want in red
        print("  mutant %-48s want %-3s red %-12s %s" % (name, want, ",".join(red) or "-", "caught" if caught else "NOT CAUGHT"))
        if not caught:
            holes += 1
    # Helper mutants, each on a temporary COPY (the live helper is only read): the run that row's check makes must come out wrong.
    live_sha = hashlib.sha256(open(HELPER, "rb").read()).hexdigest()
    helper_mutants = [
        ("the helper writes a /0 range", "H2",
         "    if ($plen -eq 0) { Refuse ('a /0 range is every address, and is refused: ' + $e) }\n    $bits = Get-Bits $addr\n",
         "    $bits = Get-Bits $addr\n", ["-Action", "on", "-Entries", "1.2.3.4/0", "-DryRun"], lambda rc, out: rc != 1),
        ("a mapped entry is kept in IPv6 form", "H1b",
         "    if ($v6 -and $plen -ge 96 -and", "    if ($false -and $plen -ge 96 -and",
         ["-Action", "on", "-Entries", MAPPED[0], "-DryRun"],
         lambda rc, out: not (rc == 0 and out and out[-1].endswith("then " + " ".join(MAPPED[1])))),
    ]
    tmpd = tempfile.mkdtemp(prefix="sdsysapi-mut-")
    try:
        copy = os.path.join(tmpd, "sd-sdsysapi.ps1")
        text = read(HELPER)
        for name, want, old, new, args, wrong in helper_mutants:
            assert old in text, "helper mutant text not found: " + name
            with open(copy, "wb") as f:
                f.write(text.replace(old, new, 1).encode("latin-1"))
            rc, out = ps(copy, args)
            caught = wrong(rc, out)
            print("  mutant %-48s want %-3s %s" % (name, want, "caught" if caught else "NOT CAUGHT"))
            if not caught:
                holes += 1
    finally:
        shutil.rmtree(tmpd, ignore_errors=True)
    unchanged = hashlib.sha256(open(HELPER, "rb").read()).hexdigest() == live_sha
    print("  the live helper is unchanged by SHA-256: %s" % unchanged)
    print("selftest: %d mutants, %d not caught" % (len(MUTANTS) + len(helper_mutants), holes))
    return 1 if holes or not unchanged else 0


def main(argv):
    print("test-sdsysapi-units: RELEASE_1.1 331 (Linux S.256), SDSYS through the API from another computer")
    for k, p in FILES.items():
        print("  reads %s" % p)
    print("  runs  %s (-DryRun, or -Dir in a temporary directory; never <ProgramData>)" % HELPER)
    src, missing = load()
    if src is None:
        print("test-sdsysapi-units: %s is not there - nothing to measure (exit 2)" % missing)
        return 2
    if "--selftest" in argv:
        return selftest(src)
    rows = checks(src) + helper_rows(HELPER)
    fails = report(rows)
    print("")
    print("test-sdsysapi-units: %d passed, %d failed" % (len(rows) - fails, fails))
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
