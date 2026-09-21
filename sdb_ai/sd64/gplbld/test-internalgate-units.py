#!/usr/bin/env python3
"""test-internalgate-units.py - the free guard over the "sd -internal" door.
RELEASE_1.1_FIXES.md 82 (D2').  No SD, install, elevation or cycle.

WHAT IS GUARDED.  LOGIN (sdsys/gpl.bp/login, internal.gate) admits an "sd -internal"
session only against a one-shot marker file, $internal, in the SDSYS directory, and
deletes it on admission.  Whoever legitimately starts an internal session writes one first.
That is TWO halves in DIFFERENT languages and files - the gate in BASIC, the writers in
PowerShell and Python - and either half works alone while both are wrong alone:

  * a session start with no writer is REFUSED by the gate, and the only place that shows
    is an install or a cycle: a missing writer in upgrade-voc.ps1 fails inside the
    installer, hidden, at the customer;
  * a gate that stopped consuming the marker (or decided before deleting it) leaves the
    door open for every later session, and nothing else would notice, because every
    legitimate caller still succeeds.

BASIC cannot be executed in a session, so the gate is checked the way
test-pwcomplex-units.py checks pw_complex: by reading what the file says, in ORDER,
which is the part that is load-bearing.  ***THE LIMIT IS STATED, NOT GLOSSED:*** this proves
the gate's shape and its ties to the writers, NOT that it admits a real session - that is
verify-internalgate.ps1, an elevated run against an installed system.

THE PARTITION.  It walks gplbld for every quoted "-internal" token outside comments; each
file must be a declared WRITER (and then must actually write the marker), or a declared
non-writer with its reason.  An undeclared file is a FAIL, so a NEW internal session
cannot appear without somebody deciding who writes its marker.

Exit 0 all checks passed, 1 a check failed, 2 it could not measure.
"""
import os
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
SD64 = os.path.dirname(HERE)
LOGIN = os.path.join(SD64, "sdsys", "gpl.bp", "login")

passed = 0
failed = 0


def row(ok, text, detail=""):
    global passed, failed
    if ok:
        passed += 1
        print("[PASS] " + text)
    else:
        failed += 1
        print("[FAIL] " + text + (("   <- " + detail) if detail else ""))


def read(path):
    with open(path, "r", encoding="utf-8", errors="replace") as fh:
        return fh.read()


def code_lines(text):
    """Non-comment lines of BASIC: a leading * is a comment."""
    out = []
    for ln in text.splitlines():
        if ln.lstrip().startswith("*"):
            continue
        out.append(ln)
    return out


