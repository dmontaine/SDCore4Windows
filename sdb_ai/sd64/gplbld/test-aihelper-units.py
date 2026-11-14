#!/usr/bin/env python3
"""test-aihelper-units.py - the AI helper sd-ai.exe (gplsrc/sdai, native C), BUILT AND RUN.  RELEASE_1.1 246, 13 Nov 2026.

  python C:\\Users\\Don\\Projects\\SDCore4Windows\\sdb_ai\\sd64\\gplbld\\test-aihelper-units.py [--selftest [--from=N]]

Free: no sd, no install, no elevation, no network but the loopback (a pipe of its own, files in a temporary directory, a fake provider on
127.0.0.1).  It BUILDS the helper from gplsrc/sdai into a temporary directory with MSYS2's UCRT64 gcc and the static OpenSSL, as the Makefile's
sd-ai target does, plus -DSDAI_TESTS: the test build's three hooks (SD_AI_TEST_GATE names the gate group, SD_AI_TEST_CHECK_OWNER turns the
client's owner check on for a test pipe, --test-key writes and reads a key on its own); the shipped build has none of them
(test-ai-units.py checks that).  Exit 0 every row passed, 1 a row failed, 2 it could not run (not Windows, no UCRT64 gcc or OpenSSL).

WHAT IS HELD.  The decisions are Linux's and tested there (test-once rule, owner 12 Nov 2026); this holds what Windows and the C rewrite own:
THE KEY - DPAPI round trip, not in clear, the file private (this account and SYSTEM), a blob made for one provider not readable as another's, a
key file Everyone may read refused; THE PIPE - the helper's own loop answers, a second listener on a taken name will not run
(FILE_FLAG_FIRST_PIPE_INSTANCE), the pipe's owner is the helper's account, no client is granted more than PIPE_CLIENT_MASK; THE CALLER - read off
the pipe: with a gate group the caller is NOT in (a name that does not exist), an ask is nogate and the status says gate false; with the real
sdaiusers the status's gate is the caller's REAL membership, read here independently and printed (owner, 13 Nov: the developer's own account may
be a member after an install with every gate opened); a setting from an unelevated caller is noadmin and writes nothing; THE WIRE - the status
and ok lines are the bytes the Python helper wrote (json.dumps with ", " and ": "), which SD's BASIC parses; THE CLIENT - every line on standard
output, the owner check refusing a pipe that is not NT SERVICE\\sd-ai's, --handover reading and REMOVING the file; THE CALL - a round trip to a
fake provider over TLS with the administrator's CA file (the key sent only as the bearer header to that URL), hygiene (an escape sequence never
comes back, curly quotes become plain), one retry on 429, a redirect refused, an answer over the reply limit refused, and the certificate refused
without the CA file (the Windows store does not hold the test CA) and for another host name.
NOT HELD: the service under the SCM, the virtual account and its DPAPI profile, SDSYS, a second real user, a real provider with the Windows store
(the design's falsifiers F1-F11, owed on an installed system).

--selftest  each MUTANT (a copy of gplsrc/sdai in a scratch directory with one rule taken out, BUILT) must turn a row red; the live sources are
hashed before and after and must be unchanged.  --from=N runs the mutants from number N.
"""

import ctypes
import ctypes.wintypes as wt
import glob
import hashlib
import importlib.util
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
SD64 = os.path.dirname(HERE)
AIDIR = os.path.join(SD64, "gplsrc", "sdai")
PROVIDERS = os.path.join(HERE, "ai-providers")
UCRT_BIN = os.path.join("C:" + os.sep, "msys64", "ucrt64", "bin")
GCC = os.path.join(UCRT_BIN, "gcc.exe")
PIPE_CLIENT_MASK = 0x00120183
NOGATE = "sdai-test-nogroup-%d" % os.getpid()        # a gate group that does not exist: nobody is in it
KEY = "test-key-0123456789"
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
        say("  [FAIL] " + name + ("   <- " + str(detail)[:400] if detail else ""))


# ---------------------------------------------------------------------------------------------------- Windows reads of our own (not the helper's code)

