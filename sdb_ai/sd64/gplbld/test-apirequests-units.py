#!/usr/bin/env python3
"""test-apirequests-units.py - the API request numbers 49 and 72 are the same in Core and Solo, as invariants read off the source.

  python C:/Users/Don/Projects/SDCore4Windows/sdb_ai/sd64/gplbld/test-apirequests-units.py
  python .../test-apirequests-units.py --selftest

No elevation, no install, no sd.  Exit 0 all checks passed, 1 a check failed, 2 it could not run.  The same file is in both Windows trees and says which one it is
in by gplbld/solo-sshkey.ps1 (Solo only).  Written 11 Nov 26 for SOLO 55 (owner, 11 Nov 26, "Go with option 1"; Linux mail 2026-11-11T0900).

WHY.  Core gave request 49 to QMRevision (SDRevision) on 15 Oct 26; Solo had given it to the ssh key request on 30 Sep, so a client from the 15 Oct library asking for
the revision reached Solo's key handler.  The ruling: Solo follows Core.  49 is vb.revision in both; the ssh key request is 72 in Solo and Core leaves 72 alone.

WHAT IS HELD (text only; whether the server answers is the verify suite's):
  - every entry of apisrvr's dispatch list has the number its comment gives (a table that drifts by one is the failure this file exists for);
  - 49 is vb.revision, whose handler is `response = system(1012)`;
  - Solo: 72 is vb.sshkey, 50 to 69 are Core's handlers in Core's order (12 Nov 26, SOLO 56 group 7) and 70 and 71 vb.illegal.action (group 8),
    SrvrSshKey is 72 in sdclient.h, the BASIC sdclient and scram-probe.py, SrvrRevision is 49 in the first two,
    and the request is not one a session may make before it has logged in;
  - Core: 71 is the last request, 72 is not allocated (the entry after 71 is vb.illegal.action) and the comment on 71 says it is reserved for Solo's ssh key.
"""

import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SD64 = os.path.abspath(os.path.join(HERE, os.pardir))
SOLO = os.path.isfile(os.path.join(HERE, "solo-sshkey.ps1"))
# Requests 50 to 69, the QMClient requests of 15 Oct 26, in SD Core's order (sdclient.h SrvrGetVar to SrvrWriteuSeqKey); Solo has them since SOLO 56 group 7
CORE_50_69 = ["vb.getvar", "vb.system", "vb.trans", "vb.rtrans", "vb.txn", "vb.evaluate", "vb.evalconv", "vb.iconv", "vb.oconv", "vb.iconvs",
              "vb.oconvs", "vb.openseq", "vb.readseq", "vb.readblk", "vb.writeseq", "vb.writeblk", "vb.seek", "vb.weofseq", "vb.writeseqkey",
              "vb.writeuseqkey"]
FILES = {
    "apisrvr": os.path.join(SD64, "sdsys", "gpl.bp", "apisrvr"),
    "sdclient.h": os.path.join(SD64, "gplsrc", "sdclilib", "sdclient.h"),
    "sdclient": os.path.join(SD64, "sdsys", "gpl.bp", "sdclient"),
    "scram-probe.py": os.path.join(HERE, "scram-probe.py"),
}


def table(src):
    """[(action number, handler, number in its comment or None)] from `on action + 1 gosub vb.illegal.action,` to the closing vb.illegal.action."""
    lines = src.splitlines()
    start = next((i for i, s in enumerate(lines) if re.match(r"\s*on action \+ 1 gosub vb\.illegal\.action,", s)), None)
    if start is None:
        return []
    out = []
    n = 0
    for s in lines[start + 1:]:
        m = re.match(r"\s*(vb\.[a-z.]+),?\s*(?:;\*\s*(\d+)\b)?", s)
        if not m:
            break
        n += 1
        out.append((n, m.group(1), int(m.group(2)) if m.group(2) else None))
    return out


def checks(files):
    out = []

    def ck(name, ok, detail=""):
        out.append((name, bool(ok), detail))

    ap = files["apisrvr"]
    t = table(ap)
    ck("A1 the dispatch list is found and has its closing vb.illegal.action", len(t) > 40 and t[-1][1] == "vb.illegal.action", "%d entries" % len(t))
    bad = [(n, h, c) for n, h, c in t if c is not None and c != n]
    ck("A2 every entry that names a number in its comment is at that position", not bad, "wrong: %s" % bad[:5])
    at = {n: h for n, h, c in t}
    ck("A3 request 49 is vb.revision, and its handler is `response = system(1012)`",
       at.get(49) == "vb.revision" and re.search(r"^vb\.revision:\s*\n\s*response = system\(1012\)\s*\n\s*return", ap, re.M) is not None, "49 is %s" % at.get(49))
    if SOLO:
        ck("S1 request 72 is vb.sshkey, with its handler", at.get(72) == "vb.sshkey" and re.search(r"^vb\.sshkey:", ap, re.M) is not None, "72 is %s" % at.get(72))
        # 12 Nov 26 (SOLO 56 group 7): 50 to 69 are Core's handlers, in Core's order; 70 and 71 (file administration) are not in Solo yet
        want = dict(zip(range(50, 72), CORE_50_69 + ["vb.illegal.action", "vb.illegal.action"]))
        ck("S2 requests 50 to 69 are Core's handlers in Core's order, and 70 and 71 are vb.illegal.action (group 8)", all(at.get(i) == want[i] for i in range(50, 72)),
           "%s" % [(i, at.get(i), want[i]) for i in range(50, 72) if at.get(i) != want[i]][:5])
        ck("S3 the ssh key request is in one place only (nothing else is vb.sshkey)", sum(1 for n, h, c in t if h == "vb.sshkey") == 1)
        h = files["sdclient.h"]
        ck("S4 sdclient.h: SrvrRevision 49 and SrvrSshKey 72", re.search(r"#define SrvrRevision\s+49\b", h) is not None and re.search(r"#define SrvrSshKey\s+72\b", h) is not None)
        b = files["sdclient"]
        ck("S5 the BASIC sdclient: SrvrRevision 49 and SrvrSshKey 72", re.search(r"\$define SrvrRevision\s+49\b", b) is not None and re.search(r"\$define SrvrSshKey\s+72\b", b) is not None)
        ck("S6 scram-probe.py sends the ssh key request as 72", re.search(r"^REQ_SSHKEY = 72\b", files["scram-probe.py"], re.M) is not None)
        gate = re.search(r"if action # 24 and action # 25 and action # 47 and action # 48 then", ap)
        ck("S7 only 24, 25, 47 and 48 are admitted before login (72 is not)", gate is not None)
    else:
        ck("C1 request 71 is the last allocated and 72 is not (the entry after 71 is vb.illegal.action)", at.get(71) == "vb.fcontrol" and at.get(72) == "vb.illegal.action" and len(t) == 72,
           "71 is %s, 72 is %s, %d entries" % (at.get(71), at.get(72), len(t)))
        c71 = next((s for s in ap.splitlines() if re.match(r"\s*vb\.fcontrol,", s)), "")
        ck("C2 the comment on 71 says 72 is reserved for Solo's ssh key request", "72 is RESERVED" in c71 and "Solo" in c71, c71.strip()[:120])
        ck("C3 Core has no vb.sshkey", not any(h == "vb.sshkey" for n, h, c in t) and not re.search(r"^vb\.sshkey:", ap, re.M))
    return out


