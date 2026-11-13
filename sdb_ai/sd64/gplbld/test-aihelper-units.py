#!/usr/bin/env python3
"""test-aihelper-units.py - the WINDOWS parts of the AI helper (gplbld/sd-ai, sd-ai-ctl, sd-ai-ctl.ps1), RUN.  RELEASE_1.1 246, 13 Nov 2026.

  python C:\\Users\\Don\\Projects\\SDCore4Windows\\sdb_ai\\sd64\\gplbld\\test-aihelper-units.py [--selftest] [--helper FILE]

Free: no sd, no install, no elevation, no network (a pipe of its own on this machine and files in a temporary directory).  Exit 0 every row passed, 1 a row
failed, 2 it could not run (not Windows, no Python able to run the helper).

WHAT IS HELD.  By the test-once rule (owner, 12 Nov 2026) the helper's decisions, wire formats, limits and hygiene are Linux's code and are tested on Linux
(test-aihelper.py there).  This holds what Windows changed: THE PIPE - the helper's own loop (--listen, what --service runs) answers on a pipe, refuses a
second listener on a name already taken (FILE_FLAG_FIRST_PIPE_INSTANCE: the squatting case), owns its pipe (the kernel's and the client's owner check
reads exactly this), and grants no client more than PIPE_CLIENT_MASK; THE CALLER read from the pipe (an unelevated, non-member caller is refused an ask
with nogate and a setting with noadmin; a status carries no connection details for it); THE KEY - DPAPI round trip, the file made private (this account
and SYSTEM only), a key file whose access list grants anyone else refused, a blob made for one provider not readable as another's; THE CLIENT - every
line on standard output, the owner check refusing a pipe that is not the service's, --handover reading and REMOVING the file; THE WRAPPER - "error:
nopython:" when there is no Python.  NOT HELD: the service under the SCM, the virtual account, its DPAPI profile, a real second user (the falsifiers F1-F11
of the design, owed on an installed system).

--selftest  each MUTANT (a copy of sd-ai or sd-ai-ctl in a scratch directory with one rule taken out) must turn a row red; the live files are hashed before
and after and must be unchanged.
"""

import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
FILES = {"helper": os.path.join(HERE, "sd-ai"), "ctl": os.path.join(HERE, "sd-ai-ctl"), "wrapper": os.path.join(HERE, "sd-ai-ctl.ps1"),
         "finder": os.path.join(HERE, "sd-ai-python.ps1"), "providers": os.path.join(HERE, "ai-providers"), "context": os.path.join(HERE, "ai-context")}
passed = failed = 0


def say(s=""):
    print(s, flush=True)


def row(name, ok, detail=""):
    global passed, failed
    if ok:
        passed += 1
        say("  [PASS] " + name)
    else:
        failed += 1
        say("  [FAIL] " + name + ("   <- " + str(detail)[:300] if detail else ""))


def load(path):
    import importlib.machinery
    import importlib.util
    loader = importlib.machinery.SourceFileLoader("sdai_win_under_test", path)
    spec = importlib.util.spec_from_loader("sdai_win_under_test", loader)
    mod = importlib.util.module_from_spec(spec)
    loader.exec_module(mod)
    return mod


def pipe_listed(name):
    """Is a pipe of this name there?  Read from the pipe namespace's listing: os.path.exists would OPEN it, which is a connection the helper serves."""
    try:
        return name.split("\\")[-1].lower() in (n.lower() for n in os.listdir("\\\\.\\pipe\\"))
    except OSError:
        return False


def wait_pipe(name, proc, secs=15):
    end = time.time() + secs
    while time.time() < end:
        if pipe_listed(name):
            return True
        if proc.poll() is not None:
            return False
        time.sleep(0.05)
    return False


def ctl(ctl_path, pipe, *words, env=None):
    p = subprocess.run([sys.executable, "-I", "-B", ctl_path, "--pipe", pipe] + list(words), capture_output=True, text=True, timeout=60, env=env)
    return p.returncode, p.stdout, p.stderr


