"""The API port is one fixed number, and every place that names it agrees.

WHY THIS EXISTS.  Owner's ruling, via the Linux session, 1 Oct 2026: "make
ports 4247 and 4249 -- do not allow adjustable ports".  Every full SD Core
product listens on 4247 and both Solos on 4249; 4243 is OpenQM's and
ScarletDME's, 4245 is upstream SD's.  This product is the full Windows one:
4247.

THE NUMBER LIVES IN ONE PLACE AND IS TYPED IN SEVEN.  The C side has
SD_API_PORT in gplsrc/sddefs.h, but the client library (sdclilib.c is built
apart from the server and cannot include it), BASIC's !sdclient, the firewall
script, the listener script, the staged sd.conf and the installer's text each
carry the digits themselves.  A change to one and not the others is the failure
this exists for: a client that defaults to a port nothing listens on, or a
rule that opens a port nobody binds.  It also fails if anything still PASSES
-Port to api-firewall.ps1, which no longer takes one.

APIPORT in sd.conf is an on/off switch now (gplsrc/config.c maps any value above
zero to SD_API_PORT), so the check on config.c is that the mapping is still
there: without it, `APIPORT=5000` would put the listener on 5000 and the port
would be adjustable again.

It is a source check: no SD, no install, no elevation.  The mutants run on
synthetic text, never on a file.

  python gplbld/test-apiport-units.py

Exit 0 all checks passed, 1 a check failed, 2 the tree is not there to read.
"""

import glob
import os
import re
import sys

# THIS PRODUCT.  The Solo tree's copy of this file names 4249.
PRODUCT = "SD Core for Windows"
WANT_PORT = 4247
LEGACY_PORT = 4243   # W1.1-1 and earlier; an upgraded sd.conf still says it

PORTS = {
    "SD Core for Linux": 4247,
    "SD Core for Windows": 4247,
    "SD Core for Linux Solo": 4249,
    "SD Core Solo for Windows": 4249,
}

HERE = os.path.dirname(os.path.abspath(__file__))
TREE = os.path.normpath(os.path.join(HERE, ".."))

failures = 0
passes = 0


def check(label, ok, detail=""):
    global failures, passes
    if ok:
        passes += 1
        print("  [PASS] " + label)
    else:
        failures += 1
        print("  [FAIL] " + label + ("  " + detail if detail else ""))


def read(rel):
    p = os.path.join(TREE, rel)
    if not os.path.isfile(p):
        return None
    with open(p, "rb") as f:
        return f.read().decode("latin-1").replace("\r\n", "\n")


def all_ints(rx, t, flags=0):
    return [int(x) for x in re.findall(rx, t, flags)]


def sddefs_problems(t, want):
    m = re.search(r"^#define\s+SD_API_PORT\s+(\d+)\s*$", t, re.M)
    if not m:
        return ["SD_API_PORT is not defined"]
    if int(m.group(1)) != want:
        return ["SD_API_PORT is %s, want %d" % (m.group(1), want)]
    return []


def config_problems(t):
    ok = re.search(r'"APIPORT=%d",\s*&n\)\s*==\s*1\)\s*\n\s*cfg->api_port\s*=\s*\(n\s*>\s*0\)\s*\?\s*SD_API_PORT\s*:\s*0;', t)
    return [] if ok else ["APIPORT is no longer mapped to 0 or SD_API_PORT, so the port is adjustable"]


def client_c_problems(t, want):
    ports = all_ints(r"if\s*\(port\s*<\s*0\)\s*\n\s*port\s*=\s*(\d+);", t)
    if not ports:
        return ["no `if (port < 0) port = N;` default found in OpenSocket"]
    return ["the client library defaults to %d, want %d" % (p, want) for p in ports if p != want]


def sdclient_problems(t, want):
    ports = all_ints(r"^\s*if port < 0 then port = (\d+)", t, re.M)
    if not ports:
        return ["no `if port < 0 then port = N` default found in !sdclient"]
    return ["!sdclient defaults to %d, want %d" % (p, want) for p in ports if p != want]


def firewall_problems(t, want):
    bad = []
    ports = all_ints(r"^\$Port\s*=\s*(\d+)", t, re.M)
    if not ports:
        bad.append("no `$Port = N` constant found")
    bad += ["api-firewall.ps1 uses port %d, want %d" % (p, want) for p in ports if p != want]
    if re.search(r"\[int\]\s*\$Port", t):
        bad.append("api-firewall.ps1 takes a -Port parameter again")
    return bad