# ---------------------------------------------------------------------------
# 1. the gate, as login says it
# ---------------------------------------------------------------------------
def gate_problems(login_text):
    """Every way the gate can be wrong that is visible in the text.  Returns a list."""
    p = []
    lines = code_lines(login_text)
    joined = "\n".join(lines)

    # the subroutine: from its label to the next 'return'
    m = re.search(r"(?m)^internal\.gate:\s*$(.*?)^\s+return\s*$", joined, re.S)
    if not m:
        return ["no 'internal.gate:' subroutine ending in a return"]
    body = m.group(1)

    # the call site: inside the K$INTERNAL branch, before its 'end else', and followed by a refusal
    cs = re.search(r"kernel\(K\$INTERNAL,-1\)\s+then\b(.*?)\n\s*end else", joined, re.S)
    if not cs:
        p.append("no 'if kernel(K$INTERNAL,-1) then ... end else' branch")
    else:
        branch = cs.group(1)
        if branch.count("gosub internal.gate") != 1:
            p.append("the K$INTERNAL branch does not call 'gosub internal.gate' exactly once")
        elif not re.search(r"gosub internal\.gate\s*\n\s*if not\(gate\.ok\) then goto terminate\.connection", branch):
            p.append("the call is not followed by 'if not(gate.ok) then goto terminate.connection'")

    # gate.ok is initialised near the top, BEFORE it is read (BCOMP's 'is not assigned a value')
    i_init = joined.find("gate.ok = @true")
    i_call = joined.find("gosub internal.gate")
    if i_init < 0 or i_call < 0 or i_init > i_call:
        p.append("gate.ok is not assigned before the call site reads it")

    # the marker path and the expiry
    if not re.search(r"gate\.marker = @sdsys : @ds : '\$internal'", body):
        p.append("the marker is not @sdsys:@ds:'$internal'")
    if not re.search(r"gate\.expiry = 600\b", body):
        p.append("the expiry is not 600 seconds")

    # THE LOAD-BEARING ORDER: the marker is deleted BEFORE the decision, so no path leaves it open
    i_del = body.find("ospath(gate.marker, OS$DELETE)")
    i_ok = body.find("gate.ok = @true")
    i_exp = body.find("gate.age > gate.expiry")
    if i_del < 0:
        p.append("the marker is never deleted (OS$DELETE) - the door stays open after one use")
    if i_ok < 0:
        p.append("nothing ever sets gate.ok true")
    if i_del >= 0 and i_ok >= 0 and i_del > i_ok:
        p.append("the marker is deleted AFTER gate.ok is set true - a path can admit without consuming")
    if i_del >= 0 and i_exp >= 0 and i_del > i_exp:
        p.append("the marker is deleted AFTER the expiry test - an expired marker would survive")
    # a failed delete must refuse
    if "could not be consumed" not in body:
        p.append("a marker that cannot be deleted is not refused")

    # ***THE AGE MUST BE MEASURABLE.*** OPENSEQ on a path that does not exist takes its ELSE clause
    # and leaves the file variable unopened (op_seqio.c: "Does not exist, take ELSE clause"); only
    # CREATE makes the file.  The first version of the gate opened the scratch file with OPENSEQ
    # alone, never created it, left the age at -1, and treated EVERY marker as fresh - so an
    # 11-minute-old marker was admitted (b202, verify-internalgate leg D) and nothing else could
    # have said so, because the fallback for "age unknown" is deliberately lenient.
    if not re.search(r"openseq gate\.stamp to gate\.sf else\s+create gate\.sf else", body):
        p.append("the age scratch file is opened but never CREATEd (OPENSEQ does not create; the age stays -1)")
    i_stale = body.find("ospath(gate.stamp, OS$DELETE)")
    i_open = body.find("openseq gate.stamp")
    if i_stale < 0 or i_open < 0 or i_stale > i_open:
        p.append("a stale scratch file is not deleted BEFORE it is opened (an old one would read as 'now')")
    if "gate.age = gate.now - gate.mtime" not in body:
        p.append("the age is never computed from the two mtimes")

    # every use is audited: admission by the gate, refusal by terminate.connection with a reason
    for reason in ("no internal marker", "the internal marker had expired"):
        if ("audit.reason = '" + reason + "'") not in body:
            p.append("no audit reason: " + reason)
    if "'INTERNAL SESSION ADMITTED account='" not in body:
        p.append("an admission is not written to the audit trail")
    if "gate.writer[1, 80]" not in body:
        p.append("the writer text is not capped (the file is writable by more than the installer)")
    # R4: an admission is SAID ON THE SCREEN as well as audited, so it lands in every transcript
    if not re.search(r"if gate\.ok then.*?display sysmsg\(12000, gate\.writer\)", body, re.S):
        p.append("an admission is not announced on the screen (display sysmsg(12000, gate.writer))")
    # 20 Sep 26 - THE ONE EXCEPTION TO THAT ANNOUNCEMENT, AND IT MUST STAY ONE.  The owner had the
    # installer's finishing window stop printing "Internal session admitted (opened by finish-install
    # ...)".  R4 - the rule the Linux agent asked both ports to share - still holds for every other
    # use (the installer's hidden steps, the bootstrap, the verifiers, the seat), so the exception
    # needs BOTH halves: the writer is finish-install AND the session was started -QUIET.  A blanket
    # "-QUIET silences it" would let any -QUIET caller hide the notice, and a writer-only rule would
    # hide it from a person who did not ask for quiet.  The audit line above is untouched either way.
    if not re.search(r"if gate\.writer\[1, 14\] = 'finish-install' then\s+"
                     r"if bitand\(kernel\(K\$COMMAND\.OPTIONS, 0\), CMD\.QUIET\) then announce = @false", body):
        p.append("the announcement exception is missing, or is not limited to finish-install AND -QUIET")
    if not re.search(r"if announce then display sysmsg\(12000, gate\.writer\)", body):
        p.append("the announcement is not conditional on the 'announce' decision")
    if not re.search(r"announce = @true\s+if gate\.writer", body):
        p.append("the announcement does not default to ON (announce = @true before the exception)")
    return p


