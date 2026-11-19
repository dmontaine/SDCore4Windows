#!/usr/bin/env python3
"""test-localsdsys-units.py - the free guard over local SDSYS (RELEASE_1.1 339, Linux S.267): SDSYS reached from this computer by the
Windows users the administrator lists, ssh and the API, both lists empty as delivered.

WHAT IS CHECKED, without SD, an install or elevation:
  C   gplsrc/win32localsdsys.c built with gplbld/verify-localsdsys.c into a scratch folder (UCRT64 gcc): the name rule (Windows', T0745
      Q5) and the list reader on scratch files - absent and empty are list-empty; one "name SID" line; 32 lines; 33 lines, a bad name, a
      SID that is not a local account's form, a SID twice, a byte that is not ASCII, 8 KB, a directory in the file's place are
      list-unsafe; CRLF is read.  The owner and the grants are not checked here (the scratch files are the caller's): the VM witness has them.
  PS  gplbld/sd-sdsyslocal.ps1 on a scratch folder (-Dir): Linux's lines for status, add, add again, remove, a name not listed, clear;
      the 33rd name refused; a bad name refused.  gplbld/sd-sdsysapi.ps1 (-DryRun) refuses an entry that is or holds a loopback address
      and still takes any and other ranges (T0745 Q7).
  TEXT LOGIN asks K$SDSYS.LOCAL only for an SDSYS session that would be refused (not elevated, not a job), before the case; sdsys.local's
      order is Linux's (the kernel, then a phantom or no terminal, then the credential, ONE hidden input, !CRED_VERIFY, the refusal's audit
      line BEFORE the PWDELAY sleep); the grant line and 15177 are in the SDSYS case after kernel(K$ADMINISTRATOR, 1).  APISRVR sends a
      loopback sdsys SCRAM to the local door BEFORE remote.sdsys api's list is read (term 5), asks 'peer' then 'api', refuses with 12992.
      The kernel case reads each list FIRST.  Key 175 in keys.h and int$keys.h.  local.sdsys in voc_template only.  stage.py ships the helper.
  MUTANTS  on copies only (the live files are hashed before and after): each check above is broken once and must go red.

Exit 0 all passed, 1 a check failed, 2 it could not measure (no UCRT64 gcc or no PowerShell: NO TREE).
"""
import hashlib
import os
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
SD64 = os.path.normpath(os.path.join(HERE, ".."))
SRC = os.path.join(SD64, "gplsrc")
BP = os.path.join(SD64, "sdsys", "gpl.bp")
GCC = os.environ.get("SD_UCRT_GCC", r"C:\msys64\ucrt64\bin\gcc.exe")
PWSH = shutil.which("powershell") or shutil.which("powershell.exe")

passed = failed = 0


def row(ok, text, detail=""):
    global passed, failed
    if ok:
        passed += 1
        print("  [PASS] " + text)
    else:
        failed += 1
        print("  [FAIL] " + text + (("   <- " + detail) if detail else ""))


def read(p):
    with open(p, "r", encoding="latin-1", newline="") as f:
        return f.read().replace("\r\n", "\n")


def sha(p):
    with open(p, "rb") as f:
        return hashlib.sha256(f.read()).hexdigest()


if not os.path.isfile(GCC) or PWSH is None:
    print("test-localsdsys-units: NO TREE - needs the UCRT64 gcc (%s) and PowerShell" % GCC)
    sys.exit(2)

LIVE = [os.path.join(SRC, "win32localsdsys.c"), os.path.join(BP, "login"), os.path.join(BP, "apisrvr"),
        os.path.join(SRC, "op_kernel.c"), os.path.join(HERE, "sd-sdsyslocal.ps1"), os.path.join(HERE, "sd-sdsysapi.ps1")]
before = {p: sha(p) for p in LIVE}
tmp = tempfile.mkdtemp(prefix="localsdsys-")


