#!/usr/bin/env python3
"""test-install-opengates-units.py - the installer's task "opengates" and attach-account.ps1 -OpenGates (Linux f811e1f, 19 Oct 2026; owner:
"installer asks once; y opens all gates for the installing user's account, default No").

  python gplbld/test-install-opengates-units.py
  python gplbld/test-install-opengates-units.py --selftest

FREE CHECK: no install, no sd, no administrator.  Exit 0 every check passed, 1 a check failed, 2 it could not run.

WHAT IT DOES.  Static rows read sd.iss, attach-account.ps1, modifya and keys.h as text.  The dynamic rows EXTRACT the gate tables and the two
functions (Get-ClosedGates, Open-InstallerGates) from attach-account.ps1, put them in a harness with a stub Invoke-Sd (it records the arguments
and does nothing, like a modify.account that refused everything), a stub Get-LocalGroupMember and a register record the scenario writes, and RUN
them in Windows PowerShell.  The scenarios answer: all open -> all open; a blank field, a missing group, an unreadable record or group, a
mixed-case domain-prefixed member name -> exactly the words to give, and "all open" is ABSENT.  The result is judged on what the register
and the groups HOLD, never on what the stub sd returned (the real sd says nothing useful about a refusal).

THE DEFAULT IS NO.  The task is "unchecked" (a tick, or /TASKS=opengates on a silent run, is the only way it is on); -OpenGates is passed only
under WizardIsTaskSelected('opengates'); an upgrade skips the tasks page, and an existing account (exit 2) is never touched.  The word list is
every word modify.account accepts to turn something on, less the ones that are not gates here: ssh and the API (on by default, 68),
shared-read-on (the default), files-admin-on (the administration group ships off whatever the answer: Linux D4), pins-on and the start words
(the home screen's own, not access gates; Linux's list leaves them out).  A gate added later fails the row that compares the list with
modifya until it is decided here.

NOT MEASURED HERE: that the real modify.account, run as sd -internal at ssPostInstall, accepts each word for the ATTACHed account, and that the
installer page shows.  Those are the next install cycle's.
"""

import os
import re
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
SD64 = os.path.dirname(HERE)
ATTACH = os.path.join(HERE, "attach-account.ps1")
ISS = os.path.join(HERE, "sd.iss")
MODIFYA = os.path.join(SD64, "sdsys", "gpl.bp", "modifya")
KEYS = os.path.join(SD64, "sdsys", "syscom", "keys.h")

# modifya on-words that are NOT access gates for this purpose, and why (see the header)
NOT_GATES = {"SHARED-READ-ON", "FILES-ADMIN-ON", "PINS-ON"}
EXPECT_WORDS = ["both", "sh-on", "os-on", "sd-on", "voc-on", "bp-on", "dict-on", "net-on", "shared-write-on", "files-on", "files-write-on"]
EXPECT_FIELDS = {7: "ACC$SH", 8: "ACC$OS.EXEC", 9: "ACC$SD.ACCOUNTS", 10: "ACC$VOC.EDIT", 11: "ACC$BP.EDIT", 12: "ACC$DICT.EDIT",
                 14: "ACC$SHARED.WRITE", 15: "ACC$NET"}


def read(p):
    with open(p, encoding="utf-8", errors="replace") as f:
        return f.read()


def between(text, a, b):
    i = text.find(a)
    j = text.find(b, i + 1) if i >= 0 else -1
    return text[i:j] if i >= 0 and j > i else ""


def modifya_on_words(src):
    m = re.search(r"word\.arr = convert\(',', @fm, '([^']+)'\)", src)
    return [w for w in (m.group(1).split(",") if m else []) if w.endswith("-ON")]


def keys_numbers(src):
    return {m.group(1): int(m.group(2)) for m in re.finditer(r"\$define (ACC\$[A-Z.]+)\s+(\d+)", src)}