def raw_request(mod, pipe, line, check_owner=False):
    """One request through a client opened the way win32ai.c opens it (narrow access, identification level), using the client's own talk()."""
    return mod.talk(pipe, line, check_owner)


def run(helper, ctlfile, tmp):
    mod = load(helper)
    cmod = load(ctlfile)
    state = os.path.join(tmp, "state")
    for sub in ("", "keys", "state"):
        os.makedirs(os.path.join(state, sub), exist_ok=True)
    me = mod.own_sid()
    say("  caller: this process, SID %s, unelevated test run" % me)
    row("the helper reads this process's own account (own_sid)", bool(me) and me.startswith("S-1-5-"), me)

    say("\n--- the key: DPAPI in this account's scope, a private file")
    try:
        mod.write_key(state, "openai", "sk-test-0123456789abcdef")
        got = mod.read_key(state, "openai")
    except mod.Refuse as e:
        got = "Refuse %s %s" % (e.code, e.msg)
    except OSError as e:
        got = "OSError %s" % e
    row("write_key then read_key gives the key back", got == "sk-test-0123456789abcdef", got)
    kp = os.path.join(state, "keys", "openai")
    with open(kp, "rb") as f:
        blob = f.read()
    row("the key file does not hold the key in clear text", b"sk-test-0123456789abcdef" not in blob and len(blob) > 40, len(blob))
    sids = mod.acl_sids(kp)
    row("the key file's access list allows this account and SYSTEM and nobody else", sids == {me, "S-1-5-18"}, sids)
    shutil.copyfile(kp, os.path.join(state, "keys", "anthropic"))
    subprocess.run(["icacls", os.path.join(state, "keys", "anthropic"), "/inheritance:r", "/grant:r", "*%s:F" % me, "*S-1-5-18:F"], capture_output=True)
    try:
        mod.read_key(state, "anthropic")
        r = "read"
    except mod.Refuse as e:
        r = e.code
    row("a blob made for one provider is not read as another's (the entropy names the provider): nokey", r == "nokey", r)
    subprocess.run(["icacls", kp, "/grant", "*S-1-1-0:R"], capture_output=True)
    try:
        mod.read_key(state, "openai")
        r = "read"
    except mod.Refuse as e:
        r = (e.code, e.msg)
    row("a key file that Everyone may read is refused, not repaired (nokey, not private)", r == ("nokey", "the key file is not private"), r)
    os.remove(kp)
    os.remove(os.path.join(state, "keys", "anthropic"))

    say("\n--- the pipe: the helper's own loop, as the service runs it")
    pipe = r"\\.\pipe\sd-ai-test-%d-%d" % (os.getpid(), int(time.time() * 1000) % 100000)
    logf = os.path.join(tmp, "listen.err")
    with open(logf, "wb") as lf:
        proc = subprocess.Popen([sys.executable, "-I", "-B", helper, "--listen", pipe, "--state", state, "--providers", FILES["providers"]],
                                stdout=lf, stderr=lf, creationflags=0x08000000)
    try:
        up = wait_pipe(pipe, proc)
        row("the helper's loop makes its pipe (%s)" % pipe, up, open(logf, errors="replace").read() if not up else "")
        if not up:
            return
        with open(logf, "wb") as lf2:
            second = subprocess.Popen([sys.executable, "-I", "-B", helper, "--listen", pipe, "--state", state, "--providers", FILES["providers"]],
                                      stdout=lf2, stderr=lf2, creationflags=0x08000000)
            try:
                rc = second.wait(timeout=20)
            except subprocess.TimeoutExpired:
                second.kill()
                rc = "still running"
        row("a second listener on a name already taken will not run (FILE_FLAG_FIRST_PIPE_INSTANCE: a squatted name stops the service)", rc == 3,
            "%s %s" % (rc, open(logf, errors="replace").read()[-200:]))

        r = raw_request(cmod, pipe, {"v": 1, "op": "status"})
        row("a status through the pipe answers for this caller: no gate, no connection details (an unelevated, non-member caller)",
            r.get("t") == "status" and r.get("gate") is False and "providers" not in r and r.get("provider") == "", r)
        r = raw_request(cmod, pipe, {"v": 1, "op": "ask", "system": "", "prompt": "hello"})
        row("an ask from a caller outside sdaiusers is refused: nogate", r.get("t") == "err" and r.get("code") == "nogate", r)
        r = raw_request(cmod, pipe, {"v": 1, "op": "set", "what": "provider", "value": "openai"})
        row("a setting from a caller that is not the administrator is refused: noadmin, and nothing is written",
            r.get("code") == "noadmin" and not os.path.exists(os.path.join(state, "ai.conf")), r)
        r = raw_request(cmod, pipe, {"v": 1, "op": "keyset", "provider": "openai", "key": "sk-should-not-be-kept"})
        row("a key from a caller that is not the administrator is refused: noadmin, and no key file appears",
            r.get("code") == "noadmin" and not os.listdir(os.path.join(state, "keys")), r)
        r = raw_request(cmod, pipe, "not a request")
        row("a line that is not a request is badreq", r.get("code") == "badreq", r)

        owner, aces = pipe_security(cmod, pipe)
        row("the pipe's owner is the helper's own account (what win32ai.c and sd-ai-ctl check against NT SERVICE\\sd-ai)", owner == me, owner)
        wide = [(s, hex(m)) for (t, s, m) in aces if t == 0 and s not in (me, "S-1-5-18") and m & ~mod.PIPE_CLIENT_MASK]
        row("no client of the pipe but SYSTEM and the helper's account is granted more than PIPE_CLIENT_MASK (no FILE_CREATE_PIPE_INSTANCE)", aces and not wide, (aces, wide))
        row("Administrators are granted exactly PIPE_CLIENT_MASK", any(t == 0 and s == "S-1-5-32-544" and m == mod.PIPE_CLIENT_MASK for (t, s, m) in aces), aces)

        say("\n--- the client (sd-ai-ctl) and its wrapper")
        rc, out, err = ctl(ctlfile, pipe, "show")
        row("ctl show through the pipe: exit 0, every line on standard output, nothing on standard error",
            rc == 0 and out.startswith("AI provider in use by every account: none") and err == "", (rc, out, err))
        rc, out, err = ctl(ctlfile, pipe, "provider", "openai")
        row("ctl provider: the helper's refusal printed as error: noadmin: ..., exit 1, standard error empty", rc == 1 and out.startswith("error: noadmin:") and err == "", (rc, out, err))
        hf = os.path.join(tmp, "handover-key")
        with open(hf, "w") as f:
            f.write("sk-handover-0123456789\n")
        rc, out, err = ctl(ctlfile, pipe, "key", "openai", "--handover", hf)
        row("ctl key --handover: the file is removed whatever the helper said (here noadmin)", not os.path.exists(hf) and out.startswith("error: noadmin:"), (rc, out, err))
        with open(hf, "w") as f:
            f.write("sk-handover-0123456789\n")
        rc, out, err = ctl(ctlfile, pipe, "key", "martian", "--handover", hf)
        row("ctl key --handover with a provider that is none of the five: refused, and the file removed all the same", rc == 2 and not os.path.exists(hf), (rc, out, err))
        rc, out, err = ctl(ctlfile, pipe + "-nobody", "show")
        row("ctl with no helper on the pipe: 'could not be reached' on standard output, exit 2", rc == 2 and "could not be reached" in out and err == "", (rc, out, err))
        r = None
        try:
            cmod.talk(pipe, {"v": 1, "op": "status"}, True)
            r = "sent"
        except OSError as e:
            r = str(e)
        row("the client's owner check refuses a pipe that is not NT SERVICE\\sd-ai's (this one is the test's own)", r != "sent" and "not the AI helper" in r, r)
    finally:
        proc.kill()
        proc.wait(timeout=10)

    say("\n--- the wrapper, with no Python to find")
    ps = os.path.join(os.environ.get("SystemRoot", r"C:\Windows"), "System32", "WindowsPowerShell", "v1.0", "powershell.exe")
    wdir = os.path.join(tmp, "nopy")
    os.makedirs(wdir)
    shutil.copy(FILES["wrapper"], wdir)
    with open(os.path.join(wdir, "sd-ai-python.ps1"), "w") as f:
        f.write("function Find-SdPython { return '' }\n")
    p = subprocess.run([ps, "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", os.path.join(wdir, "sd-ai-ctl.ps1"), "show"],
                       capture_output=True, text=True, timeout=120)
    row("sd-ai-ctl.ps1 with no all-users Python: one line, error: nopython: ..., exit 1 (set.ai's 12934)",
        p.returncode == 1 and p.stdout.strip() == "error: nopython: no Python 3.13 or later is installed for all users", (p.returncode, p.stdout, p.stderr))