def build(csrc, out):
    env = dict(os.environ)
    env["PATH"] = os.path.dirname(GCC) + os.pathsep + env.get("PATH", "")
    r = subprocess.run([GCC, "-std=gnu17", "-O1", "-I" + SRC, os.path.join(HERE, "verify-localsdsys.c"), csrc, "-o", out,
                        "-ladvapi32", "-lsecur32", "-luserenv", "-lnetapi32", "-liphlpapi", "-lwevtapi"],
                       capture_output=True, text=True, env=env)
    return r.returncode == 0, r.stderr[-600:]


def run(exe, *args):
    r = subprocess.run([exe] + list(args), capture_output=True, text=True)
    return r.stdout.strip()


# ------------------------------------------------------------------ fixtures
FIX = os.path.join(tmp, "sd-tls")
os.makedirs(FIX)
SID = "S-1-5-21-1111111111-2222222222-3333333333-%d"


def fixture(name, data):
    p = os.path.join(FIX, name)
    if data is None:
        return p
    if data == "DIR":
        os.makedirs(p)
        return p
    with open(p, "wb") as f:
        f.write(data)
    return p


FIXES = [
    ("absent", None, "0 list-empty"),
    ("empty", b"", "0 list-empty"),
    ("one", (b"fred " + (SID % 1001).encode() + b"\n"), "1 -"),
    ("crlf", (b"fred " + (SID % 1001).encode() + b"\r\nbob " + (SID % 1002).encode() + b"\r\n"), "2 -"),
    ("thirtytwo", b"".join((b"u%d " % i) + (SID % (1000 + i)).encode() + b"\n" for i in range(32)), "32 -"),
    ("thirtythree", b"".join((b"u%d " % i) + (SID % (1000 + i)).encode() + b"\n" for i in range(33)), "-1 list-unsafe"),
    ("badname", (b"b@d " + (SID % 1001).encode() + b"\n"), "-1 list-unsafe"),
    ("badsid", b"fred S-1-5-18\n", "-1 list-unsafe"),
    ("twice", (b"fred " + (SID % 1001).encode() + b"\nbob " + (SID % 1001).encode() + b"\n"), "-1 list-unsafe"),
    ("nonascii", (b"fr\xe9d " + (SID % 1001).encode() + b"\n"), "-1 list-unsafe"),
    ("big", (b"fred " + (SID % 1001).encode() + b"\n") + b"\n" * 8192, "-1 list-unsafe"),
    ("adir", "DIR", "-1 list-unsafe"),
]
for nm, data, _ in FIXES:
    fixture(nm, data)

NAMES = [("fred", "ok"), ("Fred.Smith", "ok"), ("o'neil", "ok"), ("a" * 20, "ok"), ("a" * 21, "bad"), ("", "bad"), ("b@d", "bad"),
         ("two words", "bad"), ("back\\slash", "bad"), ("...", "bad"), ("semi;colon", "bad")]


def c_rows(exe, tag=""):
    res = {}
    for nm, _, want in FIXES:
        out = run(exe, "read", os.path.join(FIX, nm)).split("\n")[0]
        res[nm] = out
        if not tag:
            row(out == want, "C read %s -> %s" % (nm, want), out)
    for nm, want in NAMES:
        out = run(exe, "name", nm)
        res["name:" + nm] = out
        if not tag:
            row(out == want, "C name %r -> %s" % (nm, want), out)
    return res


print("== C (win32localsdsys.c through verify-localsdsys.c, UCRT64)")
exe = os.path.join(tmp, "verify-localsdsys.exe")
ok, err = build(os.path.join(SRC, "win32localsdsys.c"), exe)
row(ok, "verify-localsdsys builds with win32localsdsys.c", err)
live_c = c_rows(exe) if ok else {}

# ------------------------------------------------------------------ PowerShell helpers
print("== sd-sdsyslocal.ps1 and sd-sdsysapi.ps1 on scratch folders")


def ps(script, *args):
    r = subprocess.run([PWSH, "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", os.path.join(HERE, script)] + list(args),
                       capture_output=True, text=True)
    return r.returncode, r.stdout.strip()