HARNESS_HEAD = r"""
$ErrorActionPreference = 'Stop'
function Say([string] $m) { Write-Output ("SAY: " + $m) }
$script:calls = New-Object System.Collections.ArrayList
function Invoke-Sd { param([string[]] $SdArgs) $null = $script:calls.Add(($SdArgs -join ' ')); return [pscustomobject]@{ Code = 0; Text = '' } }
$script:members = @{}
$script:groupsThrow = $false
function Get-LocalGroupMember {
    param([string] $Group, $ErrorAction)
    if ($script:groupsThrow) { throw 'cannot read the group' }
    $n = $script:members[$Group]
    if ($null -eq $n) { throw 'no such group' }
    foreach ($x in $n) { [pscustomobject]@{ Name = $x } }
}
"""


def lines_for(fields):
    """A register record: one line per field, 1..16; fields maps number -> text."""
    return "\r\n".join(fields.get(n, "x%d" % n) for n in range(1, 17)) + "\r\n"


def scenario(name, record_fields, members, groups_throw=False, record_missing=False):
    rec = "$record = " + ("'C:/no/such/record'" if record_missing else "'%RECORD%'")
    return (name, record_fields, members, groups_throw, rec)


ALL_YES = {n: "yes" for n in (7, 8, 9, 10, 11, 12, 14, 15)}
BOTH_GROUPS = {"sdssh": ["PC\\Don"], "sdapi": ["PC\\Don"], "sdfiles": ["PC\\Don"], "sdfileswrite": ["PC\\Don"]}
SCENARIOS = [
    scenario("all open (member names carry a domain and a different case)", ALL_YES, BOTH_GROUPS),
    scenario("sd-on blank", {**ALL_YES, 9: ""}, BOTH_GROUPS),
    scenario("os-on is no", {**ALL_YES, 8: "no"}, BOTH_GROUPS),
    scenario("shared-write-on blank", {**ALL_YES, 14: ""}, BOTH_GROUPS),
    scenario("not in sdfileswrite", ALL_YES, {**BOTH_GROUPS, "sdfileswrite": ["PC\\Ann"]}),
    scenario("not in sdfiles", ALL_YES, {**BOTH_GROUPS, "sdfiles": []}),
    scenario("not in sdapi (both is half done)", ALL_YES, {**BOTH_GROUPS, "sdapi": []}),
    scenario("in neither route group (both is named once)", ALL_YES, {**BOTH_GROUPS, "sdapi": [], "sdssh": []}),
    scenario("groups unreadable", ALL_YES, {}, groups_throw=True),
    scenario("record unreadable", ALL_YES, BOTH_GROUPS, record_missing=True),
]
EXPECT = {
    "all open (member names carry a domain and a different case)": (True, []),
    "sd-on blank": (False, ["sd-on"]),
    "os-on is no": (False, ["os-on"]),
    "shared-write-on blank": (False, ["shared-write-on"]),
    "not in sdfileswrite": (False, ["files-write-on"]),
    "not in sdfiles": (False, ["files-on"]),
    "not in sdapi (both is half done)": (False, ["both"]),
    "in neither route group (both is named once)": (False, ["both"]),
    "groups unreadable": (False, ["both", "files-on", "files-write-on"]),
    "record unreadable": (False, ["sh-on", "os-on", "sd-on", "voc-on", "bp-on", "dict-on", "shared-write-on", "net-on"]),
}