k32 = ctypes.WinDLL("kernel32", use_last_error=True)
adv = ctypes.WinDLL("advapi32", use_last_error=True)
netapi = ctypes.WinDLL("netapi32", use_last_error=True)
k32.CreateFileW.restype = wt.HANDLE
k32.CreateFileW.argtypes = [wt.LPCWSTR, wt.DWORD, wt.DWORD, ctypes.c_void_p, wt.DWORD, wt.DWORD, wt.HANDLE]
k32.CloseHandle.argtypes = [wt.HANDLE]
k32.WriteFile.argtypes = [wt.HANDLE, ctypes.c_char_p, wt.DWORD, ctypes.POINTER(wt.DWORD), ctypes.c_void_p]
k32.ReadFile.argtypes = [wt.HANDLE, ctypes.c_void_p, wt.DWORD, ctypes.POINTER(wt.DWORD), ctypes.c_void_p]
k32.LocalFree.argtypes = [ctypes.c_void_p]
k32.GetCurrentProcess.restype = wt.HANDLE
adv.OpenProcessToken.argtypes = [wt.HANDLE, wt.DWORD, ctypes.POINTER(wt.HANDLE)]
adv.GetTokenInformation.argtypes = [wt.HANDLE, ctypes.c_int, ctypes.c_void_p, wt.DWORD, ctypes.POINTER(wt.DWORD)]
adv.ConvertSidToStringSidW.argtypes = [ctypes.c_void_p, ctypes.POINTER(wt.LPWSTR)]
adv.GetSecurityInfo.restype = wt.DWORD
adv.GetSecurityInfo.argtypes = [wt.HANDLE, ctypes.c_int, wt.DWORD, ctypes.POINTER(ctypes.c_void_p), ctypes.c_void_p, ctypes.POINTER(ctypes.c_void_p),
                                ctypes.c_void_p, ctypes.POINTER(ctypes.c_void_p)]
adv.GetNamedSecurityInfoW.restype = wt.DWORD
adv.GetNamedSecurityInfoW.argtypes = [wt.LPCWSTR, ctypes.c_int, wt.DWORD, ctypes.POINTER(ctypes.c_void_p), ctypes.POINTER(ctypes.c_void_p),
                                      ctypes.POINTER(ctypes.c_void_p), ctypes.c_void_p, ctypes.POINTER(ctypes.c_void_p)]
adv.GetAce.argtypes = [ctypes.c_void_p, wt.DWORD, ctypes.POINTER(ctypes.c_void_p)]
netapi.NetLocalGroupGetMembers.argtypes = [wt.LPCWSTR, wt.LPCWSTR, wt.DWORD, ctypes.POINTER(ctypes.c_void_p), wt.DWORD, ctypes.POINTER(wt.DWORD),
                                           ctypes.POINTER(wt.DWORD), ctypes.POINTER(ctypes.c_size_t)]
netapi.NetApiBufferFree.argtypes = [ctypes.c_void_p]


def sid_text(psid):
    out = wt.LPWSTR()
    if not psid or not adv.ConvertSidToStringSidW(psid, ctypes.byref(out)):
        return None
    try:
        return out.value
    finally:
        k32.LocalFree(out)


def own_sid():
    tok = wt.HANDLE()
    if not adv.OpenProcessToken(k32.GetCurrentProcess(), 0x0008, ctypes.byref(tok)):
        return None
    try:
        need = wt.DWORD()
        adv.GetTokenInformation(tok, 1, None, 0, ctypes.byref(need))
        buf = ctypes.create_string_buffer(need.value)
        if not adv.GetTokenInformation(tok, 1, buf, need, ctypes.byref(need)):
            return None
        return sid_text(ctypes.cast(buf, ctypes.POINTER(ctypes.c_void_p))[0])
    finally:
        k32.CloseHandle(tok)


def group_sids(group):
    """The SIDs of the local group's direct members, or None when there is no such group."""
    resume = ctypes.c_size_t(0)
    out = set()
    while True:
        buf = ctypes.c_void_p()
        read, total = wt.DWORD(), wt.DWORD()
        rc = netapi.NetLocalGroupGetMembers(None, group, 0, ctypes.byref(buf), 0xFFFFFFFF, ctypes.byref(read), ctypes.byref(total), ctypes.byref(resume))
        if rc not in (0, 234):
            return None
        try:
            for i in range(read.value):
                out.add(sid_text(ctypes.c_void_p.from_address(buf.value + i * ctypes.sizeof(ctypes.c_void_p)).value))
        finally:
            if buf:
                netapi.NetApiBufferFree(buf)
        if rc == 0:
            return out


def aces_of(dacl):
    aces = []
    count = ctypes.c_ushort.from_address(dacl + 4).value          # ACL: revision, sbz1, size, AceCount
    for i in range(count):
        ace = ctypes.c_void_p()
        if not adv.GetAce(dacl, i, ctypes.byref(ace)):
            break
        typ = ctypes.c_ubyte.from_address(ace.value).value
        mask = wt.DWORD.from_address(ace.value + 4).value
        aces.append((typ, sid_text(ace.value + 8), mask))
    return aces