HD = os.path.join(tmp, "helper")
os.makedirs(HD)
steps = [
    (["-List", "ssh", "-Action", "status"], 0, "sdsys local ssh: none listed"),
    (["-List", "ssh", "-Action", "add", "-Name", "fred=" + SID % 1001], 0, "sd-sdsyslocal: sdsys local ssh: added fred; listed now: fred"),
    (["-List", "ssh", "-Action", "add", "-Name", "fred=" + SID % 1001], 0, "sd-sdsyslocal: sdsys local ssh: fred is listed already; nothing was changed"),
    (["-List", "ssh", "-Action", "add", "-Name", "b@d=" + SID % 1009], 1, "sd-sdsyslocal: 'b@d' is not a Windows user name (it holds the character @); nothing was changed"),
    (["-List", "ssh", "-Action", "status"], 0, "sdsys local ssh: listed fred"),
    (["-List", "ssh", "-Action", "remove", "-Name", "bob"], 0, "sd-sdsyslocal: sdsys local ssh: bob is not listed; nothing was changed"),
    (["-List", "ssh", "-Action", "remove", "-Name", "FRED"], 0, "sd-sdsyslocal: sdsys local ssh: removed fred; listed now: none"),
    (["-List", "ssh", "-Action", "clear"], 0, "sd-sdsyslocal: sdsys local ssh: none listed already; nothing was changed"),
]
for args, code, want in steps:
    rc, out = ps("sd-sdsyslocal.ps1", *(args + ["-Dir", HD]))
    row(rc == code and out == want, "helper %s -> %s" % (" ".join(args[:4]), want), "%d %s" % (rc, out))
with open(os.path.join(HD, "sdsys-local-api"), "wb") as f:
    f.write(b"".join((b"u%d " % i) + (SID % (2000 + i)).encode() + b"\n" for i in range(32)))
rc, out = ps("sd-sdsyslocal.ps1", "-List", "api", "-Action", "add", "-Name", "x33=" + SID % 3000, "-Dir", HD)
row(rc == 1 and "the api list holds 32 names already, the most it takes" in out, "helper refuses a 33rd name", "%d %s" % (rc, out))
rc, out = ps("sd-sdsyslocal.ps1", "-List", "api", "-Action", "clear", "-Dir", HD)
row(rc == 0 and out == "sd-sdsyslocal: sdsys local api: cleared, none listed" and not os.path.exists(os.path.join(HD, "sdsys-local-api")),
    "helper clear removes the file", out)

AD = os.path.join(tmp, "api")
os.makedirs(AD)
for e, refused in (("127.0.0.1", True), ("0.0.0.0/1", True), ("::1", True), ("::ffff:127.0.0.1", True), ("10.0.0.0/8", False),
                   ("128.0.0.0/1", False), ("any", False)):
    rc, out = ps("sd-sdsysapi.ps1", "-Action", "on", "-Entries", e, "-Dir", AD, "-DryRun")
    if refused:
        row(rc == 1 and "a loopback address is this computer, which only local.sdsys api lists: " + e in out, "sd-sdsysapi refuses %s" % e, out)
    else:
        row(rc == 0 and "would write" in out, "sd-sdsysapi still takes %s" % e, out)

# ------------------------------------------------------------------ text
print("== text")


def block(t, label):
    i = t.find("\n" + label + ":\n")
    if i < 0:
        return ""
    j = t.find("\n   return\n", i)
    return t[i:j + 11] if j > 0 else t[i:]


