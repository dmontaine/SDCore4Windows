"""test-apilocal-units.py - RELEASE_1.1 317: remote.api local means a listener on 127.0.0.1 only, as SD Core for Linux's LOCAL.

WHY IT EXISTS.  VM sit3 step 10c (15 Nov 2026): with the API LOCAL and no allow rule of SD's (a reinstall that kept sd.conf),
sd -restart made Windows ask whether to let sdwind through - sdwind listened on every interface and LOCAL was only the firewall.
Allow would open the API behind SD's back; Cancel added Block rules that later beat remote.api on.  A loopback listener draws no
such question.  The chain, read off the source: sd.conf's APILOCAL=1 (config.c) -> the segment (sysseg.c) -> sdwind binds
INADDR_LOOPBACK; api-listener.ps1 -Local writes the line and counts an ON/LOCAL move as a move; REMOTE.API LOCAL passes -Local; the
installer runs -Local before the service starts whenever the API is on and SD's rule is not open.

Free: reads source only.  --selftest makes one mutant per row in memory and the row must go red; no file is written.
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SD64 = os.path.normpath(os.path.join(HERE, ".."))
FILES = {
    "config": os.path.join(SD64, "gplsrc", "config.c"),
    "sysseg": os.path.join(SD64, "gplsrc", "sysseg.c"),
    "sysh": os.path.join(SD64, "gplsrc", "sysseg.h"),
    "sdwind": os.path.join(SD64, "gplsrc", "sdwind.c"),
    "listener": os.path.join(HERE, "api-listener.ps1"),
    "rapi": os.path.join(SD64, "sdsys", "gpl.bp", "remoteapi"),
    "iss": os.path.join(HERE, "sd.iss"),
}


def load():
    t = {}
    for k, p in FILES.items():
        with open(p, encoding="latin-1") as f:
            t[k] = f.read().replace("\r\n", "\n")
    return t


def block(text, head, end):
    i = text.find(head)
    if i < 0:
        return ""
    j = text.find(end, i + len(head))
    return text[i:j] if j >= 0 else text[i:]


def checks(t):
    rows = []
    rows.append(("L1", "config.c reads APILOCAL=<n> as a switch (any non-zero is on) into api_local, and the segment carries it after api_port",
                 'else if (sscanf(rec, "APILOCAL=%d", &n) == 1)\n        cfg->api_local = (n != 0);' in t["config"]
                 and "sysseg->api_local = cfg->api_local;" in t["sysseg"]
                 and re.search(r"int16_t api_port;[^\n]*\n\s*int16_t api_local;", t["sysh"]) is not None))
    oal = block(t["sdwind"], "static int open_api_listener(int port, bool local_only) {", "\n}\n")
    rows.append(("L2", "sdwind binds INADDR_LOOPBACK when local, INADDR_ANY otherwise, says which in its log line, and is given the segment's api_local",
                 "addr.sin_addr.s_addr = htonl(local_only ? INADDR_LOOPBACK : INADDR_ANY);" in oal
                 and '"API listener on 127.0.0.1 only (APILOCAL), port %d"' in oal
                 and "api_listener = open_api_listener((int)sysseg->api_port, sysseg->api_local != 0);" in t["sdwind"]))
    li = t["listener"]
    rows.append(("L3", "api-listener.ps1 -Local is ON plus an active APILOCAL=1; -On comments every active one out; 'already' only when the bind "
                 "matches too (so an ON/LOCAL move is reported as a move, exit 0, and REMOTE.API offers the restart); the bind is read back",
                 "[switch]$Local," in li and "$wantOn = [bool]$On -or [bool]$Local" in li and "$wantLocal = [bool]$Local" in li
                 and "-and ($isLocal -eq $wantLocal)) {" in li
                 and "foreach ($li in $localIdx) { $lines[$li] = $LOCAL_COMMENTED }" in li
                 and "if ($wantOn -and (($afterLocal.Count -gt 0) -ne $wantLocal)) {" in li))
    rows.append(("L4", "REMOTE.API LOCAL passes -Local (with the firewall restricted); ON passes -On", re.search(
        r"case action = 'LOCAL'\s*\n\s*want\.port = '-Local'[^\n]*\n\s*want\.fw\s*= '-Restrict'", t["rapi"]) is not None
        and re.search(r"case action = 'ON'\s*\n\s*want\.port = '-On'", t["rapi"]) is not None))
    m = block(t["iss"], "procedure MatchApiListenerToScope;\nvar", "\nend;\n")    # the body, not the forward declaration
    rb = block(t["iss"], "procedure ApiRuleBeforeService;", "\nend;\n")
    rows.append(("L5", "the installer, before the service starts: with the API on and SD's rule not 'open', api-listener.ps1 -Local; 'open' leaves it",
                 "if not ApiConfHasListener then\n    Exit;" in m and "if Scope = 'open' then" in m and "api-listener.ps1') + '\" -Local'" in m
                 and 0 < rb.find("MatchApiListenerToScope;") < rb.find("ApiNoteClear;") < rb.find("EarlyApiFwDone := True;")
                 and "procedure MatchApiListenerToScope; forward;" in t["iss"]))
    return rows


MUTANTS = [
    ("APILOCAL is not read", "L1", "config", 'else if (sscanf(rec, "APILOCAL=%d", &n) == 1)', 'else if (sscanf(rec, "APILOCALX=%d", &n) == 1)'),
    ("the segment does not get it", "L1", "sysseg", "sysseg->api_local = cfg->api_local;", ""),
    ("local still binds every interface", "L2", "sdwind", "htonl(local_only ? INADDR_LOOPBACK : INADDR_ANY)", "htonl(INADDR_ANY)"),
    ("sdwind is not told", "L2", "sdwind", "open_api_listener((int)sysseg->api_port, sysseg->api_local != 0)", "open_api_listener((int)sysseg->api_port, 0)"),
    ("an ON/LOCAL move reads as already", "L3", "listener", " -and ($isLocal -eq $wantLocal)) {", ") {"),
    ("-On keeps APILOCAL", "L3", "listener", "foreach ($li in $localIdx) { $lines[$li] = $LOCAL_COMMENTED }", "Say 'kept'"),
    ("REMOTE.API LOCAL binds every interface again", "L4", "rapi", "want.port = '-Local'", "want.port = '-On'"),
    ("the installer never narrows", "L5", "iss", "  MatchApiListenerToScope;\n", ""),
    ("the installer narrows an open API too", "L5", "iss", "  if Scope = 'open' then", "  if False then"),
]


def run(t, quiet=False):
    bad = 0
    for rid, what, ok in checks(t):
        bad += 0 if ok else 1
        if not quiet:
            print("  [%s] %s %s" % ("PASS" if ok else "FAIL", rid, what))
    return bad


def main():
    try:
        t = load()
    except OSError as e:
        print("NO TREE: %s" % e)
        return 2
    print("test-apilocal-units: %s" % SD64)
    if "--selftest" in sys.argv[1:]:
        if run(t, True):
            print("selftest: the live files already fail; fix that first")
            return 1
        missed = 0
        for name, rid, key, old, new in MUTANTS:
            if t[key].count(old) != 1:
                print("  [CANNOT] %s: the text occurs %d times in %s" % (name, t[key].count(old), key))
                missed += 1
                continue
            m = dict(t)
            m[key] = m[key].replace(old, new)
            failed = [r for r, _, ok in checks(m) if not ok]
            hit = rid in failed
            missed += 0 if hit else 1
            print("  [%s] %s is caught by %s (failed: %s)" % ("pass" if hit else "MISS", name, rid, ", ".join(failed) or "none"))
        print("selftest: %d mutants, %d not caught" % (len(MUTANTS), missed))
        return 1 if missed else 0
    bad = run(t)
    print("test-apilocal-units: %d passed, %d failed" % (len(checks(t)) - bad, bad))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