def login_text_or_exit():
    if not os.path.isfile(LOGIN):
        print("REFUSED: %s is not there" % LOGIN)
        sys.exit(2)
    return read(LOGIN)


print("test-internalgate-units: the 'sd -internal' door, both halves")
print("  login : " + LOGIN)
login = login_text_or_exit()

print("== 1. the gate, as login says it")
gp = gate_problems(login)
row(not gp, "the live gate has every property the partition below depends on", "; ".join(gp))

# mutants on TEXT: the live file is only ever read
mut = login.replace("void ospath(gate.marker, OS$DELETE)", "null")
row(any("never deleted" in x for x in gate_problems(mut)),
    "MUTANT: a gate that never deletes the marker is caught")
i_d = login.find("void ospath(gate.marker, OS$DELETE)")
i_ok = login.find("gate.ok = @true", login.find("internal.gate:"))
row(i_d > 0 and i_ok > 0, "CONTROL: both statements the reorder mutant moves were found in the live file")
if i_d > 0 and i_ok > 0:
    # move the delete to the end of the subroutine, after the decision
    m2 = login.replace("      void ospath(gate.marker, OS$DELETE)\n", "", 1)
    m2 = m2.replace("   audit.account = initial.account\n   if gate.ok then",
                    "   void ospath(gate.marker, OS$DELETE)\n   audit.account = initial.account\n   if gate.ok then", 1)
    row(any("AFTER" in x for x in gate_problems(m2)), "MUTANT: a delete moved after the decision is caught")
mut3 = login.replace("gosub internal.gate\n            if not(gate.ok) then goto terminate.connection", "gosub internal.gate")
row(any("not followed by" in x for x in gate_problems(mut3)), "MUTANT: a call site that ignores gate.ok is caught")
msg = os.path.join(SD64, "sdsys", "messages", "12000")
msg_text = read(msg) if os.path.isfile(msg) else ""
row("%1" in msg_text and msg_text.strip() != "",
    "message 12000 exists and takes the writer as %1 (first of the Windows block, agreed with the Linux agent)", msg)
row(not os.path.isfile(os.path.join(SD64, "sdsys", "messages", "10922")),
    "10922 is NOT here: Linux shipped it on 19 Sep as an SDSYS API refusal, and this port's first guess at it was wrong")
mut5 = login.replace("display sysmsg(12000, gate.writer)", "null")
row(any("not announced" in x for x in gate_problems(mut5)), "MUTANT: a gate that stops announcing an admission is caught")
exc_q = "if bitand(kernel(K$COMMAND.OPTIONS, 0), CMD.QUIET) then announce = @false"
exc_w = "if gate.writer[1, 14] = 'finish-install' then"
row(exc_q in login and exc_w in login,
    "CONTROL: both halves the announcement-exception mutants remove were found in the live file")
row(any("limited to finish-install AND -QUIET" in x for x in gate_problems(login.replace(exc_q, "announce = @false"))),
    "MUTANT: an exception that hides the announcement from finish-install WITHOUT -QUIET is caught")