def pipe_security(cmod, pipe):
    """The owner and the ALLOW/DENY entries (type, SID, mask) of the pipe, read through a client handle the way the kernel opens one."""
    import ctypes
    import ctypes.wintypes as wt
    k32, adv = cmod.k32, cmod.adv
    h = k32.CreateFileW(pipe, cmod.PIPE_CLIENT_MASK, 0, None, 3, 0x00110000, None)
    if h in (None, cmod.INVALID_HANDLE):
        return None, []
    try:
        owner = ctypes.c_void_p()
        dacl = ctypes.c_void_p()
        sd = ctypes.c_void_p()
        adv.GetSecurityInfo.argtypes = [wt.HANDLE, ctypes.c_int, wt.DWORD, ctypes.POINTER(ctypes.c_void_p), ctypes.c_void_p, ctypes.POINTER(ctypes.c_void_p),
                                        ctypes.c_void_p, ctypes.POINTER(ctypes.c_void_p)]
        if adv.GetSecurityInfo(h, 6, 0x1 | 0x4, ctypes.byref(owner), None, ctypes.byref(dacl), None, ctypes.byref(sd)) != 0:
            return None, []
        hm = load(FILES["helper"])
        aces = []
        info = hm.ACL_SIZE_INFORMATION()
        hm.adv.GetAclInformation(dacl, ctypes.byref(info), ctypes.sizeof(info), 2)
        for i in range(info.AceCount):
            ace = ctypes.c_void_p()
            hm.adv.GetAce(dacl, i, ctypes.byref(ace))
            hdr = hm.ACE_HEADER.from_address(ace.value)
            mask = wt.DWORD.from_address(ace.value + 4).value
            aces.append((hdr.AceType, hm.sid_text(ace.value + 8), mask))
        o = hm.sid_text(owner.value)
        k32.LocalFree(sd)
        return o, aces
    finally:
        k32.CloseHandle(h)