def load():
    files = {}
    for key, path in FILES.items():
        if not SOLO and key != "apisrvr":
            continue
        with open(path, encoding="utf-8", errors="replace") as f:
            files[key] = f.read()
    return files


MUTANTS_SOLO = [
    ("49 is the ssh key again", "apisrvr", "   vb.revision,       ;*  49 ", "   vb.sshkey,         ;*  49 "),
    ("the table drifts by one after 49", "apisrvr", "   vb.getvar,         ;*  50 ", "   vb.getvar,         ;*  51 "),
    ("72 is not the ssh key", "apisrvr", "   vb.sshkey,         ;*  72 ", "   vb.illegal.action, ;*  72 "),
    ("70 is allocated before group 8", "apisrvr", "   vb.illegal.action, ;*  70", "   vb.revision,       ;*  70"),
    ("a Core handler between 50 and 69 is missing", "apisrvr", "   vb.txn,            ;*  54", "   vb.illegal.action, ;*  54"),
    ("the handler is another revision", "apisrvr", "response = system(1012)", "response = system(1013)"),
    ("the header says 49 for the key", "sdclient.h", "#define SrvrSshKey       72", "#define SrvrSshKey       49"),
    ("the BASIC copy says 49 for the key", "sdclient", "$define SrvrSshKey       72", "$define SrvrSshKey       49"),
    ("the probe sends 49", "scram-probe.py", "REQ_SSHKEY = 72", "REQ_SSHKEY = 49"),
    ("72 is admitted before login", "apisrvr", "if action # 24 and action # 25 and action # 47 and action # 48 then", "if action # 24 and action # 25 and action # 47 and action # 48 and action # 72 then"),
]
MUTANTS_CORE = [
    ("49 is not the revision", "apisrvr", "   vb.revision,       ;*  49 ", "   vb.illegal.action, ;*  49 "),
    ("72 is allocated", "apisrvr", "   vb.fcontrol,       ;*  71   FCONTROL(file, key, value) (S.73 item 3).  72 is RESERVED: Solo's ssh-key request (owner 11 Nov 26); Core's next is 73\n   vb.illegal.action",
     "   vb.fcontrol,       ;*  71   FCONTROL(file, key, value) (S.73 item 3).  72 is RESERVED: Solo's ssh-key request (owner 11 Nov 26); Core's next is 73\n   vb.revision"),
    ("the reservation comment is gone", "apisrvr", "72 is RESERVED", "72 is free"),
    ("the table drifts by one", "apisrvr", "   vb.getvar,         ;*  50 ", "   vb.getvar,         ;*  51 "),
]


def selftest():
    files = load()
    base = checks(files)
    if any(not ok for _, ok, _ in base):
        print("selftest: the unmutated source already fails; fix that first")
        return 1
    missed = 0
    muts = MUTANTS_SOLO if SOLO else MUTANTS_CORE
    for name, key, old, new in muts:
        f = dict(files)
        if f[key].count(old) != 1:
            print("  [CANNOT] %-50s the text does not occur exactly once (%d)" % (name, f[key].count(old)))
            missed += 1
            continue
        f[key] = f[key].replace(old, new)
        caught = [n for n, ok, _ in checks(f) if not ok]
        if caught:
            print("  [caught] %-50s by %s" % (name, ", ".join(c.split()[0] for c in caught[:4])))
        else:
            print("  [MISSED] %-50s" % name)
            missed += 1
    print("selftest: %d mutants, %d missed or not applied" % (len(muts), missed))
    return 0 if missed == 0 else 1


def main():
    if "--selftest" in sys.argv:
        return selftest()
    try:
        files = load()
    except OSError as e:
        print("cannot read the source: %s" % e)
        return 2
    res = checks(files)
    failed = 0
    print("test-apirequests-units: this is the %s tree" % ("Solo" if SOLO else "Core"))
    for name, ok, detail in res:
        print("  [%s] %s%s" % ("PASS" if ok else "FAIL", name, "" if ok else "   <- " + detail))
        failed += 0 if ok else 1
    print("test-apirequests-units: %d checks, %d failed" % (len(res), failed))
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