def text_problems(login, apisrvr, opk, keys, ikeys):
    p = []
    lsd = block(login, "sdsys.local")
    i_k = lsd.find("kernel(K$SDSYS.LOCAL, 0)")
    i_ph = lsd.find("if is.phantom or kernel(K$TTY, 0) = '' then")
    i_cr = lsd.find("lsd.cred.rec<CRED$VERSION> = SCRAM$CRED.VERSION")
    i_in = lsd.find("input lsd.pw hidden")
    i_v = lsd.find("call !CRED_VERIFY('sdsys', lsd.pw, lsd.ok)")
    i_au = lsd.find("'elevation refused reason=sdsys local ssh wrong password user='")
    i_sl = lsd.find("if lsd.delay > 0 then sleep lsd.delay")
    if not (0 < i_k < i_ph < i_cr < i_in < i_v < i_au < i_sl):
        p.append("sdsys.local is not in Linux's order (kernel, phantom/terminal, credential, one hidden input, verify, audit, then sleep)")
    if lsd.count("input ") != 1 or "loop" in lsd.replace("loop\n         display remove", ""):
        p.append("sdsys.local asks more than once")
    if "kernel(K$ADMINISTRATOR, 1)" in lsd:
        p.append("sdsys.local grants by itself (the SDSYS case grants)")
    call = login.find("if upcase(@logname) = 'SDSYS' and not(kernel(K$ADMINISTRATOR, -1)) and job.name = '' then\n      gosub sdsys.local")
    case = login.find("case upcase(@logname) = 'SDSYS' and (kernel(K$ADMINISTRATOR, -1) or job.name # '' or lsd.state = 'granted')")
    if not (0 < call < case):
        p.append("LOGIN does not ask sdsys.local before the SDSYS case, or the case does not take a granted one")
    g = login.find("admin.granted = kernel(K$ADMINISTRATOR, 1)")
    ga = login.find("'elevation granted reason=sdsys local ssh user=' : lsd.user")
    gn = login.find("sysmsg(15177, lsd.user)")
    if not (0 < g < ga < gn):
        p.append("the grant, its audit line and 15177 are not in that order")
    if "audit.reason = 'SDSYS requires an elevated session' : lsd.why" not in login:
        p.append("the old refusal does not carry the reason word")
    # 18 Nov 26 (RELEASE_1.1 344, Linux S.264): the condition also takes a peer at one of this machine's own addresses (test-ownaddr-units A1)
    i_loc = apisrvr.find("if downcase(scram.user) = 'sdsys' and (field(api.loop, '.', 1) = '127' or api.loop = '::1' or api.own.addr) then")
    i_rem = apisrvr.find("gosub read.sdsys.api", i_loc if i_loc > 0 else 0)
    i_pe = apisrvr.find("kernel(K$SDSYS.LOCAL, 'peer')", i_loc if i_loc > 0 else 0)
    i_api = apisrvr.find("kernel(K$SDSYS.LOCAL, 'api' : @fm :", i_loc if i_loc > 0 else 0)
    if not (0 < i_loc < i_pe < i_api < i_rem) or "abort.message = sysmsg(12992)" not in apisrvr[i_loc:i_rem]:
        p.append("APISRVR does not send a loopback sdsys login to the local door before remote.sdsys api's list")
    case = opk[opk.find("case K_SDSYS_LOCAL:"):]
    case = case[:case.find("} break;")]
    if not (0 < case.find("sdl_read(lp, 1, &sl, &sd_local_why) <= 0") < case.find("sdl_ssh_self(")):
        p.append("key 175 does not read the ssh list first")
    a = case.find("(strncmp(arg, \"api\", 3) == 0)")
    if not (0 < a < case.find("sdl_read(lp, 1, &sl, &sd_local_why) <= 0", a) < case.find("sdl_peer_sid()[0] == '\\0'", a)):
        p.append("key 175 'api' does not read the API list first")
    if not re.search(r"#define K_SDSYS_LOCAL\s+175\b", keys) or not re.search(r"\$define K\$SDSYS\.LOCAL\s+175\b", ikeys):
        p.append("key 175 is not the same in keys.h and int$keys.h")
    return p


login = read(os.path.join(BP, "login"))
apisrvr = read(os.path.join(BP, "apisrvr"))
opk = read(os.path.join(SRC, "op_kernel.c"))
keys = read(os.path.join(SRC, "keys.h"))
ikeys = read(os.path.join(BP, "int$keys.h"))
tp = text_problems(login, apisrvr, opk, keys, ikeys)
row(not tp, "LOGIN, APISRVR and key 175 in the template's order (sdsys.local, the local door, lists read first)", "; ".join(tp))
row(os.path.isfile(os.path.join(SD64, "sdsys", "voc_template", "local.sdsys")) and not os.path.exists(os.path.join(SD64, "sdsys", "newvoc", "local.sdsys")),
    "local.sdsys is SDSYS's verb only (voc_template, not newvoc)")