# Each mutant: (file key, what it takes out, old text, new text).  The old text must be in the file exactly once.
MUTANTS = [
    ("helper", "the pipe is made without FILE_FLAG_FIRST_PIPE_INSTANCE", "0x00000003 | (0x00080000 if first else 0)", "0x00000003"),
    ("helper", "private_file accepts any access list", "return sids is not None and me is not None and sids <= {me, SID_SYSTEM}", "return True"),
    ("helper", "the key is written in clear", "blob = dpapi(key.encode(\"ascii\"), key_entropy(name), True)", "blob = key.encode(\"ascii\")"),
    ("helper", "the entropy does not name the provider", "return (\"sd-ai key \" + name).encode(\"ascii\")", "return b\"sd-ai key\""),
    ("helper", "the pipe grants Administrators everything", "parts.append(\"(A;;0x%08X;;;BA)\" % PIPE_CLIENT_MASK)", "parts.append(\"(A;;GA;;;BA)\")"),
    ("helper", "an unknown caller may change settings", "        if uid is None or not is_admin(uid):\n            return {\"t\": \"err\", \"code\": \"noadmin\", \"msg\": \"only the administrator may change the AI settings\"}, \"-\"",
     "        if False:\n            pass"),
    ("ctl", "the client writes its errors to standard error", "def say(s):\n    sys.stdout.write(s + \"\\n\")", "def say(s):\n    sys.stderr.write(s + \"\\n\")"),
    ("ctl", "--handover leaves the file", "            os.remove(path)\n        except OSError:", "            pass\n        except OSError:"),
    ("ctl", "the client trusts any pipe's owner", "        if check_owner and not owned_by_service(h):", "        if False:"),
]