row(any("limited to finish-install AND -QUIET" in x for x in gate_problems(login.replace(exc_w, "if @true then"))),
    "MUTANT: a blanket '-QUIET silences the announcement' (any writer) is caught")
row(any("limited to finish-install AND -QUIET" in x for x in gate_problems(
        login.replace(exc_w, "if gate.writer[1, 1] = 'f' then"))),
    "MUTANT: a widened writer match is caught")
row(any("default to ON" in x for x in gate_problems(login.replace("announce = @true", "announce = @false"))),
    "MUTANT: an announcement that defaults to OFF is caught")
mut6 = login.replace("create gate.sf else gate.sf = ''", "gate.sf = ''")
row(any("never CREATEd" in x for x in gate_problems(mut6)),
    "MUTANT: the age scratch file opened with OPENSEQ and never created (the b202 defect) is caught")
mut4 = login.replace("gate.expiry = 600", "gate.expiry = 0")
row(any("expiry" in x for x in gate_problems(mut4)), "MUTANT: a changed expiry is caught (the writers' docs and the witness assume 600)")

# ---------------------------------------------------------------------------
# 2. the writers: every internal session has one
# ---------------------------------------------------------------------------
print("")
print("== 2. every internal session start is a declared writer that really writes the marker")

WRITERS = {
    "attach-account.ps1": "Set-SdInternalMarker",
    "finish-install.ps1": "Set-SdInternalMarker",
    "upgrade-dicts.ps1": "Set-SdInternalMarker",
    "upgrade-nocase.ps1": "Set-SdInternalMarker",
    "upgrade-voc.ps1": "Set-SdInternalMarker",
    "bootstrap.py": "INTERNAL_MARKER_DIR",
    "sdsys-seat.ps1": "Set-SdInternalMarker",
    "verify-accountrules.ps1": "Set-SdInternalMarker",
    "verify-createfilecase.ps1": "Set-SdInternalMarker",
    "verify-deadlock.ps1": "Set-SdInternalMarker",
    "verify-realupgrade.ps1": "Set-SdInternalMarker",
}
NON_WRITERS = {
    # gplbld/verify-internalgate.ps1 STARTS internal sessions with and WITHOUT a marker on purpose
    # (legs A, C and D measure the refusal), so it controls the marker explicitly, leg by leg.
    "verify-internalgate.ps1": "the witness controls the marker itself; legs A, C, D need it absent",
}
# gplsrc/sd.c is outside gplbld and holds the "-INTERNAL" argument PARSER, not a session start.

TOKEN = re.compile(r"""['"]-internal['"]""", re.I)


def is_comment(path, line):
    s = line.lstrip()
    if path.endswith(".py"):
        return s.startswith("#")
    if path.endswith(".iss"):
        return s.startswith(";") or s.startswith("//")
    return s.startswith("#") or s.startswith("<#")


def session_starters(directory):
    """Files (not test-*) with a quoted -internal token on a non-comment line."""
    found = {}
    for name in sorted(os.listdir(directory)):
        if name.startswith("test-") or not name.endswith((".ps1", ".py", ".iss")):
            continue
        text = read(os.path.join(directory, name))
        n = sum(1 for ln in text.splitlines() if TOKEN.search(ln) and not is_comment(name, ln))
        if n:
            found[name] = (n, text)
    return found


def partition_problems(found):
    p = []
    for name, (n, text) in found.items():
        if name in NON_WRITERS:
            continue
        need = WRITERS.get(name)
        if need is None:
            p.append(name + ": starts an internal session and is not declared (a writer, or a non-writer with a reason)")
        elif need not in text:
            p.append(name + ": is a declared writer but never references " + need)
    for name in WRITERS:
        if name not in found:
            p.append(name + ": declared a writer but no longer starts an internal session (stale declaration)")
    return p