def run_scenarios(att_src, tmp):
    """Run the extracted code for every scenario; return {name: (allopen, closed_words, calls, say_text)} or None."""
    code = between(att_src, "# --- every access gate, for -OpenGates", "# --- the reinstall case")
    if not code:
        return None
    parts = [HARNESS_HEAD, code]
    for i, (name, fields, members, throws, rec) in enumerate(SCENARIOS):
        recfile = os.path.join(tmp, "rec%d.txt" % i)
        with open(recfile, "w", newline="") as f:
            f.write(lines_for({k: v for k, v in fields.items()}))
        parts.append("\n$script:calls.Clear(); $script:GatesAllOpen = $null")
        parts.append(rec.replace("%RECORD%", recfile.replace("\\", "/")))
        members_ps = "@{" + "; ".join("'%s' = @(%s)" % (g, ", ".join("'%s'" % n.replace("\\", "\\") for n in names))
                                      for g, names in members.items()) + "}"
        parts.append("$script:members = %s; $script:groupsThrow = %s" % (members_ps, "$true" if throws else "$false"))
        parts.append("$out = @(Open-InstallerGates -Account 'don' -WinUser 'Don')")
        parts.append("Write-Output ('RESULT~%d~' + $script:GatesAllOpen + '~' + ($script:calls -join ';') + '~' + (($out | Where-Object { $_ -like 'SAY: *WARNING*' }) -join ' / ') + '~' + ($out.Count))" % i)
    path = os.path.join(tmp, "harness.ps1")
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(parts) + "\n")
    ps = os.path.join(os.environ.get("SystemRoot", "C:/Windows"), "System32", "WindowsPowerShell", "v1.0", "powershell.exe")
    if not os.path.isfile(ps):
        return None
    r = subprocess.run([ps, "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", path], capture_output=True, text=True, timeout=120)
    out = {}
    for line in r.stdout.splitlines():
        if line.startswith("RESULT~"):
            _, idx, allopen, calls, warn, count = (line.split("~") + [""] * 6)[:6]
            out[SCENARIOS[int(idx)][0]] = (allopen == "True", calls, warn)
    if len(out) != len(SCENARIOS):
        return {"_error": (False, (r.stdout + r.stderr)[-600:], "")}
    return out