def listener_problems(t, want):
    bad = []
    for name, rx, w in (
        ("$ACTIVE", r"^\$ACTIVE\s*=\s*'APIPORT=(\d+)'", want),
        ("$COMMENTED", r"^\$COMMENTED\s*=\s*'# APIPORT=(\d+)'", want),
        ("$LEGACY_ACTIVE", r"^\$LEGACY_ACTIVE\s*=\s*'APIPORT=(\d+)'", LEGACY_PORT),
        ("$LEGACY_COMMENTED", r"^\$LEGACY_COMMENTED\s*=\s*'# APIPORT=(\d+)'", LEGACY_PORT),
    ):
        got = all_ints(rx, t, re.M)
        if got != [w]:
            bad.append("%s is %s, want [%d]" % (name, got, w))
    return bad


def stage_problems(t, want):
    bad = []
    got = all_ints(r"^APIPORT_LINE\s*=\s*'APIPORT=(\d+)'", t, re.M)
    if got != [want]:
        bad.append("APIPORT_LINE is %s, want [%d]" % (got, want))
    got = all_ints(r"^APIPORT=(\d+)\s*$", t, re.M)
    if got != [want]:
        bad.append("the staged sd.conf's active APIPORT lines are %s, want [%d]" % (got, want))
    got = all_ints(r"^# APIPORT=(\d+)\"\"\"", t, re.M)
    if got != [want]:
        bad.append("the no-listener sd.conf's commented line is %s, want [%d]" % (got, want))
    return bad


def iss_problems(t, want):
    bad = []
    got = all_ints(r'Description: "Provide the SD Core API \(port (\d+)\)"', t)
    if got != [want]:
        bad.append("the API task names port %s, want [%d]" % (got, want))
    got = all_ints(r"CAN now reach the SD Core API \(port (\d+)\)", t)
    if got != [want]:
        bad.append("the open-to-the-network line names port %s, want [%d]" % (got, want))
    return bad


def callers_problems(name, t):
    """A caller that still passes -Port to api-firewall.ps1, which takes none."""
    if re.search(r"api-firewall\.ps1[^\n]*\s-Port\b", t):
        return ["%s still passes -Port to api-firewall.ps1" % name]
    return []


def ports_in(t, rx):
    return all_ints(rx, t)


def help_problems(name, t, want, minimum):
    got = ports_in(t, r"listens on port (\d+)")
    if len(got) < minimum:
        return ["%s names the port %d time(s), want at least %d" % (name, len(got), minimum)]
    return ["%s says %d, want %d" % (name, p, want) for p in got if p != want]


print("test-apiport-units: %s, want port %d" % (PRODUCT, WANT_PORT))
print("test-apiport-units: reading " + TREE)
sddefs = read("gplsrc/sddefs.h")
if sddefs is None:
    print("test-apiport-units: gplsrc/sddefs.h not found - nothing measured.")
    sys.exit(2)

sources = {
    "gplsrc/config.c": read("gplsrc/config.c"),
    "gplsrc/sdclilib/sdclilib.c": read("gplsrc/sdclilib/sdclilib.c"),
    "sdsys/gpl.bp/sdclient": read("sdsys/gpl.bp/sdclient"),
    "gplbld/api-firewall.ps1": read("gplbld/api-firewall.ps1"),
    "gplbld/api-listener.ps1": read("gplbld/api-listener.ps1"),
    "gplbld/stage.py": read("gplbld/stage.py"),
    "gplbld/sd.iss": read("gplbld/sd.iss"),
    "sdsys/messages/10131": read("sdsys/messages/10131"),
    "sdsys/gpl.bp/remoteapi": read("sdsys/gpl.bp/remoteapi"),
}
missing = [k for k, v in sources.items() if v is None]
for k in missing:
    print("    missing: " + k)
check("CONTROL: every source this test reads was found", not missing)
check("CONTROL: the product table has the ruled ports and this product is in it",
      PORTS[PRODUCT] == WANT_PORT and sorted(set(PORTS.values())) == [4247, 4249]
      and LEGACY_PORT not in PORTS.values())