def file_security(path):
    owner, dacl, sd = ctypes.c_void_p(), ctypes.c_void_p(), ctypes.c_void_p()
    if adv.GetNamedSecurityInfoW(path, 1, 0x1 | 0x4, ctypes.byref(owner), None, ctypes.byref(dacl), None, ctypes.byref(sd)) != 0:
        return None, None
    try:
        return sid_text(owner.value), (aces_of(dacl.value) if dacl.value else None)
    finally:
        k32.LocalFree(sd)


def open_pipe(pipe):
    """A client handle opened as win32ai.c opens one: the narrow access, identification level."""
    return k32.CreateFileW(pipe, PIPE_CLIENT_MASK, 0, None, 3, 0x00110000, None)


def pipe_security(pipe):
    h = open_pipe(pipe)
    if h in (None, wt.HANDLE(-1).value, ctypes.c_void_p(-1).value):
        return None, []
    try:
        owner, dacl, sd = ctypes.c_void_p(), ctypes.c_void_p(), ctypes.c_void_p()
        if adv.GetSecurityInfo(h, 6, 0x1 | 0x4, ctypes.byref(owner), None, ctypes.byref(dacl), None, ctypes.byref(sd)) != 0:
            return None, []
        try:
            return sid_text(owner.value), aces_of(dacl.value)
        finally:
            k32.LocalFree(sd)
    finally:
        k32.CloseHandle(h)


def pipe_request(pipe, line, timeout=60):
    """One request line (bytes, no newline) through a client opened as the kernel opens it; the reply line, bytes, without its newline."""
    h = open_pipe(pipe)
    if h in (None, ctypes.c_void_p(-1).value):
        return b"<no helper on the pipe, error %d>" % ctypes.get_last_error()
    try:
        data = line + b"\n"
        n = wt.DWORD()
        k32.WriteFile(h, data, len(data), ctypes.byref(n), None)
        buf = b""
        end = time.time() + timeout
        while b"\n" not in buf and time.time() < end:
            chunk = ctypes.create_string_buffer(65536)
            if not k32.ReadFile(h, chunk, 65536, ctypes.byref(n), None) or n.value == 0:
                break
            buf += chunk.raw[:n.value]
        return buf.split(b"\n", 1)[0]
    finally:
        k32.CloseHandle(h)


def pipe_listed(name):
    """Is a pipe of this name there?  From the namespace's listing: opening it would be a connection the helper serves."""
    try:
        return name.split("\\")[-1].lower() in (n.lower() for n in os.listdir("\\\\.\\pipe\\"))
    except OSError:
        return False


# ---------------------------------------------------------------------------------------------------- the build, the listener, the client

def build(src, out):
    """The test build of the helper from the C files in src; (exe path or None, compiler output)."""
    exe = os.path.join(out, "sd-ai.exe")
    env = dict(os.environ)
    env["PATH"] = UCRT_BIN + os.pathsep + env.get("PATH", "")
    cmd = [GCC, "-std=gnu17", "-Wall", "-Wformat=2", "-O2", "-municode", "-DSDAI_TESTS"] + sorted(glob.glob(os.path.join(src, "*.c"))) + \
          ["-o", exe, "-Wl,-Bstatic", "-lssl", "-lcrypto", "-Wl,-Bdynamic", "-lcrypt32", "-lws2_32", "-ladvapi32", "-lnetapi32"]
    p = subprocess.run(cmd, capture_output=True, text=True, env=env, timeout=300)
    return (exe if p.returncode == 0 and os.path.isfile(exe) else None), p.stdout + p.stderr


def listen(exe, pipe, state, gate=None):
    env = dict(os.environ)
    env.pop("SD_AI_TEST_GATE", None)
    if gate:
        env["SD_AI_TEST_GATE"] = gate
    proc = subprocess.Popen([exe, "--listen", pipe, "--state", state, "--providers", PROVIDERS], stdout=subprocess.DEVNULL, stderr=subprocess.PIPE,
                            creationflags=0x08000000, env=env)
    end = time.time() + 15
    while time.time() < end:
        if pipe_listed(pipe):
            return proc, True
        if proc.poll() is not None:
            break
        time.sleep(0.05)
    return proc, False


def stop(proc):
    proc.kill()
    try:
        proc.wait(timeout=10)
    except subprocess.TimeoutExpired:
        pass