found = session_starters(HERE)
row(len(found) >= 8, "CONTROL: the walk found the internal session starters (%d files)" % len(found),
    "found %d - the token or the directory is wrong, and the partition below would pass on nothing" % len(found))
pp = partition_problems(found)
row(not pp, "every internal session start is a declared writer that references the marker", " | ".join(pp))

# mutants on the FOUND set: a writer with its marker call removed, and an undeclared starter
if "upgrade-voc.ps1" in found:
    n, text = found["upgrade-voc.ps1"]
    bare = dict(found)
    bare["upgrade-voc.ps1"] = (n, text.replace("Set-SdInternalMarker", "Set-SomethingElse"))
    row(any("upgrade-voc.ps1" in x and "never references" in x for x in partition_problems(bare)),
        "MUTANT: a writer whose marker call was removed is caught, by name")
extra = dict(found)
extra["brand-new-step.ps1"] = (1, "Start-Process sd -ArgumentList '-internal'")
row(any("brand-new-step.ps1" in x and "not declared" in x for x in partition_problems(extra)),
    "MUTANT: a NEW internal session with no declaration is caught")
gone = dict(found)
gone.pop("bootstrap.py", None)
row(any("bootstrap.py" in x and "stale" in x for x in partition_problems(gone)),
    "MUTANT: a declaration that no longer matches a session start is caught (stale declaration)")

# the seat's callers: anything using the seat's -Internal switch is covered by the seat's writer
seat_users = []
for name in sorted(os.listdir(HERE)):
    if name.startswith("test-") or not name.endswith(".ps1"):
        continue
    if re.search(r"(Invoke-SdSeatText|Invoke-SdViaSeat|Assert-SdSeat)[^\n]*-Internal", read(os.path.join(HERE, name))):
        seat_users.append(name)
row(len(seat_users) >= 4 and "sdsys-seat.ps1" in WRITERS,
    "the seat's -Internal callers are covered by the seat's own writer (%d scripts)" % len(seat_users),
    ", ".join(seat_users))

# ---------------------------------------------------------------------------
# 3. the contract between the gate and every writer
# ---------------------------------------------------------------------------
print("")
print("== 3. the contract: file name, first line, encoding, and the strings the witness asserts")
marker_ps1 = read(os.path.join(HERE, "internal-marker.ps1"))
bootstrap = read(os.path.join(HERE, "bootstrap.py"))
witness = read(os.path.join(HERE, "verify-internalgate.ps1"))
row("'$internal'" in marker_ps1 and "'$internal'" in bootstrap, "the writers name the file $internal, as LOGIN does")
row("UTF8Encoding($false)" in marker_ps1, "the PowerShell writer is UTF-8 WITHOUT a BOM (LOGIN reads line 1 with READSEQ)")
row("encoding='ascii'" in bootstrap and "pid=%d" in bootstrap, "the Python writer is ASCII and writes 'pid='")
row("pid={1}" in marker_ps1, "the PowerShell writer writes 'pid='")
row(("messages" + chr(92) + "12000") in witness and "ANNOUNCED" in witness,
    "the witness reads message 12000 from the install and scores the announcement (R4)")
for phrase in ("no internal marker", "the internal marker had expired", "INTERNAL SESSION ADMITTED account=SDSYS"):
    row(phrase in witness, "the witness (verify-internalgate.ps1) asserts the exact audit wording: " + phrase)
code_only = "\n".join(ln for ln in witness.splitlines() if not ln.lstrip().startswith("#"))
row(("messages" + chr(92) + "5024") in code_only and "$termText" in code_only and "Connection terminated" not in code_only,
    "the witness reads the refusal text from message 5024 (in its code, not just its comments) rather than typing it")

# the shipped scripts find the helper beside them: it must be staged with them
stage = read(os.path.join(HERE, "stage.py"))
row("'internal-marker.ps1'" in stage, "stage.py ships internal-marker.ps1 beside the scripts that dot-source it")
for name in ("attach-account.ps1", "finish-install.ps1", "upgrade-dicts.ps1", "upgrade-nocase.ps1", "upgrade-voc.ps1"):
    row("internal-marker.ps1" in read(os.path.join(HERE, name)), "%s dot-sources internal-marker.ps1" % name)