if not missing:
    def run(label, problems):
        check(label, problems == [], "; ".join(problems))

    run("SD_API_PORT is this product's port", sddefs_problems(sddefs, WANT_PORT))
    run("config.c turns any APIPORT above zero into SD_API_PORT", config_problems(sources["gplsrc/config.c"]))
    run("the client library's default is this port", client_c_problems(sources["gplsrc/sdclilib/sdclilib.c"], WANT_PORT))
    run("!sdclient's default is this port", sdclient_problems(sources["sdsys/gpl.bp/sdclient"], WANT_PORT))
    run("api-firewall.ps1 has this port and takes no -Port", firewall_problems(sources["gplbld/api-firewall.ps1"], WANT_PORT))
    run("api-listener.ps1 writes this port and reads the legacy one", listener_problems(sources["gplbld/api-listener.ps1"], WANT_PORT))
    run("stage.py ships APIPORT with this port", stage_problems(sources["gplbld/stage.py"], WANT_PORT))
    run("the installer's text names this port", iss_problems(sources["gplbld/sd.iss"], WANT_PORT))
    run("message 10131 names this port", help_problems("message 10131", sources["sdsys/messages/10131"], WANT_PORT, 2))
    run("REMOTE.API's help names this port", help_problems("remoteapi", sources["sdsys/gpl.bp/remoteapi"], WANT_PORT, 2))

    scripts = sorted(glob.glob(os.path.join(TREE, "gplbld", "*.ps1")) + [os.path.join(TREE, "gplbld", "sd.iss")])
    scripts = [s for s in scripts
               if os.path.basename(s) not in ("api-firewall.ps1",)]
    bad = []
    for s in scripts:
        with open(s, "rb") as f:
            bad += callers_problems(os.path.basename(s), f.read().decode("latin-1"))
    check("CONTROL: %d scripts and the installer were scanned for -Port callers" % len(scripts), len(scripts) > 20)
    check("nothing passes -Port to api-firewall.ps1", bad == [], "; ".join(bad))

# MUTANTS, on synthetic text, each the change this test exists to catch.
check("MUTANT: the client library on the old port is caught",
      client_c_problems("    if (port < 0)\n        port = 4243;\n", WANT_PORT) != [])
check("MUTANT: !sdclient on the old port is caught",
      sdclient_problems("   if port < 0 then port = 4243\n", WANT_PORT) != [])
check("MUTANT: APIPORT stored as written (the port adjustable again) is caught",
      config_problems('else if (sscanf(rec, "APIPORT=%d", &n) == 1)\n        cfg->api_port = n;\n') != [])
check("MUTANT: api-firewall.ps1 with a -Port parameter is caught",
      firewall_problems("param(\n    [int]$Port = 4247,\n)\n$Port = 4247\n", WANT_PORT) != [])
check("MUTANT: api-firewall.ps1 on the old port is caught",
      firewall_problems("$Port = 4243\n", WANT_PORT) != [])
check("MUTANT: a caller passing -Port is caught",
      callers_problems("x.ps1", "& (Join-Path $G 'api-firewall.ps1') -Open -Port $Port\n") != [])
check("MUTANT: the installer's task naming the old port is caught",
      iss_problems('Name: "apiremote"; Description: "Provide the SD Core API (port 4243)"; \\\n', WANT_PORT) != [])
check("MUTANT: a legacy line that no longer reads 4243 is caught",
      listener_problems("$ACTIVE = 'APIPORT=4247'\n$COMMENTED = '# APIPORT=4247'\n"
                        "$LEGACY_ACTIVE = 'APIPORT=4247'\n$LEGACY_COMMENTED = '# APIPORT=4243'\n", WANT_PORT) != [])
check("CONTROL: correct synthetic text passes every extractor",
      client_c_problems("    if (port < 0)\n        port = 4247;\n", WANT_PORT) == []
      and sdclient_problems("   if port < 0 then port = 4247\n", WANT_PORT) == []
      and config_problems('else if (sscanf(rec, "APIPORT=%d", &n) == 1)\n        cfg->api_port = (n > 0) ? SD_API_PORT : 0;\n') == []
      and firewall_problems("$Port = 4247\n", WANT_PORT) == []
      and callers_problems("x.ps1", "& (Join-Path $G 'api-firewall.ps1') -Open\n") == [])

print("")
if passes == 0:
    print("test-apiport-units: VOID - no check ran.")
    sys.exit(2)
if failures:
    print("test-apiport-units: %d passed, %d failed." % (passes, failures))
    sys.exit(1)
print("test-apiport-units: %d passed, 0 failed." % passes)
sys.exit(0)