def digest(p):
    with open(p, "rb") as f:
        return hashlib.sha256(f.read()).hexdigest()


def one_run(helper, ctlfile):
    global passed, failed
    passed = failed = 0
    tmp = tempfile.mkdtemp(prefix="sdai-units-")
    try:
        run(helper, ctlfile, tmp)
    finally:
        subprocess.run(["icacls", tmp, "/reset", "/T", "/Q"], capture_output=True)
        shutil.rmtree(tmp, ignore_errors=True)
    return failed


def selftest():
    before = {k: digest(p) for k, p in FILES.items()}
    missed = 0
    for n, (key, what, old, new) in enumerate(MUTANTS, 1):
        with open(FILES[key], encoding="ascii") as f:
            text = f.read()
        if text.count(old) != 1:
            say("MUTANT %d (%s): its text is not in %s exactly once - the self-test is stale" % (n, what, key))
            missed += 1
            continue
        d = tempfile.mkdtemp(prefix="sdai-mutant-")
        try:
            paths = {"helper": os.path.join(d, "sd-ai"), "ctl": os.path.join(d, "sd-ai-ctl")}
            for k in paths:
                shutil.copyfile(FILES[k], paths[k])
            for extra in ("ai-providers", "ai-context"):
                shutil.copyfile(os.path.join(HERE, extra), os.path.join(d, extra))
            with open(paths[key], "w", encoding="ascii", newline="\n") as f:
                f.write(text.replace(old, new))
            red = one_run(paths["helper"], paths["ctl"])
        finally:
            shutil.rmtree(d, ignore_errors=True)
        say("MUTANT %d (%s): %s" % (n, what, "caught (%d red)" % red if red else "MISSED"))
        missed += 0 if red else 1
    after = {k: digest(p) for k, p in FILES.items()}
    if before != after:
        say("THE LIVE FILES CHANGED DURING THE SELF-TEST")
        return 1
    say("selftest: %d mutants, %d missed; the live files are unchanged (SHA-256)" % (len(MUTANTS), missed))
    return 1 if missed else 0


def main():
    if os.name != "nt":
        say("test-aihelper-units: Windows only")
        return 2
    if sys.version_info < (3, 13):
        say("test-aihelper-units: the helper needs Python 3.13 or later; this is %s" % sys.version.split()[0])
        return 2
    for k, p in FILES.items():
        if not os.path.isfile(p):
            say("test-aihelper-units: %s is missing (%s)" % (k, p))
            return 2
    if "--selftest" in sys.argv:
        return selftest()
    helper = FILES["helper"]
    if "--helper" in sys.argv:
        helper = sys.argv[sys.argv.index("--helper") + 1]
    say("test-aihelper-units: %s and %s, under %s" % (helper, FILES["ctl"], sys.executable))
    bad = one_run(helper, FILES["ctl"])
    say("\n%d passed, %d failed" % (passed, bad))
    if passed == 0:
        say("NOTHING WAS MEASURED")
        return 1
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