# ---------------------------------------------------------------------------
# 4. the PowerShell writer, EXECUTED
# ---------------------------------------------------------------------------
print("")
print("== 4. internal-marker.ps1, executed against a temp directory")
tmp = tempfile.mkdtemp(prefix="intgate-")
try:
    sysdir = os.path.join(tmp, "sdsys")
    os.makedirs(sysdir)
    probe = os.path.join(tmp, "probe.ps1")
    ps = "\n".join([
        "$ErrorActionPreference = 'Stop'",
        ". '" + os.path.join(HERE, "internal-marker.ps1").replace("\\", "/") + "'",
        "$d = '" + sysdir.replace("\\", "/") + "'",
        "$r1 = Set-SdInternalMarker -SdsysDir $d -Writer 'unit-test'",
        "Write-Output ('SET=' + $r1)",
        "Write-Output ('EXISTS=' + (Test-Path -LiteralPath (Join-Path $d '$internal')))",
        "$r2 = Remove-SdInternalMarker -SdsysDir $d",
        "Write-Output ('REMOVED=' + $r2)",
        "Write-Output ('GONE=' + (-not (Test-Path -LiteralPath (Join-Path $d '$internal'))))",
        "Write-Output ('REMOVE-ABSENT=' + (Remove-SdInternalMarker -SdsysDir $d))",
        "Write-Output ('SET-MISSING-DIR=' + (Set-SdInternalMarker -SdsysDir ($d + '-nope') -Writer 'x'))",
        # written again and left, so the bytes can be read from here
        "$null = Set-SdInternalMarker -SdsysDir $d -Writer ('caf' + [char]0x00E9 + ' ' + ('x' * 200))",
        "",
    ])
    with open(probe, "w", encoding="utf-8") as fh:
        fh.write(ps)
    r = subprocess.run(["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", probe],
                       capture_output=True, text=True, timeout=120)
    out = r.stdout
    row(r.returncode == 0, "the probe script ran", (r.stderr or out)[-300:])
    row("SET=True" in out and "EXISTS=True" in out, "Set-SdInternalMarker writes the marker and says so", out)
    row("REMOVED=True" in out and "GONE=True" in out, "Remove-SdInternalMarker removes it and says so", out)
    row("REMOVE-ABSENT=True" in out, "removing an absent marker is not an error", out)
    row("SET-MISSING-DIR=False" in out, "a missing SDSYS directory is a FALSE, not a throw (a caller must be able to refuse)", out)
    mk = os.path.join(sysdir, "$internal")
    if os.path.isfile(mk):
        raw = open(mk, "rb").read()
        row(not raw.startswith(b"\xef\xbb\xbf"), "the marker has NO BOM", repr(raw[:8]))
        row(all(b < 128 for b in raw), "and is pure ASCII - a non-ASCII writer name is replaced, not written", repr(raw[:80]))
        first = raw.decode("ascii", "replace").split("\n")[0]
        row(re.match(r"^caf\? x+ pid=\d+ \d{4}-\d\d-\d\dT", first) is not None or re.match(r"^caf\?", first) is not None,
            "line 1 starts with the sanitised writer name", first[:60])
        row(raw.count(b"\n") == 1 and raw.endswith(b"\n"), "and it is exactly one line", repr(raw[-20:]))
    else:
        row(False, "the long-writer marker was not written", out)
finally:
    shutil.rmtree(tmp, ignore_errors=True)

print("")
if failed == 0 and passed == 0:
    print("REFUSED: no check ran")
    sys.exit(2)
print("test-internalgate-units: %d passed, %d failed" % (passed, failed))
sys.exit(0 if failed == 0 else 1)