def ctl(exe, *words, env_add=None):
    env = dict(os.environ)
    env.pop("SD_AI_PIPE", None)
    env.update(env_add or {})
    p = subprocess.run([exe] + list(words), capture_output=True, text=True, timeout=90, env=env, stdin=subprocess.DEVNULL)
    return p.returncode, p.stdout, p.stderr


def jline(b):
    try:
        return json.loads(b.decode("utf-8"))
    except (ValueError, UnicodeDecodeError):
        return {"unreadable": repr(b[:200])}


def ask_line(prompt):
    return json.dumps({"v": 1, "op": "ask", "system": "", "prompt": prompt, "maxtokens": 100}, separators=(",", ":")).encode("ascii")


def load_fake():
    spec = importlib.util.spec_from_file_location("sdai_fakemodel", os.path.join(HERE, "test-fakemodel.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


# ---------------------------------------------------------------------------------------------------- the rows

def run(exe, tmp, fake):
    me = own_sid()
    members = group_sids("sdaiusers")
    real_gate = members is not None and me in members
    say("  built: %s" % exe)
    say("  caller: this process, SID %s, unelevated test run" % me)
    say("  this account in sdaiusers: %s (read here with NetLocalGroupGetMembers: %s)" % (real_gate, "no such group" if members is None else "%d member(s)" % len(members)))
    row("this process's own account is read (the null case: every row below compares against it)", bool(me) and me.startswith("S-1-5-"), me)

    say("\n--- the key: DPAPI in this account's scope, a private file")
    state = os.path.join(tmp, "state")
    for sub in ("", "keys", "state"):
        os.makedirs(os.path.join(state, sub), exist_ok=True)
    w = ctl(exe, "--test-key", "write", state, "openai", "sk-test-0123456789abcdef")
    r = ctl(exe, "--test-key", "read", state, "openai")
    row("the key is written and read back (--test-key: write_key, then read_key)", w[1].strip() == "ok" and r[1].strip() == "key: sk-test-0123456789abcdef", (w, r))
    kp = os.path.join(state, "keys", "openai")
    blob = open(kp, "rb").read() if os.path.exists(kp) else b""
    row("the key file does not hold the key in clear text (a DPAPI blob)", b"sk-test-0123456789abcdef" not in blob and len(blob) > 40, len(blob))
    owner, aces = file_security(kp)
    allow = {s for (t, s, m) in (aces or []) if t == 0}
    row("the key file's access list allows this account and SYSTEM and nobody else, and it is protected (nothing inherited)", allow == {me, "S-1-5-18"} and owner == me, (owner, aces))
    if os.path.exists(kp):
        shutil.copyfile(kp, os.path.join(state, "keys", "anthropic"))
        subprocess.run(["icacls", os.path.join(state, "keys", "anthropic"), "/inheritance:r", "/grant:r", "*%s:F" % me, "*S-1-5-18:F"], capture_output=True)
    r = ctl(exe, "--test-key", "read", state, "anthropic")
    row("a blob made for one provider is not read as another's (the entropy names the provider): nokey", r[1].startswith("refused: nokey: the key file cannot be opened"), r)
    subprocess.run(["icacls", kp, "/grant", "*S-1-1-0:R"], capture_output=True)
    r = ctl(exe, "--test-key", "read", state, "openai")
    row("a key file that Everyone may read is refused, not repaired (nokey, not private)", r[1].strip() == "refused: nokey: the key file is not private", r)
    for f in ("openai", "anthropic"):
        try:
            os.remove(os.path.join(state, "keys", f))
        except OSError:
            pass

    say("\n--- the pipe and the caller: the helper's own loop, as the service runs it, with a gate group nobody is in (%s)" % NOGATE)
    pipe = r"\\.\pipe\sd-ai-test-%d-%d" % (os.getpid(), int(time.time() * 1000) % 100000)
    proc, up = listen(exe, pipe, state, NOGATE)
    try:
        row("the helper's loop makes its pipe (%s)" % pipe, up, proc.stderr.read().decode(errors="replace") if not up and proc.poll() is not None else "")
        if not up:
            return
        sp = subprocess.Popen([exe, "--listen", pipe, "--state", state, "--providers", PROVIDERS], stdout=subprocess.DEVNULL, stderr=subprocess.PIPE,
                              creationflags=0x08000000)
        try:
            src, serr = sp.wait(timeout=20), sp.stderr.read().decode(errors="replace")
        except subprocess.TimeoutExpired:          # it took the name: what the flag is there to stop
            stop(sp)
            src, serr = "still running after 20 s", ""
        row("a second listener on a name already taken will not run (FILE_FLAG_FIRST_PIPE_INSTANCE: a squatted name stops the service), exit 3, said why",
            src == 3 and "could not be made" in serr, (src, serr))
        raw = pipe_request(pipe, b'{"v":1,"op":"status"}')
        row("THE WIRE: a status for a non-member, non-administrator is exactly the Python helper's bytes", raw == b'{"t": "status", "provider": "", "model": "", "gate": false, "key": false}', raw)
        r = jline(pipe_request(pipe, ask_line("hello")))
        row("an ask from a caller outside the gate group is refused: nogate", r.get("t") == "err" and r.get("code") == "nogate", r)
        r = jline(pipe_request(pipe, b'{"v":1,"op":"set","what":"provider","value":"openai"}'))
        row("a setting from a caller that is not the administrator is refused: noadmin, and nothing is written", r.get("code") == "noadmin" and not os.path.exists(os.path.join(state, "ai.conf")), r)
        r = jline(pipe_request(pipe, b'{"v":1,"op":"keyset","provider":"openai","key":"sk-should-not-be-kept"}'))
        row("a key from a caller that is not the administrator is refused: noadmin, and no key file appears", r.get("code") == "noadmin" and not os.listdir(os.path.join(state, "keys")), r)
        raw = pipe_request(pipe, b"not a request")
        row("THE WIRE: a line that is not a request is badreq, in the Python helper's bytes",
            raw == b'{"t": "err", "code": "badreq", "msg": "not a request this helper understands"}', raw)
        owner, aces = pipe_security(pipe)
        row("the pipe's owner is the helper's own account (what win32ai.c and the client check against NT SERVICE\\sd-ai)", owner == me, owner)
        wide = [(s, hex(m)) for (t, s, m) in aces if t == 0 and s not in (me, "S-1-5-18") and m & ~PIPE_CLIENT_MASK]
        row("no client of the pipe but SYSTEM and the helper's account is granted more than PIPE_CLIENT_MASK (no FILE_CREATE_PIPE_INSTANCE)", aces and not wide, (aces, wide))
        row("Administrators are granted exactly PIPE_CLIENT_MASK", any(t == 0 and s == "S-1-5-32-544" and m == PIPE_CLIENT_MASK for (t, s, m) in aces), aces)
        log = open(os.path.join(state, "sd-ai.log"), errors="replace").read() if os.path.exists(os.path.join(state, "sd-ai.log")) else ""
        row("each request left one log line with this caller's SID, the status and no text", ("sid=%s provider=- status=nogate in=- out=-" % me) in log and "hello" not in log, log[-300:])

        say("\n--- the client (sd-ai.exe show ...)")
        rc, out, err = ctl(exe, "--pipe", pipe, "show")
        row("show through the pipe: exit 0, every line on standard output, nothing on standard error",
            rc == 0 and out.startswith("AI provider in use by every account: none (the AI is off)\n  model -, key not set, your account's gate off") and err == "", (rc, out, err))
        rc, out, err = ctl(exe, "show", env_add={"SD_AI_PIPE": pipe})
        row("SD_AI_PIPE names the pipe when --pipe does not (the tests' way; the product never sets it)", rc == 0 and out.startswith("AI provider in use") and err == "", (rc, out, err))
        rc, out, err = ctl(exe, "--pipe", pipe, "provider", "openai")
        row("provider: the helper's refusal printed as error: noadmin: ..., exit 1, standard error empty",
            rc == 1 and out == "error: noadmin: only the administrator may change the AI settings\n" and err == "", (rc, out, err))
        hf = os.path.join(tmp, "handover-key")
        with open(hf, "w") as f:
            f.write("sk-handover-0123456789\n")
        rc, out, err = ctl(exe, "--pipe", pipe, "key", "openai", "--handover", hf)
        row("key --handover: the file is removed whatever the helper said (here noadmin)", not os.path.exists(hf) and out.startswith("error: noadmin:"), (rc, out, err))
        with open(hf, "w") as f:
            f.write("sk-handover-0123456789\n")
        rc, out, err = ctl(exe, "--pipe", pipe, "key", "martian", "--handover", hf)
        row("key --handover with a provider that is none of the five: refused, exit 2, and the file removed all the same", rc == 2 and not os.path.exists(hf), (rc, out, err))
        rc, out, err = ctl(exe, "--pipe", pipe + "-nobody", "show")
        row("no helper on the pipe: 'could not be reached' on standard output, exit 2", rc == 2 and out == "sd-ai-ctl: the AI helper could not be reached (OSError)\n" and err == "", (rc, out, err))
        rc, out, err = ctl(exe, "--pipe", pipe, "show", env_add={"SD_AI_TEST_CHECK_OWNER": "1"})
        row("the client's owner check refuses a pipe that is not NT SERVICE\\sd-ai's (this one is the test's own): nothing sent, exit 2",
            rc == 2 and "could not be reached" in out, (rc, out, err))
        rc, out, err = ctl(exe, "--pipe", pipe)
        row("no command: the usage, on standard output, exit 2", rc == 2 and out.startswith("usage: sd-ai-ctl") and err == "", (rc, out, err))
    finally:
        stop(proc)

    say("\n--- the gate as delivered: the real group sdaiusers, read live")
    pipe2 = pipe + "-real"
    proc, up = listen(exe, pipe2, state, None)
    try:
        r = jline(pipe_request(pipe2, b'{"v":1,"op":"status"}')) if up else {}
        row("with the real group, the status's gate is this account's REAL membership of sdaiusers (%s), read live" % real_gate, up and r.get("gate") is real_gate, r)
    finally:
        stop(proc)

    say("\n--- the call: a fake provider on 127.0.0.1 over TLS")
    if fake is None:
        row("the fake provider could be loaded (test-fakemodel.py) and the openssl command line found", False, "see above")
        return
    gate = None
    for g in ("sdaiusers", "Administrators", "Users"):
        s = group_sids(g)
        if s is not None and me in s:
            gate = g
            break
    say("  the gate for these rows: %s (a local group this account is a direct member of)" % gate)
    row("a local group holds this account directly, so the call can pass the gate", gate is not None, "sdaiusers, Administrators, Users")
    if gate is None:
        return
    pki = os.path.join(tmp, "pki")
    os.makedirs(pki)
    try:
        fake.make_pki(pki)
    except RuntimeError as e:
        row("the test certificates are made", False, e)
        return
    fm = fake.FakeModel(pki, key=KEY).start()
    fw = fake.FakeModel(pki, key=KEY, cert="wrongname").start()
    st3 = os.path.join(tmp, "state3")
    for sub in ("", "keys", "state"):
        os.makedirs(os.path.join(st3, sub), exist_ok=True)
    ca = os.path.join(pki, "ca.crt").replace("\\", "/")

    def conf(port, with_ca=True):
        lines = ["provider=custom", "custom.name=Fake", "custom.url=https://localhost:%d/v1/chat/completions" % port, "custom.format=openai", "custom.auth=bearer",
                 "custom.version=", "custom.maxparam=max_tokens", "model.custom=fake-large"]
        if with_ca:
            lines.append("ca-file=" + ca)
        with open(os.path.join(st3, "ai.conf"), "w", newline="\n") as f:
            f.write("\n".join(lines) + "\n")

    conf(fm.port)
    w = ctl(exe, "--test-key", "write", st3, "custom", KEY)
    pipe3 = pipe + "-call"
    proc, up = listen(exe, pipe3, st3, gate)
    try:
        row("the listener for the call is up and the key is set", up and w[1].strip() == "ok", w)
        raw = pipe_request(pipe3, ask_line("hello"))
        row("THE WIRE: an answer is exactly the Python helper's bytes: text, tokens, provider, truncated, replaced",
            raw == b'{"t": "ok", "text": "The answer is forty-two.", "in": 11, "out": 7, "provider": "custom", "truncated": false, "replaced": 0}', raw)
        last = fm.log[-1] if fm.log else {}
        sent = jline(last.get("body", b""))
        row("the request went to the provider's path with the key as the bearer header and nowhere else in it, with the model and the person's text",
            last.get("path") == "/v1/chat/completions" and last.get("headers", {}).get("authorization") == "Bearer " + KEY and KEY.encode() not in last.get("body", b"")
            and sent.get("model") == "fake-large" and sent.get("max_tokens") == 100 and sent.get("messages", [{}])[-1] == {"role": "user", "content": "hello"}, last)
        r = jline(pipe_request(pipe3, ask_line("[[ctrl]]")))
        t = r.get("text", "")
        row("hygiene: no escape, no BEL, no carriage return, no byte above 126 comes back; curly quotes and the dash are plain; the rest is counted as replaced",
            r.get("t") == "ok" and all(ord(ch) < 127 and (ch in "\n\t" or ord(ch) >= 32) for ch in t) and '"quoted" - dash' in t and r.get("replaced", 0) >= 5, r)
        before = fm.count.get("err429", 0)
        r = jline(pipe_request(pipe3, ask_line("[[err429]]")))
        row("ONE retry on 429: the second answer is taken", r.get("t") == "ok" and fm.count.get("err429", 0) - before == 2, (r, fm.count))
        r = jline(pipe_request(pipe3, ask_line("[[redirect]]")))
        row("a redirect is refused, never followed", r.get("code") == "refused" and "redirect, which is not followed" in r.get("msg", ""), r)
        r = jline(pipe_request(pipe3, ask_line("[[big]]")))
        row("an answer over the reply limit (300,000 characters against 65536) is refused, not cut", r.get("code") == "toobig" and r.get("msg") == "the reply is over 65536 bytes", r)
        r = jline(pipe_request(pipe3, ask_line("[[shape]]")))
        row("an answer of a shape the helper does not know is badreply", r.get("code") == "badreply", r)
        conf(fm.port, with_ca=False)
        n0 = len(fm.log)
        r = jline(pipe_request(pipe3, ask_line("hello")))
        row("WITHOUT the administrator's CA file the certificate is refused (the Windows store does not hold the test CA), and no request reached the provider",
            r.get("code") == "net" and r.get("msg") == "the provider's certificate was not accepted" and len(fm.log) == n0, r)
        conf(fw.port)
        r = jline(pipe_request(pipe3, ask_line("hello")))
        row("a certificate the CA signed for ANOTHER host name is refused", r.get("code") == "net" and r.get("msg") == "the provider's certificate was not accepted" and not fw.log, r)
    finally:
        stop(proc)
        fm.stop()
        fw.stop()


# ---------------------------------------------------------------------------------------------------- the mutants

# (file, what it takes out, old text, new text).  The old text must be in the file exactly once.
MUTANTS = [
    ("sdai_main.c", "the pipe is made without FILE_FLAG_FIRST_PIPE_INSTANCE", "PIPE_ACCESS_DUPLEX | (first ? FILE_FLAG_FIRST_PIPE_INSTANCE : 0)", "PIPE_ACCESS_DUPLEX"),
    ("sdai_win.c", "private_file accepts any access list", "    if (!EqualSid(s, me) && !EqualSid(s, (PSID)system))\n      ok = 0;\n", ""),
    ("sdai_main.c", "the key is written in clear", "  if (!dpapi((const BYTE*)key, (DWORD)strlen(key), entropy, 1, &blob, &bn))",
     "  blob = (BYTE*)_strdup(key);\n  bn = (DWORD)strlen(key);\n  if (0)"),
    ("sdai_main.c", "the entropy does not name the provider", '{ snprintf(out, n, "sd-ai key %s", name); }', '{ (void)name; snprintf(out, n, "sd-ai key"); }'),
    ("sdai_main.c", "the pipe grants Administrators everything", 'snprintf(t, sizeof t, "(A;;0x%08X;;;BA)", PIPE_CLIENT_MASK);', 'snprintf(t, sizeof t, "(A;;GA;;;BA)");'),
    ("sdai_main.c", "an unknown caller may change settings", '    if (c == NULL || !is_admin(c)) {\n      reply_err(r, "noadmin", "only the administrator may change the AI settings");',
     '    if (0) {\n      reply_err(r, "noadmin", "only the administrator may change the AI settings");'),
    ("sdai_win.c", "the gate fails open on a group that cannot be read", "      if (buf != NULL)\n        NetApiBufferFree(buf);\n      return 0;", "      if (buf != NULL)\n        NetApiBufferFree(buf);\n      return 1;"),
    ("sdai_ctl.c", "the client writes its lines to standard error", "  HANDLE h = GetStdHandle(STD_OUTPUT_HANDLE);\n  DWORD w;\n  size_t n = strlen(s);",
     "  HANDLE h = GetStdHandle(STD_ERROR_HANDLE);\n  DWORD w;\n  size_t n = strlen(s);"),
    ("sdai_ctl.c", "--handover leaves the file", "  DeleteFileW(w);\n  free(w);\n  return k.p;", "  free(w);\n  return k.p;"),
    ("sdai_ctl.c", "the client trusts any pipe's owner", "if ((check_owner && !owned_by_service(h))", "if ((0)"),
    ("sdai_https.c", "the certificate is not verified", "SSL_CTX_set_verify(ctx, SSL_VERIFY_PEER, NULL);", "SSL_CTX_set_verify(ctx, SSL_VERIFY_NONE, NULL);"),
    ("sdai_https.c", "the host name is not checked", "if (!SSL_set1_host(ssl, host) || !SSL_set_tlsext_host_name(ssl, host)) {", "if (!SSL_set_tlsext_host_name(ssl, host)) {"),
    ("sdai_main.c", "the answer is not cleaned", "    hygiene(text.p, text.n, &clean, &replaced);\n", "    clean = text;\n    replaced = 0;\n"),
    ("sdai_main.c", "no retry", "for (attempt = 1; attempt <= 2; attempt++) {", "for (attempt = 1; attempt <= 1; attempt++) {"),
    ("sdai_main.c", "the status line is written with other separators", '  sb_key(out, &first, "t");\n  sb_jstrz(out, "status");', '  sb_puts(out, "\\"t\\":\\"status\\"");\n  first = 0;'),
]


def digest(p):
    with open(p, "rb") as f:
        return hashlib.sha256(f.read()).hexdigest()


def one_run(src, fake):
    global passed, failed
    passed = failed = 0
    # not mkdtemp: its names may hold _, and the ca-file setting takes letters, digits and . / + - only (the helper's plain_path)
    tmp = os.path.join(tempfile.gettempdir(), "sdai-units-%d-%d" % (os.getpid(), int(time.time() * 1000) % 10 ** 9))
    os.makedirs(tmp)
    try:
        exe, out = build(src, tmp)
        if exe is None:
            row("the test build of the helper compiles", False, out[-600:])
            return failed
        run(exe, tmp, fake)
    finally:
        subprocess.run(["icacls", tmp, "/reset", "/T", "/Q"], capture_output=True)
        shutil.rmtree(tmp, ignore_errors=True)
    return failed


def selftest(fake, first):
    files = sorted(glob.glob(os.path.join(AIDIR, "*")))
    before = {p: digest(p) for p in files}
    missed = 0
    for n, (name, what, old, new) in enumerate(MUTANTS, 1):
        if n < first:
            continue
        with open(os.path.join(AIDIR, name), encoding="ascii") as f:
            text = f.read()
        if text.count(old) != 1:
            say("MUTANT %d (%s): its text is in %s %d times, not once - the self-test is stale" % (n, what, name, text.count(old)))
            missed += 1
            continue
        d = tempfile.mkdtemp(prefix="sdai_mutant_")
        try:
            for p in files:
                shutil.copyfile(p, os.path.join(d, os.path.basename(p)))
            with open(os.path.join(d, name), "w", encoding="ascii", newline="") as f:
                f.write(text.replace(old, new))
            import contextlib
            import io
            with contextlib.redirect_stdout(io.StringIO()):
                red = one_run(d, fake)
        finally:
            shutil.rmtree(d, ignore_errors=True)
        say("MUTANT %d (%s): %s" % (n, what, "caught (%d red)" % red if red else "MISSED"))
        missed += 0 if red else 1
    after = {p: digest(p) for p in files}
    if before != after:
        say("THE LIVE SOURCES CHANGED DURING THE SELF-TEST")
        return 1
    say("selftest: %d mutants, %d missed; the live sources are unchanged (SHA-256)" % (len(MUTANTS), missed))
    return 1 if missed else 0


def main():
    if os.name != "nt":
        say("test-aihelper-units: Windows only")
        return 2
    if not os.path.isfile(GCC) or not glob.glob(os.path.join(UCRT_BIN, "..", "lib", "libssl.a")):
        say("test-aihelper-units: no UCRT64 gcc or static OpenSSL at %s - it builds the helper the way the Makefile does" % UCRT_BIN)
        return 2
    for p in (AIDIR, PROVIDERS):
        if not os.path.exists(p):
            say("test-aihelper-units: %s is missing" % p)
            return 2
    try:
        fake = load_fake()
        if fake.openssl_path() is None:
            say("  (no openssl command line: the call rows will fail)")
    except (OSError, ImportError, SyntaxError) as e:
        say("  test-fakemodel.py could not be loaded: %s" % e)
        fake = None
    if "--selftest" in sys.argv:
        first = 1
        for a in sys.argv:
            if a.startswith("--from="):
                first = int(a[len("--from="):])
        return selftest(fake, first)
    say("test-aihelper-units: building %s with %s (-DSDAI_TESTS), running it unelevated" % (AIDIR, GCC))
    bad = one_run(AIDIR, fake)
    say("\n%d passed, %d failed" % (passed, bad))
    if passed == 0:
        say("NOTHING WAS MEASURED")
        return 1
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