row("'sd-sdsyslocal.ps1'," in read(os.path.join(HERE, "stage.py")), "stage.py ships sd-sdsyslocal.ps1")
row(all(os.path.isfile(os.path.join(SD64, "sdsys", "messages", str(m))) for m in list(range(15175, 15185)) + [12992]),
    "messages 15175-15184 and 12992 exist")
row("sdl_peer_record(" in read(os.path.join(SRC, "linuxio.c")), "the API front records the loopback peer (linuxio.c)")

# ------------------------------------------------------------------ mutants
print("== mutants (copies only)")
MUT = [
    ("the phantom test after the credential", "login",
     "   if is.phantom or kernel(K$TTY, 0) = '' then\n      lsd.why = ' why=no-terminal'\n      return\n   end\n\n", ""),
    ("the audit line after the sleep", "login",
     "      lsd.delay = config('PWDELAY')\n      if lsd.delay > 0 then sleep lsd.delay\n", ""),
    ("the case grants without the door's answer", "login", " or lsd.state = 'granted')", " or 1)"),
    ("the loopback door removed", "apisrvr", "and (field(api.loop, '.', 1) = '127' or api.loop = '::1' or api.own.addr) then", "and 0 then"),
    ("key 175 asks the ssh door before the list", "opk", "else if (sdl_read(lp, 1, &sl, &sd_local_why) <= 0)\n          ;   /* list-empty or list-unsafe */\n        else if ((sdsyslocal_claim", "else if ((sdsyslocal_claim"),
]
for name, which, old, new in MUT:
    src = {"login": login, "apisrvr": apisrvr, "opk": opk}
    if old not in src[which]:
        row(False, "MUTANT control: the text the mutant changes is in the live file (%s)" % name)
        continue
    src[which] = src[which].replace(old, new, 1)
    row(len(text_problems(src["login"], src["apisrvr"], src["opk"], keys, ikeys)) > 0, "MUTANT: %s is caught" % name)

if live_c:
    mc = read(os.path.join(SRC, "win32localsdsys.c"))
    old = "      if (strcmp(out->sid[j], sp + 1) == 0)\n        return -1;\n"
    if old in mc:
        mp = os.path.join(tmp, "mutant.c")
        with open(mp, "w", encoding="latin-1", newline="\n") as f:
            f.write(mc.replace(old, "", 1))
        mexe = os.path.join(tmp, "mutant.exe")
        okm, errm = build(mp, mexe)
        res = c_rows(mexe, "m") if okm else {}
        row(okm and res.get("twice") != live_c.get("twice"), "MUTANT: a list that holds a SID twice, read as good, is caught", errm)
    else:
        row(False, "MUTANT control: the SID-twice test is in the live win32localsdsys.c")
    old = "    if (strchr(\"\\\"/\\\\[]:;|=,+*?<>@\", c) != NULL)\n      return 0;\n"
    if old in mc:
        mp = os.path.join(tmp, "mutant2.c")
        with open(mp, "w", encoding="latin-1", newline="\n") as f:
            f.write(mc.replace(old, "", 1))
        mexe = os.path.join(tmp, "mutant2.exe")
        okm, errm = build(mp, mexe)
        res = c_rows(mexe, "m") if okm else {}
        row(okm and res.get("name:b@d") == "ok", "MUTANT: a name rule that takes Windows' forbidden characters is caught", errm)
    else:
        row(False, "MUTANT control: the forbidden-character test is in the live win32localsdsys.c")

after = {p: sha(p) for p in LIVE}
row(before == after, "the live files are unchanged by the run (SHA-256 before and after)")
shutil.rmtree(tmp, ignore_errors=True)
print("test-localsdsys-units: %d passed, %d failed" % (passed, failed))
sys.exit(0 if failed == 0 else 1)