def checks(att, iss, mod, keys):
    rows = []

    def row(name, ok, detail=""):
        rows.append((name, bool(ok), detail))

    # --- static: the list and the tables -------------------------------------------------------------------------------------------
    m = re.search(r"\$GateWords = @\(([^)]*)\)", att)
    words = re.findall(r"'([a-z-]+)'", m.group(1)) if m else []
    row("S1 the word list is the expected one, files-on before files-write-on", words == EXPECT_WORDS, "%s" % words)
    mod_on = modifya_on_words(mod)
    gates = [w for w in mod_on if w not in NOT_GATES]
    row("S2 the list is both (ssh and the API) and every on-word modify.account accepts, less shared-read-on, files-admin-on and pins-on (a gate added later fails here)",
        sorted(["both"] + [w.lower() for w in gates]) == sorted(words), "modifya %s, list %s" % (sorted(w.lower() for w in gates), sorted(words)))
    row("S3 files-admin-on is not in the list or the installer text (the administration group ships off whatever the answer)",
        "files-admin-on" not in words and "files-admin-on" not in re.sub(r"#.*", "", att.split("function Get-ClosedGates")[0].split("$GateWords")[-1]),
        "")
    kn = keys_numbers(keys)
    fm = re.search(r"\$GateFields = @\((.*)\)\s*$", att, re.M)
    fields = {int(a): b for a, b in re.findall(r"@\((\d+),\s*'([a-z-]+)'\)", fm.group(1))} if fm else {}
    want_fields = {n: {7: "sh-on", 8: "os-on", 9: "sd-on", 10: "voc-on", 11: "bp-on", 12: "dict-on", 14: "shared-write-on", 15: "net-on"}[n] for n in EXPECT_FIELDS}
    row("S4 the register fields read are the ACC$ numbers of keys.h", fields == want_fields and all(kn.get(EXPECT_FIELDS[n]) == n for n in EXPECT_FIELDS),
        "fields %s, keys %s" % (fields, {EXPECT_FIELDS[n]: kn.get(EXPECT_FIELDS[n]) for n in EXPECT_FIELDS}))
    gm = re.search(r"\$GateGroups = \[ordered\]@\{([^}]*)\}", att)
    groups = dict(re.findall(r"'([a-z]+)'\s*=\s*'([a-z-]+)'", gm.group(1))) if gm else {}
    row("S5 the groups read are sdssh and sdapi (both), sdfiles (files-on) and sdfileswrite (files-write-on), and no others",
        groups == {"sdssh": "both", "sdapi": "both", "sdfiles": "files-on", "sdfileswrite": "files-write-on"}, "%s" % groups)

    # --- static: the call, the exit code, the default -------------------------------------------------------------------------------
    row("S6 -OpenGates is a switch, off by default", re.search(r"\[switch\] \$OpenGates", att) is not None)
    call = re.search(r"if \(\$OpenGates\) \{\s*Open-InstallerGates -Account \$User\.ToLower\(\) -WinUser \$User\s*if \(-not \$script:GatesAllOpen\) \{ \$result = 4 \}\s*\}", att)
    row("S7 the gates are opened only under if ($OpenGates), after the account record exists, and a failure is exit 4 and nothing else",
        call is not None and att.find("Say \"attach-account: $User now has an SD account\"") < att.find("Open-InstallerGates -Account"), "")
    row("S8 the function sets a variable and returns no value (Say prints, and a printing function that returns folds its output into the value)",
        re.search(r"function Open-InstallerGates[\s\S]*?\n\}", att) is not None
        and not re.search(r"return \$(true|false)", between(att, "function Open-InstallerGates", "# --- the reinstall case")), "")
    row("S9 the warning says NOT open and names the words, the success line is a different line",
        "WARNING these access gates are NOT open for" in att and "every access gate is open for" in att, "")
    task = re.search(r'^Name: "opengates";.*?\n.*$', iss, re.M)
    row("S10 sd.iss has the task opengates, UNCHECKED (the default is No)", task is not None and "unchecked" in iss[task.start():task.start() + 400],
        "task text: %s" % (iss[task.start():task.start() + 300] if task else "absent"))
    ps = between(iss, "function AttachInstallerAccount", "(* 25 Oct 26 - THE SHARED ACCOUNT")
    row("S11 the installer passes -OpenGates only under WizardIsTaskSelected('opengates')",
        re.search(r"if WizardIsTaskSelected\('opengates'\) then\s*Gates := ' -OpenGates';", ps) is not None and ps.count("-OpenGates") == 1, "")
    row("S12 code 4 is read as the account being made (the password prompt follows 0 and 2 only), and the warning carries ' NOT '",
        re.search(r"if AttachCode = 4 then\s*begin\s*AttachCode := 0;", iss) is not None and "Some access gates are NOT open for" in iss, "")
    row("S13 an upgrade does not ask: the tasks page is skipped on one, and a task left unchecked is not selected",
        "(PageID = wpSelectTasks) and TrueUpgrade" in iss, "")

    # --- dynamic: the extracted code, run ------------------------------------------------------------------------------------------
    tmp = tempfile.mkdtemp(prefix="opengates-")
    try:
        res = run_scenarios(att, tmp)
    except Exception as e:  # noqa: BLE001 - a harness that cannot run is exit 2 below
        res = None
        row("D0 the harness ran", False, "%r" % (e,))
    if res is None:
        row("D0 the harness ran (no gate tables found in attach-account.ps1, or no Windows PowerShell)", False, "")
        return rows
    if "_error" in res:
        row("D0 the harness ran", False, res["_error"][1])
        return rows
    for name in EXPECT:
        allopen, calls, warn = res[name]
        want_open, want_closed = EXPECT[name]
        row("D %s: all open = %s" % (name, want_open), allopen == want_open, "got %s; calls %s" % (allopen, calls))
        words_in_warn = re.findall(r"NOT open for \S+: ([a-z -]+?)( /|$)", warn)
        got_closed = words_in_warn[0][0].split() if words_in_warn else []
        row("D %s: the warning names exactly %s" % (name, want_closed or "no gate"), sorted(got_closed) == sorted(want_closed) and (bool(warn) == bool(want_closed)),
            "warning: %r" % warn)
    any_calls = res["all open (member names carry a domain and a different case)"][1]
    row("D the one sd call is -internal MODIFY.ACCOUNT <account in lower case> then the words in order",
        any_calls == "-internal MODIFY.ACCOUNT don " + " ".join(EXPECT_WORDS), any_calls)
    return rows


MUTANTS = [
    # (name, file key, old text, new text)
    ("the task is ticked by default", "iss", 'GroupDescription: "5)  SD Core account:"; Flags: unchecked', 'GroupDescription: "5)  SD Core account:"; Flags: '),
    ("the switch is passed whatever the task says", "iss", "  if WizardIsTaskSelected('opengates') then\n    Gates := ' -OpenGates';", "  Gates := ' -OpenGates';"),
    ("net-on is not in the list", "att", "'dict-on', 'net-on', 'shared-write-on'", "'dict-on', 'shared-write-on'"),
    ("files-write-on comes before files-on", "att", "'files-on', 'files-write-on')", "'files-write-on', 'files-on')"),
    ("files-admin-on is in the list", "att", "'files-on', 'files-write-on')", "'files-on', 'files-write-on', 'files-admin-on')"),
    ("a wrong register field", "att", "@(10, 'voc-on')", "@(9, 'voc-on')"),
    ("the success is not judged", "att", "if ($closed.Count -eq 0) {", "if ($true) {"),
    ("a missing group is not judged", "att", "if ((-not $in) -and ($closed -notcontains $GateGroups[$g])) { $null = $closed.Add($GateGroups[$g]) }", ""),
    ("both is named once per group", "att", "if ((-not $in) -and ($closed -notcontains $GateGroups[$g])) {", "if (-not $in) {"),
    ("the member name is compared with the domain", "att", "($_.Name -split '\\\\')[-1]", "$_.Name"),
    ("the function returns a value again", "att", "        $script:GatesAllOpen = $true\n        return\n", "        $script:GatesAllOpen = $true\n        return $true\n"),
    ("the gates are opened without being asked", "att", "            if ($OpenGates) {", "            if ($true) {"),
    ("a failed opening is not exit 4", "att", "if (-not $script:GatesAllOpen) { $result = 4 }", "if (-not $script:GatesAllOpen) { $result = 0 }"),
    ("code 4 is left as 4", "iss", "      AttachCode := 0;\n      OpenGatesMsg :=", "      OpenGatesMsg :="),
    ("the install asks on an upgrade too", "iss", "Result := (PageID = wpSelectTasks) and TrueUpgrade;", "Result := False;"),
]


def load():
    return read(ATTACH), read(ISS), read(MODIFYA), read(KEYS)


def selftest():
    att, iss, mod, keys = load()
    if any(not ok for _, ok, _ in checks(att, iss, mod, keys)):
        print("REFUSING - the unmutated sources already fail", file=sys.stderr)
        return 2
    holes = 0
    print("--- self-test: each mutation must be CAUGHT and match its text exactly once ---")
    for name, which, old, new in MUTANTS:
        src = att if which == "att" else iss
        if src.count(old) != 1:
            print("  [FAIL] %s: the text matches %d times, not once" % (name, src.count(old)))
            holes += 1
            continue
        a2, i2 = (src.replace(old, new), iss) if which == "att" else (att, src.replace(old, new))
        caught = [n for n, ok, _ in checks(a2, i2, mod, keys) if not ok]
        print("  [%s] %s%s" % ("pass" if caught else "FAIL", name, ": caught by " + "; ".join(caught[:2])[:110] if caught else ": NOT CAUGHT"))
        holes += 0 if caught else 1
    print("\n%d of %d mutants caught, %d missed" % (len(MUTANTS) - holes, len(MUTANTS), holes))
    return 1 if holes else 0


def main():
    for p in (ATTACH, ISS, MODIFYA, KEYS):
        if not os.path.isfile(p):
            print("test-install-opengates-units: CANNOT RUN - %s is not readable" % p, file=sys.stderr)
            return 2
    if "--selftest" in sys.argv[1:]:
        return selftest()
    rows = checks(*load())
    bad = 0
    for name, ok, detail in rows:
        bad += 0 if ok else 1
        print("  [%s] %s%s" % ("PASS" if ok else "FAIL", name, "" if ok else "   <- " + detail))
    print("\ntest-install-opengates-units: %d checks, %d failed" % (len(rows), bad))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
