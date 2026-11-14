#!/usr/bin/env python3
#
# test-ai-units.py - the AI integration read off its source as TEXT (from Linux b1d496df, S.69 step 2; RELEASE_1.1 246).  Free: no sd, no install, no elevation.
#
#   python C:\Users\Don\Projects\SDCore4Windows\sdb_ai\sd64\gplbld\test-ai-units.py [--selftest [--from=N]]
#
# What a behaviour test cannot say: that a rule is still WRITTEN where it must be.  Exit 0 every row passed, 1 a row failed.   --selftest   each MUTANT (a rule
# taken out of a copy of the text, in memory) must turn a row red; --from=N runs the mutants from number N on.  test-aihelper-units.py RUNS the Windows parts.
#
# 13 Nov 26 Windows port - THE HELPER IS NATIVE C (the owner's ruling that day: "python not being an integral part of windows argues for the c helper"): the rows that
# read the Python helper gplbld/sd-ai, its client, sd-ai-ctl.ps1 and sd-ai-python.ps1 read gplsrc/sdai/*.c instead (shipped(): comments and the -DSDAI_TESTS blocks out),
# every rule kept; new rows for the Makefile target, the files gone, 12934 gone, the trust store, the retry and the 4 MB cap, and no USER32 / SHELL32; mutants follow.
# 13 Nov 26 Windows port - from Linux b1d496df.  Groups A, C, D, E and F are Linux's rows with the Windows facts (message ids + 1005 / + 1000, SDSYS, the pipe for the
# socket, DPAPI and the private access list for the 0600 key file, PowerShell for the shell, the client's wrapper and its --handover).  GROUP B is Windows' own:
# Linux's installer, remover, sd-elevate and systemd units have no counterpart here; their place is taken by install-aihelper.ps1 (the service, its account, its
# hardening, the state directory), sd.iss (after the Python step; removed at uninstall; the group deleted), stage.py (the program folder), sync-route-groups.ps1
# (the group, empty) and set.ai's Windows client rules.  GROUP W is new: the transport (win32ai.c), the pipe and caller rules of the helper, and DPAPI.
#
# GROUP A, the helper: it never turns certificate checking off, names no way to (no CERT_NONE, no verify=False, no unverified context, no insecure flag),
# checks the host name, accepts https URLs only, starts no program but itself for one request (the service loop), never prints to stdout, gives the gate group
# sdaiusers and asks the gate BEFORE the settings are read, keeps the key out of its one log line, writes no audit lines (SD does), lets only the administrator
# change a setting, and the shipped providers table is https only, has exactly the four providers, and leaves the key out.
# GROUP C, the kernel calls and the ai verb (Linux's, renumbered), with the pipe for the socket.
# GROUP D, the AI choice page (tool.ai), Linux's, with PowerShell for the hand-over directory.  E: a follow-up's history (op_ai.c).  F: S.170's one setup dialog.
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SD64 = os.path.dirname(HERE)
BP = os.path.join(SD64, "sdsys", "gpl.bp")
AIDIR = os.path.join(SD64, "gplsrc", "sdai")
FILES = {
    "main": os.path.join(AIDIR, "sdai_main.c"),
    "win": os.path.join(AIDIR, "sdai_win.c"),
    "https": os.path.join(AIDIR, "sdai_https.c"),
    "json": os.path.join(AIDIR, "sdai_json.c"),
    "ctl": os.path.join(AIDIR, "sdai_ctl.c"),
    "makefile": os.path.join(SD64, "Makefile"),
    "providers": os.path.join(HERE, "ai-providers"),
    "context": os.path.join(HERE, "ai-context"),
    "install": os.path.join(HERE, "install-aihelper.ps1"),
    "iss": os.path.join(HERE, "sd.iss"),
    "stage": os.path.join(HERE, "stage.py"),
    "groups": os.path.join(HERE, "sync-route-groups.ps1"),
    "attach": os.path.join(HERE, "attach-account.ps1"),
    "modifya": os.path.join(BP, "modifya"),
    "createa": os.path.join(BP, "createa"),
    "create_account": os.path.join(BP, "create_account"),
    "acc_os_info": os.path.join(BP, "acc_os_info"),
    "restorea": os.path.join(BP, "restorea"),
    "setai": os.path.join(BP, "setai"),
    "createacc.h": os.path.join(SD64, "sdsys", "syscom", "createacc.h"),
    "voc_template": os.path.join(SD64, "sdsys", "voc_template", "set.ai"),
    "op_ai": os.path.join(SD64, "gplsrc", "op_ai.c"),
    "win32ai": os.path.join(SD64, "gplsrc", "win32ai.c"),
    "keys.h": os.path.join(SD64, "gplsrc", "keys.h"),
    "int$keys.h": os.path.join(BP, "int$keys.h"),
    "op_kernel": os.path.join(SD64, "gplsrc", "op_kernel.c"),
    "sd.h": os.path.join(SD64, "gplsrc", "sd.h"),
    "gpl.src": os.path.join(SD64, "gpl.src"),
    "ai": os.path.join(BP, "ai"),
    "voc_ai": os.path.join(SD64, "sdsys", "voc_template", "ai"),
    "newvoc_ai": os.path.join(SD64, "sdsys", "newvoc", "ai"),
    "m12628": os.path.join(SD64, "sdsys", "messages", "12628"),
    "m12630": os.path.join(SD64, "sdsys", "messages", "12630"),
    "tool_ai": os.path.join(BP, "tool_ai"),
    "tk_runx": os.path.join(BP, "tk_runx"),
    "tk_gate_info": os.path.join(BP, "tk_gate_info"),
    "voc_tool_ai": os.path.join(SD64, "sdsys", "voc_template", "tool.ai"),
    "h_prov": os.path.join(SD64, "sdsys", "helptext", "tool.ai.providers"),
    "h_acc": os.path.join(SD64, "sdsys", "helptext", "tool.ai.accounts"),
}
MESSAGES = os.path.join(SD64, "sdsys", "messages")
passed = failed = 0


def row(name, ok, detail=""):
    global passed, failed
    if ok:
        passed += 1
        print("  [PASS] " + name)
    else:
        failed += 1
        print("  [FAIL] " + name + ("   <- " + detail if detail else ""))


def code_only(text):
    """The text with comments and docstrings taken out, so a rule named in a comment does not count as code."""
    text = re.sub(r'"""(?:.|\n)*?"""', '""', text)
    return "\n".join(re.sub(r"(^|\s)#.*$", "", l) for l in text.split("\n"))


def ps_only(text):
    """PowerShell without its # comment lines and trailing # comments."""
    return "\n".join(re.sub(r"(^|\s)#.*$", "", l) for l in text.split("\n"))


def bas(text):
    """A BASIC source without its comment lines and the ;* comments after a statement."""
    out = []
    for l in text.split("\n"):
        if l.lstrip().startswith("*"):
            continue
        out.append(re.sub(r"\s;\*.*$", "", l))
    return "\n".join(out)


def between(text, a, b):
    i = text.find(a)
    if i < 0:
        return ""
    j = text.find(b, i + len(a))
    return text[i:j] if j > 0 else text[i:]


def ordered(text, *parts):
    pos = -1
    for p in parts:
        i = text.find(p, pos + 1)
        if i < 0:
            return False
        pos = i
    return True


def c_only(text):
    """C source without its comments."""
    text = re.sub(r"/\*(?:.|\n)*?\*/", " ", text)
    return re.sub(r"//[^\n]*", "", text)


def c_strip(text):
    """C source without its comments, reading string and character literals as such (c_only would take the // of "https://" for a comment)."""
    out = []
    i, n = 0, len(text)
    while i < n:
        ch = text[i]
        if ch in "\"'":
            j = i + 1
            while j < n and text[j] != ch:
                j += 2 if text[j] == "\\" else 1
            out.append(text[i:j + 1])
            i = j + 1
        elif text.startswith("/*", i):
            j = text.find("*/", i + 2)
            out.append(" ")
            i = n if j < 0 else j + 2
        elif text.startswith("//", i):
            j = text.find("\n", i)
            i = n if j < 0 else j
        else:
            out.append(ch)
            i += 1
    return "".join(out)


def shipped(text):
    """C source as the Makefile builds it: no comments, and no #ifdef SDAI_TESTS block (the test build's hooks, test-aihelper-units.py's -DSDAI_TESTS)."""
    return re.sub(r"#ifdef SDAI_TESTS\b(?:.|\n)*?#endif", " ", c_strip(text))


def helper(t):
    """The helper as shipped: its four C files (the client, sdai_ctl.c, is t["ctl"])."""
    return "\n".join(shipped(t[k]) for k in ("main", "win", "https", "json"))


def func(text, head):
    """The body of the C function whose definition starts with head, to the next function at column 0."""
    i = text.find(head)
    if i < 0:
        return ""
    m = re.search(r"\n(static |int |void |jval\* |HANDLE |wchar_t\* |char\* )", text[i + len(head):])
    return text[i:i + len(head) + m.start()] if m else text[i:]


def check_a(t):
    c = helper(t)
    hs = shipped(t["https"])
    row("no way to turn certificate checking off: no SSL_VERIFY_NONE, no verify callback, no 'insecure' anywhere in the helper", not re.search(r"SSL_VERIFY_NONE|set_verify_callback|insecure", c, re.I)
        and c.count("SSL_CTX_set_verify(") == 1, "")
    row("the TLS context requires the provider's certificate (SSL_VERIFY_PEER), checks the host name (SSL_set1_host, or the address for an IP), sends SNI and is not older than TLS 1.2",
        "SSL_CTX_set_verify(ctx, SSL_VERIFY_PEER, NULL);" in hs and "SSL_CTX_set_min_proto_version(ctx, TLS1_2_VERSION)" in hs and "!SSL_set1_host(ssl, host) || !SSL_set_tlsext_host_name(ssl, host)" in hs
        and "X509_VERIFY_PARAM_set1_ip_asc(vp, host)" in hs, "")
    up = func(shipped(t["main"]), "static int url_parse(")
    row("the URL a request goes to must be https: url_parse refuses anything not starting https://, and its path has no query string and no % escape", 'if (strncmp(u, "https://", 8) != 0)\n    return 0;' in up
        and 'return chars_in(p, "._~/+,:-");' in up and "http://" not in c, "")
    row("(Windows) it starts no program but ITSELF for one request (the service loop): one CreateProcessW, of this program with --one; no system, popen, ShellExecute, WinExec",
        c.count("CreateProcessW(") == 1 and "CreateProcessW(self, wcmd," in c and '"\\"%s\\" --one --state"' in c and not re.search(r"\bsystem\s*\(|_?popen\s*\(|ShellExecute|WinExec|\bexec[lv]p?\s*\(", c), "")
    row("it never prints: no printf, puts or stdout in the shipped helper; the one reply goes to the connection handed to serve(), the standard output of --one",
        not re.search(r"\bprintf\s*\(|\bputs\s*\(|\bstdout\b|fwrite\s*\(", c) and c.count("STD_OUTPUT_HANDLE") == 1
        and "return serve(GetStdHandle(STD_INPUT_HANDLE), GetStdHandle(STD_OUTPUT_HANDLE));" in c, "")
    row("the gate group is sdaiusers and the administrator account is SDSYS; the test build's gate (SD_AI_TEST_GATE) is not in the shipped helper",
        '#define GATE_GROUP L"sdaiusers"' in c and '#define ADMIN_USER L"SDSYS"' in c and "SD_AI_TEST_GATE" not in c and "--test-key" not in c and "SD_AI_TEST_GATE" in t["win"], "")
    hall = func(shipped(t["main"]), "static void handle(")
    mb = between(hall, 'if (strcmp(op, "models") == 0) {', 'if (strcmp(op, "set") == 0 ||')
    row("(S.170) in handle() the models request is the administrator's: is_admin is asked BEFORE the settings or the key are read, a caller who is not gets noadmin, and the list is asked last",
        ordered(mb, "if (c == NULL || !is_admin(c)) {", '"noadmin", "only the administrator may ask for the list of models"', "conf_and_table(&conf)", "read_key(pname, &key)",
                "list_models(&conf, pname, &p, key, lim, &ids, &nids)"), "")
    h = hall[hall.find('if (strcmp(op, "set") == 0 ||'):]
    sv = func(shipped(t["main"]), "static int serve(")
    row("in handle() the gate is asked BEFORE the settings are read (may_ask comes before conf_and_table); the caller is read from the pipe in serve() once, from nothing the caller wrote",
        0 <= h.find("if (!may_ask(c)) {") < h.find("conf_and_table(&conf)") and c.count("caller_from_pipe(") == 2 and "have_caller = caller_from_pipe(hin, &c);" in sv, "")
    row("may_ask (S.163, owner Q6): SDSYS OR a member of the gate group, and nobody else (another Windows administrator needs the gate); an unknown caller is never let through",
        "int may_ask(const caller_t* c) { return c != NULL && (is_sdsys(c) || in_group(c->psid, gate_group())); }" in c, "")
    row("is_admin (owner Q6): SDSYS, or an ELEVATED caller with Administrators enabled - the settings only", "int is_admin(const caller_t* c) { return c != NULL && (is_sdsys(c) || (c->elevated && c->admins)); }" in c, "")
    row("in handle() the key is read after the model and before the request is checked, the limits are counted before the call, and the call is last",
        ordered(h, "sel = selected(&conf, &name, &p, &model);", "read_key(name, &key)", 'json_get(req, "prompt")', "counters(c->sid, lim, 0, 1)", "ask(&conf, &p, model, key,"), "")
    row("in handle() set, keyset and keyclear reach admin_op only for the administrator: is_admin is asked first, and a caller who is not gets noadmin",
        ordered(h, 'if (strcmp(op, "set") == 0 || strcmp(op, "keyset") == 0 || strcmp(op, "keyclear") == 0) {', "if (c == NULL || !is_admin(c)) {",
                '"noadmin", "only the administrator may change the AI settings"', "admin_op(req, &js)") and c.count("admin_op(req, &js)") == 1, "")
    lg = func(shipped(t["main"]), "static void log_line(")
    fmt = re.search(r'snprintf\(line, sizeof line, "([^"]*)", ([^;]*)\);', lg)
    row("the one log line names the caller (sid), the provider, the status and the sizes and no text or key", bool(fmt) and fmt.group(1) == "%s sd-ai: sid=%s provider=%s status=%s in=%s out=%s\\n"
        and fmt.group(2) == 'ts, c ? c->sid : "None", r->prov, r->status, r->in, r->out', repr(fmt.groups() if fmt else None))
    row("it writes no audit trail: no 'audit' and no K$AUDIT in the helper (SD writes the line BEFORE it asks)", "audit" not in c.lower(), "")
    rk = func(shipped(t["main"]), "static int read_key(")
    pf = func(shipped(t["win"]), "int private_file(")
    row("(Windows) the key file must be private BEFORE it is read: private_file (a plain file, no reparse point, an access list of this account and SYSTEM only) comes before the read; a "
        "file that is not is nokey", ordered(rk, "if (!private_file(path))", '"the key file is not private"', "read_file(path, 65536, &blob, &n)", "dpapi((BYTE*)blob, (DWORD)n, entropy, 0, &raw, &rn)")
        and "if (!path_plain_file(path) ||" in pf and "FILE_ATTRIBUTE_REPARSE_POINT" in c, "")
    row("a redirect is never followed: the HTTP code never reads a Location header, and a 3xx is refused", "location" not in hs.lower() and "redirect, which is not followed" in c, "")
    row("the reply is cut to ASCII by hygiene() before it is returned, and an oversize reply is an error, not a cut", ordered(h, "hygiene(text.p, text.n, &clean, &replaced);", '"the reply is over %lld bytes"'), "")
    ad = func(shipped(t["main"]), "static int admin_op_locked(")
    row("admin_op checks the whole result before it writes (selected, every limit) and write_key/write_conf replace atomically; a key reply never holds the key",
        ordered(ad, "if (selected(&nw, &n, &p, &m) < 0)", "if (all_limits(&nw, lim) < 0)", "if (write_conf(&nw) < 0)")
        and "return replace_file(tmp, path);" in c and 'replace_file(tmp, state_path("keys", name))' in c and 'sb_puts(out, "{\\"t\\": \\"ok\\", \\"key\\": \\"set\\"}");' in ad
        and 'json_get(req, "key")' in ad and "echo" not in ad, "")
    p = t["providers"]
    secs = re.findall(r"^\[([a-z]+)\]$", p, re.M)
    row("the shipped providers table has exactly anthropic, openai, google and deepseek", secs == ["anthropic", "openai", "google", "deepseek"], repr(secs))
    urls = re.findall(r"^url=(.*)$", p, re.M)
    row("every shipped URL is https and names a host", len(urls) == 4 and all(re.match(r"^https://[a-z.]+/", u) for u in urls), repr(urls))
    models = re.findall(r"^model=(.*)$", p, re.M)
    row("the shipped table holds a default model for each provider (a plain model name) and no key (the person supplies the key; the model may be changed)",
        len(models) == 4 and all(re.match(r"^[A-Za-z0-9][A-Za-z0-9._:/@+-]{0,99}$", m) for m in models) and not re.search(r"^key", p, re.M | re.I), repr(models))
    k = shipped(t["ctl"])
    kb = between(k, 'strcmp(cmd, "key") == 0 && nr == 1', "return usage();")
    rc = func(k, "static char* read_key_console(")
    row("the client never takes a key as an argument: in the key branch the key comes from the console (echo off, then restored) or standard input only (rest holds the provider and nothing "
        "else), and it is never printed", "key = read_key_console(rest[0]);" in kb and "rest[1]" not in kb and "argv" not in kb
        and ordered(rc, "GetConsoleMode(in, &mode)", "& ~ENABLE_ECHO_INPUT", "ReadConsoleW(", "SetConsoleMode(in, mode);") and not re.search(r"\bsayf?\((?:[^;]*,\s*)?key\s*[,)]", k)
        and "if (!is_provider(rest[0]))" in kb, "")
    hb = between(k, 'strcmp(cmd, "key") == 0 && nr == 3 && strcmp(rest[1], "--handover") == 0', 'strcmp(cmd, "key") == 0 && nr == 1')
    hk = func(k, "static char* handover_key(")
    row("(Windows) the client's key --handover: the key is the FILE's (named by the third word), read and removed BEFORE the provider is even checked, and never printed",
        ordered(hb, "key = handover_key(rest[2]);", "if (!is_provider(rest[0]))", '"keyset"') and ordered(hk, "read_file(w, 65536, &data, &n)", "DeleteFileW(w);")
        and hk.count("return") == 1, "")
    ct = t["context"]
    row("(Windows) the shipped standing text names SD Core for Windows, its own paths and documents, no Linux path, and is printable ASCII within 4000 characters",
        ct.startswith("About this system: SD Core for Windows") and "/usr/local" not in ct and "Linux" not in ct and "SDCore4WindowsDocs" in ct and len(ct) <= 4001
        and re.match(r"^[\x20-\x7e\n]*$", ct) is not None, "")


def check_b(t):
    ins = ps_only(t["install"])
    row("(Windows) install-aihelper.ps1 makes the service sd-ai as the virtual account NT SERVICE\\sd-ai (owner Q3), start auto, restricted SID, one privilege (SeChangeNotifyPrivilege), "
        "and refuses an unelevated run",
        "$SvcAccount = 'NT SERVICE\\sd-ai'" in ins and "& $sc config $SvcName obj= $SvcAccount" in ins and "-StartupType Automatic" in ins and "& $sc sidtype $SvcName restricted" in ins
        and "& $sc privs $SvcName SeChangeNotifyPrivilege" in ins and ordered(ins, "IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)", "exit 2", "New-Service"), "")
    row("...the service runs the native helper sd-ai.exe in the program folder with --service, and nothing looks for Python (the owner, 13 Nov 2026: the C helper)",
        "$helper = Join-Path $lib 'sd-ai.exe'" in ins and "$bin = '\"' + $helper + '\" --service'" in ins and "python" not in ins.lower() and "exit 3" not in ins
        and "foreach ($f in @('sd-ai.exe', 'ai-providers', 'ai-context')) {" in ins, "")
    row("...the keys directory is SYSTEM's and the service's ONLY (no Administrators entry), the state directory adds Administrators READ; inheritance cut on both; ai.conf is not written (none is AI off)",
        "& icacls $keys /inheritance:r /grant:r '*S-1-5-18:(OI)(CI)F' \"${SvcAccount}:(OI)(CI)M\" | Out-Null" in ins
        and "& icacls $state /inheritance:r /grant:r '*S-1-5-18:(OI)(CI)F' \"${SvcAccount}:(OI)(CI)M\" '*S-1-5-32-544:(OI)(CI)RX' | Out-Null" in ins and "ai.conf" not in ins.replace("ai.conf is NOT written", ""), "")
    row("...nothing is deleted from the state directory (an upgrade keeps settings and keys, as Linux keeps /var/lib/sd-ai), and what was made is read back and printed (account, command, pipe, access lists)",
        not re.search(r"Remove-Item[^\n]*\$(state|keys|cnt)\b", ins) and "Get-CimInstance -ClassName Win32_Service" in ins and "$w.StartName -eq $SvcAccount" in ins and "Test-AiPipe" in ins, "")
    iss = t["iss"]
    ia = between(iss, "function InstallAiHelper: String;", "procedure CurStepChanged")
    row("(Windows) sd.iss sets up the helper at ssPostInstall (from [Code]), reports any code but 0 as a failure (no Python excuse: exit 3 is gone), removes the service at uninstall and deletes the "
        "group sdaiusers with the others",
        iss.count("AiMsg := InstallAiHelper;") == 1 and "AiMsg +" in iss and "\\install-aihelper.ps1\"\" -Remove\"" in iss
        and "Exec(Net, 'localgroup sdaiusers /delete'," in iss and "  if Code = 0 then\n    Exit;" in ia and "Code = 3" not in ia, "")
    st = t["stage"]
    row("(Windows) stage.py ships bin\\sd-ai.exe and the two data files to ProgramFiles\\lib\\sd-ai (a missing one fails the build), refuses an msys-, python, USER32 or SHELL32 import in it, "
        "and ships install-aihelper.ps1 to {app}",
        "AI_HELPER_BIN = 'sd-ai.exe'" in st and "AI_HELPER_FILES = ['ai-providers', 'ai-context']" in st and "ai_dst = os.path.join(pf, 'lib', 'sd-ai')" in st
        and "for src in [os.path.join('bin', AI_HELPER_BIN)] + [os.path.join(here, n) for n in AI_HELPER_FILES]:" in st
        and "'sd-ai.exe':      ['msys-', 'python', 'user32', 'shell32']," in st
        and "raise SystemExit('missing %s - the AI helper needs it' % src)" in st and "'install-aihelper.ps1'," in st, "")
    mk = "\n".join(l for l in t["makefile"].split("\n") if not l.lstrip().startswith("#"))
    rec = between(mk, "\nsd-ai:\n", "\n\n")
    row("(Windows) the Makefile builds sd-ai.exe as sd's prerequisite with the UCRT64 compiler and the STATIC OpenSSL, from every C file of gplsrc/sdai, and never with -DSDAI_TESTS",
        re.search(r"^sd: \$\(SDOBJS\)[^\n]*\bsd-ai\b", mk, re.M) is not None and "$(UCRT_CC)" in rec and "-Wl,-Bstatic -lssl -lcrypto -Wl,-Bdynamic" in rec
        and "$(wildcard $(AIDIR)/*.c)" in rec and "-o $(GPLBIN)sd-ai.exe" in rec and "-municode" in rec and "SDAI_TESTS" not in mk, rec[:200])
    gone = [n for n in ("sd-ai", "sd-ai-ctl", "sd-ai-ctl.ps1", "sd-ai-python.ps1") if os.path.exists(os.path.join(HERE, n))]
    row("(Windows) the Python helper, its client and their two PowerShell finders are gone from gplbld", not gone, repr(gone))
    g = ps_only(t["groups"])
    row("(Windows) sync-route-groups.ps1 makes sdaiusers with the other gate groups and adds nobody to it", "$AiGroup   = 'sdaiusers'" in g and "    Ensure-Group $AiGroup $AiComment" in g
        and not re.search(r"Add-LocalGroupMember[^\n]*\$AiGroup|sdaiusers[^\n]*/add", g), "")
    a = ps_only(t["attach"])
    row("(Windows) the installer's 'open every access gate' answer gives ai-on and reads sdaiusers back, as Linux's does (owner on Linux: every gate)", "'sdaiusers' = 'ai-on'" in a and "ai-on" in a, "")
    h, cr, ca2, ai, rs, hd = (t[k] for k in ("modifya", "createa", "create_account", "acc_os_info", "restorea", "createacc.h"))
    row("createacc.h defines CA$AI as 41, once; create.account's AI-ON sets it and nothing else does; the audit gates= list names it", re.search(r"\$define\s+CA\$AI\s+41\b", hd) is not None
        and len(re.findall(r"\$define\s+\S+\s+41\b", hd)) == 1 and re.search(r"case upcase\(token\) = 'AI-ON'\s*\n\s*settings<CA\$AI> = 1\s*\n", cr) is not None and len(re.findall(r"(?<!if )settings<CA\$AI>\s*=", cr)) == 1
        and "{ai-on}" in cr and "if settings<CA$AI> = 1 then gates<-1> = 'ai-on'" in cr, "")
    cab = bas(ca2)
    row("!create_account: ai.want is exactly 1; the group sdaiusers is looked for BEFORE the Windows user is made and joined after it, a group or other account is refused as for FILES-ON, "
        "and the state line 12611 is read off the group",
        "ai.want = (settings<CA$AI> = 1)" in cab and ordered(cab, "if ai.want then", "files.grp.name = 'sdaiusers'", "gosub check.files.group") and 'os_group("ADDMEM", "sdaiusers", acc.uname)' in cab
        and cab.count("or ai.want then") == 2 and "ai.now = is_grp_member(acc.uname, 'sdaiusers')" in cab and "sysmsg(12611, acc.name, if ai.now then 'yes' else 'no')" in cab, "")
    row("the manifest has route.ai from membership of sdaiusers, RESTORE.ACCOUNT reads it, clears it for each section and hands it on as CA$AI only when it is 1",
        ordered(ai, "is_grp_member(uname, 'sdaiusers')", "'route.files.admin: '", "info<-1> = 'route.ai: ' : aiuse") and re.search(r"= 'route\.ai'\s*; m\.route\.ai = kv", rs) is not None
        and "m.route.ai = ''" in rs and "if m.route.ai = '1' then settings<CA$AI> = 1" in rs and bas(rs).count("CA$AI") == 1, "")
    sa = bas(t["setai"])
    row("set.ai asks for the administrator FIRST (before any word is read or any command built), then checks every word against the allowed characters, then builds the command", ordered(sa, "kernel(K$ADMINISTRATOR, -1)",
        "stop sysmsg(2001)", "words = trim(@sentence)", "convert(okc, space(len(okc)), w)", "stop sysmsg(12627", "begin case") and sa.count("os.execute") == 4, "")
    hb = between(sa, "case sub = 'key' and n.words = 4 and downcase(field(words, ' ', 4)) = 'handover'", "case sub = 'key' and n.words = 4 and downcase(field(words, ' ', 4)) = 'clear'")
    row("(S.170, Windows) set.ai key p handover: the file is FIXED (the hand-over directory in the sdsys directory, not a word of the sentence); the client is given its path (--handover), the "
        "file is removed after the client ran and on a refused provider, and the key is read back, not assumed; SD never reads the file itself",
        ordered(hb, "hand.f = @sdsys : @ds : '$aikey' : @ds : 'key'", "gosub drop.handover", "stop sysmsg(12615",
                "os.execute \"& '\" : ctl : \"' 'key' '\" : prov : \"' '--handover' '\" : hand.f : \"'\" capturing out", "gosub drop.handover", "gosub check.key", "if not(key.found) then")
        and "drop.handover: os.execute \"Remove-Item -LiteralPath '\" : hand.f : \"' -Force -ErrorAction SilentlyContinue\" return" in re.sub(r"\s+", " ", sa)
        and not re.search(r"\b(openseq|readseq|readblk|osread)\b", sa), "")
    safe = set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._:/@+,-")
    row("set.ai quotes every word it passes to the client in single quotes and allows only letters, digits and . _ : / @ + , - (no quote, space, $, ; or backquote)",
        set(re.search(r"okc = '([^']*)'", sa).group(1)) == safe and sa.count("qargs") >= 8
        and "qargs = \"'provider' '\"" in sa and 'os.execute "& \'" : ctl' in sa, "")
    row("set.ai key: the console is handed to the client (os.execute, no capturing, nothing redirected), the key is never in a variable of SD's, and the result is read back, not assumed",
        ordered(sa, "case sub = 'key' and n.words = 3", "os.execute \"& '\" : ctl : \"' 'key' '\" : prov : \"'\"\n", "qargs = \"'show'\"", "gosub run.ctl", "gosub check.key", "if not(key.found) then")
        and not re.search(r"\binput\b|readline", sa) and "2>&1" not in sa, "")
    rc = between(sa, "run.ctl:", "need.ok:")
    row("(Windows) run.ctl: the client is run with its words quoted and NOTHING redirected, its carriage returns are taken out, and only then is an unreachable helper judged; no Python is "
        "looked for anywhere (no nopython, no 12934: the helper is native, 13 Nov 2026)",
        ordered(rc, "os.execute \"& '\" : ctl : \"' \" : qargs capturing out", "out = convert(char(13), '', out)",
                "if trim(out) = '' or (trim(out<1>)[1, 7] # 'error: ' and (index(out, 'could not be reached', 1) or index(out, 'not found', 1)") and "nopython" not in sa and "12934" not in sa, "")
    audits = re.findall(r"kernel\(K\$AUDIT, ([^\n]*)\)", sa)
    row("every audit line of set.ai is lower case, has no key (no 'key=' and no variable named key) and names a host, never a whole URL; (S.160) the standing text's three lines carry its size or the "
        "name the wall found, never the text", len(audits) == 13 and all(a.lstrip().startswith("'set.ai ") for a in audits)
        and not any(re.search(r"key=|: key\b|curl\b|cpath\b.*curl", a) for a in audits) and not any("curl" in a for a in audits) and any("host=' : chost" in a for a in audits)
        and "'set.ai context bytes=' : len(ctext)" in audits and "'set.ai context=default'" in audits and "'set.ai context refused name=' : why" in audits
        and not any(re.search(r"\b(ctext|hx)\b", a.replace("len(ctext)", "")) for a in audits), repr(audits))
    row("(S.160) set.ai context: the hex word is checked (even length, hexadecimal, 8000 at most), decoded, every byte printable ASCII or a line feed, put to the wall's screen BEFORE the helper is asked, "
        "and a refusal stops before the client runs",
        ordered(sa, "case sub = 'context' and n.words = 3", "if len(hx) = 0 or mod(len(hx), 2) or len(hx) > 8000", "ctext = iconv(hx, 'MX0C')", "if cc # 10 and (cc < 32 or cc > 126) then stop sysmsg(15014)",
                "call $tk_aiwall('request', ctext, why)", "stop sysmsg(15013, why)", "qargs = \"'context' '\" : hx : \"'\"", "gosub run.ctl"), "")
    row("(Windows) set.ai finds its client in the program folder (K$WINPATH of /lib/sd-ai/sd-ai.exe, the helper's own program), never in the SD system directory; SD_AI_CTL overrides it for the "
        "tests only; a path holding a quote is refused",
        "if ctl = '' then ctl = kernel(K$WINPATH, '/lib/sd-ai/sd-ai.exe')" in sa and "env('SD_AI_CTL')" in sa and not re.search(r"ctl\s*=[^\n]*@sdsys", sa) and sa.count("@sdsys") == 1
        and "index(ctl, \"'\", 1)" in sa, "")
    row("set.ai is in SDSYS's VOC only: voc_template has it as a verb for $setai and newvoc has no set.ai", t["voc_template"].split("\n")[:3] == ["V", "CA", "$setai"]
        and not os.path.exists(os.path.join(SD64, "sdsys", "newvoc", "set.ai")), "")
    need = [str(n) for n in range(12611, 12628)]
    bad = []
    for n in need:
        p = os.path.join(MESSAGES, n)
        try:
            tx = open(p, encoding="latin-1").read()
        except OSError:
            bad.append(n + " missing")
            continue
        if not tx.endswith("\n") or tx.count("\n") != 1 or tx.strip() == "":
            bad.append(n + " shape")
    row("messages 12611 to 12627 exist, one line each; 12934 (\"the AI needs Python\") is gone with the Python helper", not bad and not os.path.exists(os.path.join(MESSAGES, "12934")), repr(bad))
    row("12611 is 'Account %1 has ai %2', 12614 is the usage, and 12613 does not name the program",
        open(os.path.join(MESSAGES, "12611")).read() == "Account %1 has ai %2\n" and "set.ai {" in open(os.path.join(MESSAGES, "12614")).read()
        and "sd-ai" not in open(os.path.join(MESSAGES, "12613")).read(), "")


def check_c(t):
    o = c_only(t["op_ai"])
    ks = dict(re.findall(r"#define\s+K_AI_([A-Z]+)\s+(\d+)", t["keys.h"]))
    bs = dict(re.findall(r"\$define\s+K\$AI\.([A-Z]+)\s+(\d+)", t["int$keys.h"]))
    want = {"START": "160", "POLL": "161", "CANCEL": "162", "STATUS": "163"}
    row("the four AI kernel keys are 160 to 163, the same numbers in keys.h and in int$keys.h, and no other key of either file uses one of them", ks == want and bs == want
        and len(re.findall(r"#define\s+K_\w+\s+16[0-3]\b", t["keys.h"])) == 4 and len(re.findall(r"\$define\s+K\$\S+\s+16[0-3]\b", t["int$keys.h"])) == 4, repr((ks, bs)))
    kk = c_only(t["op_kernel"])
    row("op_kernel.c sends the four keys together to k_ai(action, descr, &result) and nowhere else, and answers none of them itself; sd.h declares k_ai; gpl.src builds op_ai and win32ai",
        re.search(r"case K_AI_START:\s*case K_AI_POLL:\s*case K_AI_CANCEL:\s*case K_AI_STATUS:\s*k_ai\(action, descr, &result\);\s*break;", kk) is not None and kk.count("k_ai(") == 1
        and "nohelper" not in kk and kk.count("K_AI_") == 4
        and "void k_ai(int action, DESCRIPTOR * descr, DESCRIPTOR * result);" in t["sd.h"] and "\nop_ai\n" in t["gpl.src"] and "\nwin32ai\n" in t["gpl.src"], "")
    kf = o[o.index("void k_ai("):]
    row("k_ai refuses a caller that is not a $internal program BEFORE the action is looked at: the flag test comes first, answers ERR internal and returns, and the switch follows",
        ordered(kf, "if (!(process.program.flags & HDR_INTERNAL))", 'ai_answer("ERR", "internal", result)', "return;", "switch (action)"), "")
    st = o[o.index("Private void ai_start("):o.index("Private void ai_poll(")]
    row("ai_start: one request at a time (busy is the first test), the audit line is written BEFORE the connection is made, and once", ordered(st, "if (ai.active)", '"busy"', "audit_message(audit);", "ai_connect()")
        and st.count("audit_message(") == 1, "")
    row("the audit line is 'ai request account=%s program=%s bytes.out=%d' in lower case, from the account, the program's name and a length: the text, the prompt and the system sentence are not arguments of it",
        'snprintf(audit, sizeof(audit), "ai request account=%s program=%s bytes.out=%d", account(), pname, (int)(strlen(system) + strlen(prompt)));' in st, "")
    row("the request that can be built is an ask and nothing else: the JSON op is \"ask\" once, and keyset, keyclear and set appear nowhere in op_ai.c", st.count('\\"op\\":\\"ask\\"') == 1
        and not re.search(r'keyset|keyclear|\\"set\\"', o), "")
    row("the arguments are cut system, maxtokens, prompt: the first mark ends the system sentence, the second the number, and the prompt is the rest (a mark inside it moves no field)",
        ordered(st, "system = arg;", "maxt = p + 1;", "prompt = p + 1;", "maxtokens = atoi(maxt);"), "")
    row("a byte above 127 goes out as ? and a control character is escaped (English only; nothing but plain ASCII is sent)", re.search(r"else if \(c >= 128\) \{\s*out\[pos\+\+\] = '\?';", o) is not None
        and "c < 32 || c == 127" in o, "")
    row("A FOLLOW-UP is maxtokens VM n with n from 1 to AI_HIST_MAX (3), else ERR bad; the 2n earlier fields are cut off BEFORE the prompt, which stays last, and a missing one is ERR bad; all of it is read before the audit line",
        re.search(r"#define AI_HIST_MAX 3\b", o) is not None and ordered(st, "maxtokens = atoi(maxt);", "p = strchr(maxt, VALUE_MARK);", "nhist = atoi(p + 1);", "if (nhist < 1 || nhist > AI_HIST_MAX) {",
                                                                        '"bad"', "for (i = 0; i < 2 * nhist; i++) {", "hist[i] = prompt;", "p = strchr(prompt, FIELD_MARK);", "if (p == NULL) {", '"bad"', "prompt = p + 1;", "audit_message(audit);"), "")
    row("a follow-up's audit line counts its earlier exchanges in bytes.out and says followup=n, still never the text; they go to the helper as \"history\" of {q, a}, each escaped like the prompt",
        'snprintf(audit, sizeof(audit), "ai request account=%s program=%s bytes.out=%d followup=%d", account(), pname, (int)(strlen(system) + strlen(prompt) + hbytes), nhist);' in st
        and ordered(st, '",\\"history\\":["', '"%s{\\"q\\":"', "ai_json_string(req, pos, hist[2 * i]", '",\\"a\\":"', "ai_json_string(req, pos, hist[2 * i + 1]", "req[pos++] = ']';", '",\\"maxtokens\\":%d}\\n"')
        and "cap = (6 * (strlen(system) + strlen(prompt) + hbytes)) + 256 + (32 * nhist);" in st, "")
    w = c_only(t["win32ai"])
    row("(Windows) the kernel talks to the helper's pipe through win32ai.c and nothing else: no socket, no host name lookup, no TLS, no program started, no select() or poll() on the pipe",
        "win32_ai_open(" in o and not re.search(r"\bsocket\s*\(|AF_INET|AF_UNIX|netinet|getaddrinfo|gethostbyname|SSL_|\bsystem\s*\(|popen|\bexec[lv]|\bselect\s*\(|\bpoll\s*\(", o)
        and not re.search(r"CreateProcess|ShellExecute|WinHttp|InternetOpen|\bsocket\s*\(|cygwin_attach_handle_to_fd|\bselect\s*\(", w), "")
    row("(Windows) the pipe is \\\\.\\pipe\\sd-ai, or the SD_AI_PIPE of the session's environment (the tests) only when it is a pipe name; only the real name skips nothing (its owner is checked)",
        o.count('"\\\\\\\\.\\\\pipe\\\\sd-ai"') == 1 and o.count("getenv(") == 1 and 'getenv("SD_AI_PIPE")' in o
        and ordered(o, 'getenv("SD_AI_PIPE")', "strncasecmp(p, AI_PIPE_PREFIX, strlen(AI_PIPE_PREFIX)) == 0", "*check_owner = 0;", "*check_owner = 1;", "return AI_DEFAULT_PIPE;"), "")
    pl = o[o.index("Private void ai_poll("):o.index("Private void ai_status(")]
    row("a request ends: a 340 second deadline, a reply of at most 512 KB, and the pipe is closed by ai_reset on every end (the deadline, a reply too big twice, the answer taken, the helper hanging up)",
        re.search(r"#define AI_DEADLINE 340 ", o) is not None and re.search(r"#define AI_REPLY_MAX 524288\s*\n", o) is not None and pl.count("ai_reset();") >= 5, "")
    row("(Windows) ai_poll reads only what PeekNamedPipe says is there (win32_ai_avail before every win32_ai_read, the read no longer than that), and a broken, empty pipe is 'closed'",
        ordered(pl, "avail = win32_ai_avail(ai.slot);", "if (avail <= 0)", "if (want > avail)", "n = win32_ai_read(ai.slot, ai.buf + ai.len, want);", "if (win32_ai_avail(ai.slot) < 0) {", '"closed"'), "")
    v = bas(t["ai"])
    row("ai is an internal program catalogued as $ai", re.search(r"\$internal\s*\nprogram ai\s*\n\$catalog \$ai\b", v) is not None, "")
    row("the order in the verb: an earlier request is given up, the helper's status is read, the text is shown, the person is asked, a no stops it, and ONLY THEN is the request started (START appears once)",
        ordered(v, "kernel(K$AI.CANCEL, 0)", "kernel(K$AI.STATUS, 0)", "display sysmsg(12633", "display question", "input ans", "if ans # 'y' and ans # 'yes' then", "stop sysmsg(12635)", "kernel(K$AI.START")
        and v.count("K$AI.START") == 1 and v.count("input ") == 1, "")
    row("what is sent is the administrator's standing text (S.160), the fixed sentence and the person's text, and nothing of the account: the sentence is assigned once from a literal, the standing "
        "text comes only from the helper's status after the wall's screen, the question is unchanged, and the START argument is exactly that, the limit and the text",
        len(re.findall(r"^\s*system\.text = '[^']*'\s*$", v, re.M)) == 1 and len(re.findall(r"system\.text\s*=", v)) == 2
        and ordered(v, "ctext = st{'context'}", "call $tk_aiwall('request', ctext, why)", "stop sysmsg(15013, why)", "fixed.text = system.text",
                    "if ctext # '' then c.send = 'Standing information from the administrator of this SD system:' : char(10) : ctext", "system.text = c.send : fixed.text")
        and "reply = kernel(K$AI.START, system.text : @fm : 1024 : @fm : question)" in v and not re.search(r"question\s*=[^\n]*ctext", v), "")
    row("(Windows) the fixed sentence names SD Core for Windows", "system.text = 'You are answering a question typed at the terminal of SD Core for Windows, a multivalue database." in v, "")
    row("(S.160, S.175) SD's own text is INVISIBLE to the person asking: the preview displays the question only, never system.text, fixed.text, c.send or ctext",
        "display question" in v and not any(re.search(r"\b(system\.text|fixed\.text|c\.send|ctext)\b", l.replace("len(system.text)", ""))
                                              for l in v.split("\n") if l.strip().startswith(("display", "crt", "print"))), "")
    row("the gate, the model and the key are read from the helper's status BEFORE anything is shown: provider empty, gate false, model empty and key false each stop with their own message",
        ordered(v, "prov = st{'provider'}", "if prov = '' then", "stop sysmsg(12629)", "if not(st{'gate'}) then", "stop sysmsg(12630, @who)", "if model = '' then", "stop sysmsg(12631, prov, 'model')",
                "if not(st{'key'}) then", "stop sysmsg(12631, prov, 'key')", "display sysmsg(12633"), "")
    row("the verb only displays the answer: it starts no program and reads no file (no os.execute, execute, perform, chain, openseq, readseq, writeseq) and takes one answer of the person's",
        not re.search(r"\b(os\.execute|execute|perform|chain|openseq|readseq|writeseq|openpath)\b", v), "")
    row("ai is a verb in SDSYS's VOC and in every account's: voc_template and newvoc both name $ai", t["voc_ai"].split("\n")[:3] == ["V", "CA", "$ai"]
        and t["newvoc_ai"].startswith("Verb") and t["newvoc_ai"].split("\n")[1:3] == ["CA", "$ai"], "")
    bad = []
    for n in range(12628, 12640):
        p = os.path.join(MESSAGES, str(n))
        try:
            tx = open(p, encoding="latin-1").read()
        except OSError:
            bad.append("%d missing" % n)
            continue
        if not tx.endswith("\n") or tx.count("\n") != 1 or tx.strip() == "":
            bad.append("%d shape" % n)
    row("messages 12628 to 12639 exist, one line each", not bad, repr(bad))
    row("12628 tells the person to put text that ends with ? in quotes, and 12630 names the way to allow an account (modify.account %1 ai-on)", "in quotes if it ends with ?" in t["m12628"]
        and "modify.account %1 ai-on" in t["m12630"], "")


def sqz(text):
    return re.sub(r"\s+", " ", text).strip()


def check_d(t):
    v = sqz(bas(t["tool_ai"]))
    row("tool.ai is an internal program catalogued as $tool_ai; it opens the base for the administrator FIRST (and prints and stops on a refusal), writes its one audit line, and only then reads the helper",
        re.search(r"^\$internal\s*\nprogram \$tool_ai\s*\n\$catalog \$tool_ai\b", bas(t["tool_ai"]), re.M) is not None
        and ordered(v, "call $tk_open('tool.ai', 'admin', ctx, err) if err # '' then display err stop end", "kernel(K$AUDIT, 'tool start app=tool.ai')", "gosub read.all", "reply = kernel(K$AI.STATUS, 0)"), "")
    row("it may run SET.AI (through $tk_runx) and MODIFY.ACCOUNT (through $tk_run) and nothing else: each list is assigned once and each routine called once, with its own list",
        v.count("allow.set = 'set.ai'") == 1 and v.count("allow.acc = 'modify.account'") == 1 and v.count("call $tk_runx(allow.set, sent, out, st, err)") == 1 and v.count("call $tk_run(allow.acc, sent, out, st, err)") == 1
        and len(re.findall(r"call \$tk_runx?\((?!allow\.set|allow\.acc)", v)) == 0, "")
    row("every command is shown in the confirm box BEFORE it runs: in confirm.and.run the box comes first, a result other than run runs nothing, and both run sites follow it; no other site calls $tk_run or $tk_runx",
        ordered(v, "confirm.and.run: call $tk_confirm(sent, el, typed, res, cmsg) if res = 'run' then if use.x then call $tk_runx(", "call $tk_run(allow.acc", "end else msg = cmsg end return") and v.count("call $tk_confirm(sent, el, typed") == 1, "")
    row("(S.160) the one direct EXECUTE is SET.AI CONTEXT: the sentence is 'set.ai context ' and the text as MX0C hexadecimal (or -), after the confirm box, and before it runs the verb, the "
        "word count and a word of hexadecimal or - only are checked again",
        len(re.findall(r"(?<!os\.)\bexecute\b", v)) == 1
        and ordered(v, "do.context:", "cx.sent = 'set.ai context -'", "cx.sent = 'set.ai context ' : oconv(cx.new, 'MX0C')", "call $tk_confirm(cx.show, el, '', res, cmsg) if res # 'run' then msg = cmsg return end",
                    "if downcase(field(cx.sent, ' ', 1)) # 'set.ai' or field(cx.sent, ' ', 2) # 'context' or dcount(cx.sent, ' ') # 3 then return",
                    "if cx.word # '-' and convert('0123456789ABCDEFabcdef', '', cx.word) # '' then return", "execute cx.sent trapping aborts capturing out"), "")
    row("(S.170, Windows) the page's OS.EXECUTEs are the hand-over directory and file only: the directory made SDSYS's and SYSTEM's alone with icacls (Linux's 0700), the file removed",
        not re.search(r"\b(perform|chain)\b", v) and v.count("os.execute") == 2
        and "icacls $d /inheritance:r /grant:r 'SDSYS:(OI)(CI)F' 'SYSTEM:(OI)(CI)F'" in v and "os.execute \"Remove-Item -LiteralPath '\" : hf : \"' -Force -ErrorAction SilentlyContinue\" return" in v, "")
    k = between(v, "do.setup:", "setup.items:")
    tk = between(v, "setup.takekey:", "setup.save:")
    sv = between(v, "setup.save:", "key.word:")
    row("(S.170) S is the one setup dialog, for the fixed five providers only; K and M are gone (no do.key, no do.model, no 'k' or 'm' key)",
        k.startswith("do.setup: p = provs<pi> if index(' anthropic openai google deepseek custom ', ' ' : p : ' ', 1) = 0 then return") and "do.key:" not in v and "do.model:" not in v
        and "call $tk_keys('add', keys, 's', 'setup', 'setup', 'Provider', 1)" in v and "'k', 'key'" not in v and "'m', 'model'" not in v, k[:160])
    hk = between(v, "hand.key:", "fetch.models:")
    row("(S.170) the dialog is always the same: a MASKED Key entry (the keep-stars when a key is set), the Model LIST, Other name, Save and Cancel; the list is asked for when it opens if a key is set",
        ordered(k, "if pkey<pi> then gosub fetch.models", "gosub setup.items", "screen form title su.title", "screen entry sf, 'key' at 2 + su.lw,2 width 70 value su.kini mask maxlen 600",
                "screen list sf, 'model', su.items", "screen entry sf, 'other'", "screen button sf, 'ok', '&Save'", "screen button sf, 'cancel', sysmsg(12254)", "screen wait sf returning su.ev then")
        and not re.search(r"(?<![\w.])ev\b", k, re.I)
        and "if pkey<pi> then su.kini = su.keep" in k and k.count("screen entry") == 2, "")
    row("(S.170) the key is read only from the Key entry (kv = trim of SCREEN GET 'key'), the keep-stars and an empty entry hand nothing over, it is checked as a word of 8 to 512 characters from ! to ~ "
        "before anything is done with it, kv is cleared after the dialog, and only after the hand-over is the list asked WITH it and shown",
        ordered(tk, "screen get sf, 'key' returning kv", "kv = trim(kv)", "if kv = su.keep or kv = '' then kv = '' return", "gosub key.word", "gosub hand.key", "key.done = 1",
                "screen set sf, 'key' value su.keep", "gosub fetch.models", "gosub setup.items", "screen set sf, 'model' items su.items")
        and len(re.findall(r"\bkv\s*=\s*trim\(", v)) == 1 and "screen hide sf" in k and k.index("kv = ''") < k.rindex("screen hide sf"), "")
    row("(S.170) THE KEY GOES NOWHERE BUT THE HAND-OVER FILE: kv is written only by WRITESEQ to hf, in the directory made private first; kv is cleared on every path of hand.key; no sentence, message, "
        "audit line or display holds kv; SET.AI is told 'handover', never the key",
        ordered(hk, "hdir = @sdsys : @ds : '$aikey'", "hf = hdir : @ds : 'key'", "icacls $d /inheritance:r", "openseq hf to kf", "writeseq kv to kf", "close kf kv = ''", "call $tk_runx(allow.set, 'set.ai key ' : p : ' handover', out, st, err)",
                "os.execute \"Remove-Item -LiteralPath '\" : hf") and v.count("writeseq") == 1 and len(re.findall(r"\bkv\b", hk)) >= 3
        and not any(re.search(r"(^\s*|\bthen\s+|\belse\s+)(sent|msg|su\.say|bad|el<-1>|cmsg|hint|spec|fv(<\d+>)?)\s*:?=.*\bkv\b|(display|crt|kernel\(K\$AUDIT|\$tk_runx?\(|\$tk_confirm\(|\$tk_form\('say').*\bkv\b", ln)
                    for ln in bas(t["tool_ai"]).split("\n")), "")
    row("(S.170) Save takes the model from the LIST, or from Other name only when the list holds it (or there is no list); a Save with no key is refused; a list that has only just come is shown, not saved over",
        ordered(sv, "if not(pkey<pi>) and not(key.done) then", "screen get sf, 'other' returning ov", "gosub valid.word", "if lm.ok and lm.n > 0 then", "if lm.list<i> = ov then found = 1",
                "if not(found) then", "mv = ov", "screen get sf, 'model' returning li", "mv = lm.list<li>", "su.done = 1")
        and "gosub setup.takekey if not(su.fetched) then gosub setup.save" in k, "")
    row("the page starts no request and reads no secret: no K$AI.START and no K$AI.POLL, the only kernel AI call is K$AI.STATUS, the only file opened is the register (one OPENPATH), no key file of the "
        "helper's is named and nothing is READ by OPENSEQ (S.170: the one OPENSEQ writes the hand-over file)",
        "K$AI.START" not in v and "K$AI.POLL" not in v and "K$AI.CANCEL" not in v and v.count("K$AI.STATUS") == 1 and v.count("openpath") == 1 and "@sdsys:@ds:'accounts'" in v
        and not re.search(r"ProgramData|\\ai\\keys|keys/|readseq|readblk", v) and v.count("openseq") == 1, "")
    row("the names typed: selecting a provider asks for its name (and deselecting asks for none), turning an account's gate ON asks for the account's name (OFF none), Custom asks for 'custom' and a certificate file for 'ca'",
        "sent = 'set.ai provider none' typed = ''" in v and "sent = 'set.ai provider ' : p typed = p" in v and "end else typed = an.name lpid = sel" in v
        and "sent = 'modify.account ' : an.name : ' ' : (if on.now then 'ai-off' else 'ai-on') el = '' typed = '' if on.now then" in v
        and v.count("typed = 'custom'") == 1 and v.count("typed = 'ca'") == 1, "")
    row("every word that is typed is checked against SET.AI's own list before the sentence is built: the model (1 to 80), the four fields and the address of Custom (https:// first), the certificate file, and a limit's name and digits",
        ordered(v, "setup.save:", "vw = ov vmax = 80 gosub valid.word if not(vw.ok) then", "mv = ov") and ordered(v, "do.custom:", "vmax = 40 ; vw = v1 ; gosub valid.word", "vmax = 300 ; vw = v2 ; gosub valid.word", "v2[1, 8] # 'https://'",
        "vmax = 40 ; vw = v5 ; gosub valid.word", "vmax = 60 ; vw = v6 ; gosub valid.word", "call $tk_form('say'", "call $tk_form('close'", "sent = 'set.ai custom '") and ordered(v, "do.ca:", "vmax = 300 gosub valid.word if not(vw.ok) then", "sent = 'set.ai ca '")
        and ordered(v, "do.limit:", "locate ln in lnames<1> setting lk else", "convert('0123456789', space(10), lv)) # ''", "sent = 'set.ai limit '"), "")
    okc_page = re.search(r"\bokc = '([^']*)'", bas(t["tool_ai"]))
    okc_set = re.search(r"\bokc = '([^']*)'", bas(t["setai"]))
    good_x = re.search(r"\bgood = '([^']*)'", bas(t["tk_runx"]))
    row("the page's list of characters, SET.AI's and $tk_runx's are the same set, with no space, quote, semicolon, dollar, backquote, bar, ampersand, angle bracket or backslash in it",
        bool(okc_page and okc_set and good_x) and set(okc_page.group(1)) == set(okc_set.group(1)) == set(good_x.group(1)) and not (set(okc_page.group(1)) & set(" '\"`;$|&<>\\")), repr((okc_page, okc_set, good_x)))
    row("the accounts are read through $tk_gates and only a USER account is listed; the gate is the 'ai' row of the table; the page opens no record of the register itself",
        "call $tk_gates(names<i>, g, ainfo, gerr) if gerr = '' and ainfo<1> = 'USER' then" in v and "if g<k, 1> = 'ai' then ast<an> = g<k, 2>" in v and not re.search(r"\bread(v|u|vu)?\s+\w[\w.]*\s+from\b", v), "")
    row("tool.ai is in SDSYS's VOC only: voc_template has it as a verb for $tool_ai and newvoc has no tool.ai", t["voc_tool_ai"].split("\n")[:3] == ["V", "CA", "$tool_ai"] and not os.path.exists(os.path.join(SD64, "sdsys", "newvoc", "tool.ai")), "")
    row("the two help records exist (title, documentation page, a paragraph) and the page asks for both by their keys", all(len(t[k].strip().split("\n")) >= 3 and t[k].split("\n")[1] == "administrator-21-the-ai-helper" for k in ("h_prov", "h_acc"))
        and "'tool.ai.providers'" in v and "'tool.ai.accounts'" in v, "")
    row("(Windows) the help says what is Windows: the gate is a Windows group, the key is the service account NT SERVICE\\sd-ai's, and SDSYS (an elevated Administrator) can read it",
        "Windows group" in t["h_acc"] and "Linux" not in t["h_acc"] and "NT SERVICE\\sd-ai" in t["h_prov"] and "SDSYS is an elevated Administrator and can read the key" in t["h_prov"]
        and "Linux" not in t["h_prov"], "")
    gi = [ln for ln in re.findall(r'rows<-1> = "([^"]*)"', t["tk_gate_info"]) if ln.startswith("ai|")]
    cols = gi[0].split("|") if len(gi) == 1 else []
    ids = [ln.split("|")[0] for ln in re.findall(r'rows<-1> = "([^"]*)"', t["tk_gate_info"])]
    row("the gate table has one 'ai' row: group sdaiusers, words ai-on and ai-off, off as delivered, reaching beyond SD, built, listed after files-admin",
        len(cols) == 15 and cols[2:4] == ["ai-on", "ai-off"] and cols[4] == "group" and cols[6] == "sdaiusers" and cols[9] == "off" and cols[13] == "1" and cols[14] == "built"
        and ids.index("ai") == ids.index("files-admin") + 1, repr(gi))


def check_w(t):
    """GROUP W (Windows): the transport, the pipe and the caller, the key at rest, and the client."""
    w = c_only(t["win32ai"])
    o = c_only(t["op_ai"])
    op = w[w.index("int win32_ai_open("):w.index("int win32_ai_write(")]
    row("win32ai.c opens the pipe at IDENTIFICATION level (the helper can read who called and never act as the caller) with the narrow AI_ACCESS, never GENERIC_WRITE (FILE_APPEND_DATA is "
        "FILE_CREATE_PIPE_INSTANCE on a pipe)", "CreateFileA(pipe, AI_ACCESS, 0, NULL, OPEN_EXISTING, SECURITY_SQOS_PRESENT | SECURITY_IDENTIFICATION, NULL)" in op
        and "GENERIC_WRITE" not in w and "FILE_APPEND_DATA" not in w
        and "#define AI_ACCESS (FILE_READ_DATA | FILE_WRITE_DATA | FILE_READ_ATTRIBUTES | FILE_WRITE_ATTRIBUTES | READ_CONTROL | SYNCHRONIZE)" in w, "")
    row("...the owner of the pipe is checked against NT SERVICE\\sd-ai BEFORE the handle is kept or anything can be written, and a pipe that is not the service's is closed and answered WIN32_AI_NOTOURS",
        ordered(op, "if (check_owner && !owned_by_service(h)) {", "CloseHandle(h);", "return WIN32_AI_NOTOURS;", "SetNamedPipeHandleState(", "slots[slot] = h;")
        and '#define AI_SERVICE_ACCOUNT "NT SERVICE\\\\sd-ai"' in w and ordered(w, "LookupAccountNameA(NULL, AI_SERVICE_ACCOUNT", "GetSecurityInfo(h, SE_KERNEL_OBJECT, OWNER_SECURITY_INFORMATION", "EqualSid(owner, (PSID)want)"), "")
    row("...only a name beginning \\\\.\\pipe\\ is opened, and only a pipe (GetFileType): the transport cannot be pointed at a file", ordered(op, "strncasecmp(pipe, AI_PIPE_PREFIX, strlen(AI_PIPE_PREFIX)) != 0", "return WIN32_AI_NONE;")
        and "GetFileType(h) != FILE_TYPE_PIPE" in op, "")
    row("...the handle is NON-BLOCKING (PIPE_NOWAIT) and readiness is PeekNamedPipe's: a broken pipe is -1 (closed), and no read is ever asked of an empty pipe by op_ai.c",
        "mode = PIPE_READMODE_BYTE | PIPE_NOWAIT;" in op and "PeekNamedPipe(h, NULL, 0, NULL, &avail, NULL)" in w and re.search(r"ERROR_BROKEN_PIPE[^;]*\n?[^;]*return -1;", w) is not None, "")
    cn = o[o.index("Private int ai_connect("):o.index("Private bool ai_send_all(")]
    row("(Windows) op_ai.c: a pipe that is not the service's is AUDITED ('ai refused reason=pipe.owner', lower case) and answered as no helper; nothing is sent to it",
        ordered(cn, "slot = win32_ai_open(path, check_owner, AI_CONNECT_MS);", "if (slot == WIN32_AI_NOTOURS) {", 'audit_message("ai refused reason=pipe.owner");', "return -1;"), "")
    c = helper(t)
    m = shipped(t["main"])
    wn = shipped(t["win"])
    cp = func(m, "static HANDLE create_pipe(")
    lo = func(m, "static int listener_open(")
    row("the helper's pipe REJECTS REMOTE CLIENTS (a Windows pipe is reachable over the network otherwise), and its FIRST instance is FILE_FLAG_FIRST_PIPE_INSTANCE (a name someone else made first stops it)",
        "DWORD pipe_mode = PIPE_TYPE_BYTE | PIPE_READMODE_BYTE | PIPE_WAIT | PIPE_REJECT_REMOTE_CLIENTS;" in cp and "PIPE_ACCESS_DUPLEX | (first ? FILE_FLAG_FIRST_PIPE_INSTANCE : 0)" in cp
        and "g_cur = create_pipe(g_pipe, 1, &g_sa);" in lo and m.count("create_pipe(g_pipe, 1,") == 1, "")
    sd = func(m, "static int pipe_sa(")
    row("the pipe's security: owner the helper's own account, a PROTECTED list (P:), SYSTEM and the helper full, sdusers and Administrators PIPE_CLIENT_MASK only, and PIPE_CLIENT_MASK is win32ai.c's AI_ACCESS (0x00120183)",
        'snprintf(sd, sizeof sd, "O:%sD:P(A;;GA;;;SY)(A;;GA;;;%s)", me, me);' in sd and 'snprintf(t, sizeof t, "(A;;0x%08X;;;%s)", PIPE_CLIENT_MASK, s);' in sd
        and 'snprintf(t, sizeof t, "(A;;0x%08X;;;BA)", PIPE_CLIENT_MASK);' in sd and "#define PIPE_CLIENT_MASK 0x00120183" in m and "#define PIPE_CLIENT_MASK 0x00120183" in shipped(t["ctl"])
        and sd.count("GA") == 2, "")
    pr = func(wn, "int caller_from_pipe(")
    row("the caller is read by impersonating the pipe's client and REVERTING before anything else; a failed revert ends the process; LocalSystem, LocalService and NetworkService are no caller",
        ordered(pr, "if (!ImpersonateNamedPipeClient(h))", "return 0;", "OpenThreadToken(", "ok = read_token(tok, c);", "if (!RevertToSelf())", "ExitProcess(5);",
                'strcmp(c->sid, "S-1-5-18") == 0 || strcmp(c->sid, "S-1-5-19") == 0 || strcmp(c->sid, "S-1-5-20") == 0', "return 0;"), "")
    ig = func(wn, "int in_group(")
    row("the gate is read LIVE at each request (NetLocalGroupGetMembers, the caller's own SID among the members) and every doubt is no", "NetLocalGroupGetMembers(NULL, group, 0," in ig
        and "if (rc != NERR_Success && rc != ERROR_MORE_DATA) {" in ig and ig.count("return 1;") == 1 and "EqualSid(m, (PSID)sid)" in ig, "")
    dp = func(wn, "int dpapi(")
    row("the key is DPAPI in the helper account's OWN scope (no CRYPTPROTECT_LOCAL_MACHINE: any process on the machine could open a machine blob), no UI, with the provider's name as entropy",
        "CryptProtectData(&din, NULL, &ent, NULL, NULL, CRYPTPROTECT_UI_FORBIDDEN, &dout)" in dp and "CryptUnprotectData(&din, NULL, &ent, NULL, NULL, CRYPTPROTECT_UI_FORBIDDEN, &dout)" in dp
        and "LOCAL_MACHINE" not in c and 'static void key_entropy(char* out, size_t n, const char* name) { snprintf(out, n, "sd-ai key %s", name); }' in m
        and m.count("key_entropy(entropy, sizeof entropy, name);") == 2, "")
    wk = func(m, "static int write_key(")
    pc = func(wn, "HANDLE private_create(")
    row("write_key encrypts BEFORE it writes, into a file created with a protected list of this account and SYSTEM only (not one that inherits), then replaces the old one",
        ordered(wk, "dpapi((const BYTE*)key, (DWORD)strlen(key), entropy, 1, &blob, &bn)", "h = private_create(tmp);", "WriteFile(h, blob, bn, &w, NULL)", 'replace_file(tmp, state_path("keys", name))')
        and 'snprintf(sddl, sizeof sddl, "O:%sD:P(A;;FA;;;SY)(A;;FA;;;%s)", me, me);' in pc, "")
    pf = func(wn, "int private_file(")
    row("private_file allows only this account and SYSTEM, and refuses a list it cannot read or judge (no list, an entry of a kind not known)",
        "if (!EqualSid(s, me) && !EqualSid(s, (PSID)system))" in pf and "if (dacl == NULL ||" in pf and "if (hdr->AceType != ACCESS_ALLOWED_ACE_TYPE) {" in pf, "")
    ls = func(m, "static void listener_run(")
    spn = func(m, "static int spawn(")
    row("the service loop makes the NEXT instance BEFORE it lets go of the connected one (there is never a moment with no instance of ours for another user to take the name), and each request "
        "process is started suspended, put in a job that ends it when the service stops, and inherits the connection and the log and nothing else",
        ordered(ls, "BOOL ok = ConnectNamedPipe(g_cur, NULL);", "nxt = create_pipe(g_pipe, 0, &g_sa);", "if (!spawn(g_cur)) {", "g_cur = nxt;") and ls.count("spawn(") == 1
        and ordered(spn, "PROC_THREAD_ATTRIBUTE_HANDLE_LIST, inherit,", "CREATE_SUSPENDED", "AssignProcessToJobObject(g_job, pi.hProcess);", "ResumeThread(pi.hThread);")
        and "info.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;" in m, "")
    sv = func(m, "static int serve(")
    row("a request process ends itself if it runs far past its deadline (the watchdog, Linux's alarm), and the reply is flushed to the client before the process ends",
        "#define WATCHDOG_MS ((5 + 300 + 5) * 1000)" in m and ordered(sv, "CreateThread(NULL, 0, watchdog, NULL, 0, NULL);", "handle(buf.p,", "write_all(hout, r.js.p, r.js.n);", "FlushFileBuffers(hout);"), "")
    k = shipped(t["ctl"])
    tk = func(k, "static jval* talk(")
    row("(Windows) the client writes EVERYTHING to standard output (PowerShell 5.1 would wrap standard error in error records where set.ai reads 'error:') and checks the real pipe's owner before sending",
        "STD_ERROR_HANDLE" not in k and "stderr" not in k and not re.search(r"(?<!\w)f?printf\s*\(", k) and "SD_AI_TEST_CHECK_OWNER" not in k and "check_owner = _stricmp(path, DEFAULT_PIPE) == 0;" in k
        and ordered(tk, "CreateFileW(wp, PIPE_CLIENT_MASK, 0, NULL, OPEN_EXISTING, SECURITY_SQOS_PRESENT | SECURITY_IDENTIFICATION, NULL)", "if ((check_owner && !owned_by_service(h))",
                    "WriteFile(h, req + done,"), "")
    hs = shipped(t["https"])
    row("(13 Nov 26, the C helper) the provider's certificate is checked against the ca-file ALONE when SET.AI CA set one (Linux's meaning), else against the Windows ROOT store's certificates that "
        "may vouch for a server; X509_STRICT and PARTIAL_CHAIN as Python 3.13's default context",
        ordered(hs, "if (ca_file != NULL && ca_file[0] != '\\0') {", "SSL_CTX_load_verify_file(ctx, ca_file) != 1", "} else if (load_windows_roots(SSL_CTX_get_cert_store(ctx)) == 0) {")
        and 'CertOpenSystemStoreW(0, L"ROOT")' in hs and "szOID_PKIX_KP_SERVER_AUTH" in hs
        and "if (!usage_ok(c, CERT_FIND_PROP_ONLY_ENHKEY_USAGE_FLAG) || !usage_ok(c, CERT_FIND_EXT_ONLY_ENHKEY_USAGE_FLAG))" in hs
        and "X509_V_FLAG_X509_STRICT | X509_V_FLAG_PARTIAL_CHAIN" in hs, "")
    ak = func(m, "static int ask(")
    row("(13 Nov 26, the C helper) ONE retry on 429 and 5xx within the deadline, at most 4 MB of an answer read, more refused; connect and handshake within 5 seconds; no proxy",
        "for (attempt = 1; attempt <= 2; attempt++) {" in ak and "(r.status == 429 || r.status == 500 || r.status == 502 || r.status == 503 || r.status == 504) && attempt == 1" in ak
        and "#define RAW_CAP (4 * 1024 * 1024)" in t["https"] + t["main"] + open(os.path.join(AIDIR, "sdai.h"), encoding="latin-1").read()
        and "if (r->len > RAW_CAP)" in m and "#define CONNECT_TIMEOUT_MS 5000" in open(os.path.join(AIDIR, "sdai.h"), encoding="latin-1").read()
        and not re.search(r"proxy|WinHttp|InternetOpen", c, re.I), "")
    row("(13 Nov 26, the C helper) no USER32 and no SHELL32 in the program: libcrypto's three USER32 imports are stubbed (sdtlsrelay.c's measurement), and the command line comes from wmain, "
        "not SHELL32's CommandLineToArgvW", all(("void* __imp_%s = (void*)stub_%s;" % (f, f)) in hs for f in ("GetProcessWindowStation", "GetUserObjectInformationW", "MessageBoxW"))
        and "int wmain(int argc, wchar_t** wargv) {" in m and "CommandLineToArgvW" not in c and "shellapi" not in c, "")


GROUP_A_MUTANTS = [
    ("https", "certificate check off", "SSL_CTX_set_verify(ctx, SSL_VERIFY_PEER, NULL);", "SSL_CTX_set_verify(ctx, SSL_VERIFY_NONE, NULL);"),
    ("https", "host name check off", "if (!SSL_set1_host(ssl, host) || !SSL_set_tlsext_host_name(ssl, host)) {", "if (!SSL_set_tlsext_host_name(ssl, host)) {"),
    ("main", "http accepted", 'if (strncmp(u, "https://", 8) != 0)\n    return 0;\n  h = p = u + 8;', 'if (strncmp(u, "http", 4) != 0)\n    return 0;\n  h = p = u + (u[4] == \'s\' ? 8 : 7);'),
    ("main", "a query string is accepted in a URL", 'return chars_in(p, "._~/+,:-");', 'return chars_in(p, "._~/+,:?=&-");'),
    ("main", "a program is started", "  ExitProcess(4);\n  return 0;\n}", "  system(\"x\");\n  ExitProcess(4);\n  return 0;\n}"),
    ("main", "the helper prints", "  g_out = hout;\n", "  g_out = hout;\n  printf(\"x\");\n"),
    ("win", "the gate group is renamed", '#define GATE_GROUP L"sdaiusers"', '#define GATE_GROUP L"sdusers"'),
    ("main", "the key is put in the log line", '"%s sd-ai: sid=%s provider=%s status=%s in=%s out=%s\\n", ts,', '"%s sd-ai: key=%s sid=%s provider=%s status=%s in=%s out=%s\\n", ts, "k",'),
    ("main", "the key file is read before it is judged", '  if (!private_file(path))\n    return refuse("nokey", "the key file is not private");\n', ""),
    ("main", "the hygiene runs after the size test", "    hygiene(text.p, text.n, &clean, &replaced);\n    if ((long long)clean.n > lim[L_BYTES_REPLY]) {", "    if ((long long)text.n > lim[L_BYTES_REPLY]) {"),
    ("main", "the settings are checked for the administrator after they are done", '    if (c == NULL || !is_admin(c)) {\n      reply_err(r, "noadmin", "only the administrator may change the AI settings");',
     '    if (0) {\n      reply_err(r, "noadmin", "only the administrator may change the AI settings");'),
    ("main", "keyset echoes the key", 'sb_puts(out, "{\\"t\\": \\"ok\\", \\"key\\": \\"set\\"}");', 'sb_puts(out, "{\\"t\\": \\"ok\\", \\"key\\": \\"set\\", \\"echo\\": ");\n    sb_jstrz(out, kv->s);'),
    ("main", "the result of a setting is not checked before it is written", "  if (selected(&nw, &n, &p, &m) < 0)", "  if (0)"),
    ("win", "any Windows administrator may ask without the gate", "(is_sdsys(c) || in_group(c->psid, gate_group()))", "(is_admin(c) || in_group(c->psid, gate_group()))"),
    ("win", "an unelevated administrator may change settings", "(c->elevated && c->admins)", "(c->admins)"),
    ("providers", "an http URL in the table", "url=https://api.openai.com", "url=http://api.openai.com"),
    ("providers", "a model in the table", "[openai]\n", "[openai]\nmodel=gpt\n"),
    ("ctl", "the key is taken from the command line", "    key = read_key_console(rest[0]);", "    key = (argc > 3) ? argv[3] : read_key_console(rest[0]);"),
    ("ctl", "--handover reads the file only for a known provider",
     '    key = handover_key(rest[2]); /* removed first, whatever follows */\n    if (!is_provider(rest[0])) {\n      say("sd-ai-ctl: the provider is one of anthropic, openai, google, deepseek, custom");\n      return 2;\n    }\n',
     '    if (!is_provider(rest[0])) {\n      say("sd-ai-ctl: the provider is one of anthropic, openai, google, deepseek, custom");\n      return 2;\n    }\n    key = handover_key(rest[2]);\n'),
    ("context", "the standing text says Linux", "About this system: SD Core for Windows", "About this system: SD Core for Linux"),
]
M_B = len(GROUP_A_MUTANTS)
GROUP_B_MUTANTS = [
    ("install", "the service runs as LocalSystem", "& $sc config $SvcName obj= $SvcAccount | Out-Null", "& $sc config $SvcName obj= LocalSystem | Out-Null"),
    ("install", "the service SID is not restricted", "& $sc sidtype $SvcName restricted | Out-Null", "& $sc sidtype $SvcName unrestricted | Out-Null"),
    ("install", "the keys directory admits Administrators", "& icacls $keys /inheritance:r /grant:r '*S-1-5-18:(OI)(CI)F' \"${SvcAccount}:(OI)(CI)M\" | Out-Null",
     "& icacls $keys /inheritance:r /grant:r '*S-1-5-18:(OI)(CI)F' \"${SvcAccount}:(OI)(CI)M\" '*S-1-5-32-544:(OI)(CI)F' | Out-Null"),
    ("install", "the service runs under Python again", "$bin = '\"' + $helper + '\" --service'", "$bin = '\"' + $py + '\" -I -B \"' + $helper + '\" --service'"),
    ("install", "the state is reset on an upgrade", "foreach ($d in @($state, $keys, $cnt)) {", "Remove-Item -LiteralPath $state -Recurse -Force\nforeach ($d in @($state, $keys, $cnt)) {"),
    ("iss", "a helper that did not start is passed over (the old no-Python code 3)", "  if Code = 0 then\n    Exit;\n  Result := 'The AI helper service", "  if (Code = 0) or (Code = 3) then\n    Exit;\n  Result := 'The AI helper service"),
    ("makefile", "the test build's hooks are compiled into the shipped helper", "\t@PATH=\"$(UCRT_BIN):$$PATH\" $(UCRT_CC) -std=gnu17 -Wall -Wformat=2 -O2 -municode \\",
     "\t@PATH=\"$(UCRT_BIN):$$PATH\" $(UCRT_CC) -std=gnu17 -Wall -Wformat=2 -O2 -municode -DSDAI_TESTS \\"),
    ("makefile", "sd does not build the helper", "sd: $(SDOBJS) sdclilib sdsvc sdtlsrelay sd-ai sdpy", "sd: $(SDOBJS) sdclilib sdsvc sdtlsrelay sdpy"),
    ("stage", "sd-ai.exe may import the MSYS2 runtime or Python", "'sd-ai.exe':      ['msys-', 'python', 'user32', 'shell32'],", "'sd-ai.exe':      ['user32'],"),
    ("iss", "the service is left at uninstall", "    Parameters: \"-NoProfile -NonInteractive -ExecutionPolicy Bypass -File \"\"{app}\\install-aihelper.ps1\"\" -Remove\"; \\\n", "    Parameters: \"-NoProfile\"; \\\n"),
    ("iss", "the group is left at uninstall", "  Exec(Net, 'localgroup sdaiusers /delete',    '', SW_HIDE, ewWaitUntilTerminated, Code);\n", ""),
    ("stage", "the helper is not staged", "AI_HELPER_BIN = 'sd-ai.exe'", "AI_HELPER_BIN = 'sd-ai'"),
    ("groups", "sdaiusers is not made", "    Ensure-Group $AiGroup $AiComment\n", ""),
    ("createacc.h", "CA$AI shares a number", "$define CA$AI              41", "$define CA$AI              40"),
    ("createa", "ai-on is not a word", "         case upcase(token) = 'AI-ON'\n            settings<CA$AI> = 1\n", ""),
    ("acc_os_info", "the manifest has no route.ai", "   info<-1> = 'route.ai: ' : aiuse", "   info<-1> = 'route.x: ' : aiuse"),
    ("restorea", "route.ai is not restored", "      if m.route.ai = '1' then settings<CA$AI> = 1\n", ""),
    ("setai", "the administrator is not asked first", "   if not(kernel(K$ADMINISTRATOR, -1)) then\n      stop sysmsg(2001) ;* Command requires administrator privileges\n   end\n", ""),
    ("setai", "a semicolon is an allowed character", "0123456789._:/@+,-'", "0123456789._:/@+,-;'"),
    ("setai", "the key is captured by SD", "         os.execute \"& '\" : ctl : \"' 'key' '\" : prov : \"'\"\n", "         os.execute \"& '\" : ctl : \"' 'key' '\" : prov : \"'\" capturing keyout\n"),
    ("setai", "the whole URL goes to the audit trail", "' host=' : chost)", "' host=' : curl)"),
    ("setai", "the client is looked for in the SD system directory", "if ctl = '' then ctl = kernel(K$WINPATH, '/lib/sd-ai/sd-ai.exe')", "if ctl = '' then ctl = @sdsys : @ds : 'bin' : @ds : 'sd-ai.exe'"),
    ("setai", "the carriage returns are left in", "   out = convert(char(13), '', out)\n*  8 Nov 26", "*  8 Nov 26"),
    ("setai", "the no-Python stop comes back", "   out = convert(char(13), '', out)\n*  8 Nov 26",
     "   out = convert(char(13), '', out)\n   if trim(out<1>)[1, 16] = 'error: nopython:' then stop sysmsg(12934)\n*  8 Nov 26"),
    ("voc_template", "set.ai is a different program", "$setai", "$setstart"),
]
M_C = M_B + len(GROUP_B_MUTANTS)
GROUP_C_MUTANTS = [
    ("op_ai", "any program may call the kernel keys", "if (!(process.program.flags & HDR_INTERNAL)) {", "if (0) {"),
    ("op_ai", "the audit line is not written", "  audit_message(audit);\n", ""),
    ("op_ai", "a second audit call after the connection", "  ai.slot = ai_connect();\n  if (ai.slot < 0) {\n    free(req);", "  ai.slot = ai_connect();\n  audit_message(audit);\n  if (ai.slot < 0) {\n    free(req);"),
    ("op_ai", "the text goes into the audit line", 'bytes.out=%d", account(), pname, (int)(strlen(system) + strlen(prompt)));', 'bytes.out=%d %s", account(), pname, (int)(strlen(system) + strlen(prompt)), prompt);'),
    ("op_ai", "the kernel opens a socket", "  slot = win32_ai_open(path, check_owner, AI_CONNECT_MS);\n", "  slot = win32_ai_open(path, check_owner, AI_CONNECT_MS);\n  (void)socket(1, 1, 0);\n"),
    ("op_ai", "the request is a settings operation", '\\"op\\":\\"ask\\"', '\\"op\\":\\"keyset\\"'),
    ("op_ai", "a byte above 127 is sent as it is", "    } else if (c >= 128) {\n      out[pos++] = '?';", "    } else if (c >= 128) {\n      out[pos++] = (char)c;"),
    ("op_ai", "the deadline is a thousand times longer", "#define AI_DEADLINE 340 /*", "#define AI_DEADLINE 340000 /*"),
    ("op_ai", "the number is read from the prompt", "maxtokens = atoi(maxt);", "maxtokens = atoi(prompt);"),
    ("op_ai", "any SD_AI_PIPE is taken, a file too", "(strncasecmp(p, AI_PIPE_PREFIX, strlen(AI_PIPE_PREFIX)) == 0)) {", "1) {"),
    ("op_ai", "the real pipe's owner is not checked", "  *check_owner = 1;\n  return AI_DEFAULT_PIPE;", "  *check_owner = 0;\n  return AI_DEFAULT_PIPE;"),
    ("keys.h", "a key number is moved", "#define K_AI_POLL            161", "#define K_AI_POLL            171"),
    ("int$keys.h", "a key number is moved in BASIC", "$define K$AI.CANCEL       162", "$define K$AI.CANCEL       172"),
    ("op_kernel", "POLL is not dispatched", "    case K_AI_POLL:\n    case K_AI_CANCEL:", "    case K_AI_CANCEL:"),
    ("gpl.src", "win32ai is not linked", "win32ai\n", ""),
    ("ai", "the preview answer is not tested", "   if ans # 'y' and ans # 'yes' then", "   if @false then"),
    ("ai", "nobody is asked", "   input ans\n", "   ans = 'y'\n"),
    ("ai", "the account is put into the system sentence", "   system.text = 'You are", "   system.text = @who : 'You are"),
    ("ai", "the account is put into the request", "system.text : @fm : 1024 : @fm : question)", "system.text : @fm : 1024 : @fm : question : @who)"),
    ("ai", "the gate is not read from the status", "   if not(st{'gate'}) then", "   if @false then"),
    ("ai", "the answer is run", "   display sysmsg(12639, j{'in'}", "   os.execute text\n   display sysmsg(12639, j{'in'}"),
    ("newvoc_ai", "ai is a different program for accounts", "$ai", "$pdf"),
    ("m12628", "the usage no longer mentions quotes", "Put the text in quotes if it ends with ?", ""),
]
M_D = M_C + len(GROUP_C_MUTANTS)
GROUP_D_MUTANTS = [
    ("tool_ai", "the confirm box is skipped", "   call $tk_confirm(sent, el, typed, res, cmsg)\n   if res = 'run' then\n      if use.x then", "   res = 'run'\n   if res = 'run' then\n      if use.x then"),
    ("tool_ai", "no name is typed to select a provider", "      sent = 'set.ai provider ' : p\n      typed = p\n", "      sent = 'set.ai provider ' : p\n      typed = ''\n"),
    ("tool_ai", "no name is typed to turn a gate on", "      typed = an.name\n      lpid = sel", "      typed = ''\n      lpid = sel"),
    ("tool_ai", "Custom needs no word", "   typed = 'custom'\n", "   typed = ''\n"),
    ("tool_ai", "a certificate file needs no word", "      typed = 'ca'\n", "      typed = ''\n"),
    ("tool_ai", "a semicolon is an allowed character", "0123456789._:/@+,-'", "0123456789._:/@+,-;'"),
    ("tool_ai", "the page may run sh", "allow.set = 'set.ai'", "allow.set = 'set.ai sh'"),
    ("tool_ai", "the key hand-over is not guarded by the fixed four", "   if index(' anthropic openai google deepseek custom ', ' ' : p : ' ', 1) = 0 then return\n", ""),
    ("tool_ai", "the key is put in the sentence", "call $tk_runx(allow.set, 'set.ai key ' : p : ' handover', out, st, err)", "call $tk_runx(allow.set, 'set.ai key ' : p : ' ' : kv, out, st, err)"),
    ("tool_ai", "the model is not checked", "      vmax = 80\n      gosub valid.word\n", "      vmax = 80\n      vw.ok = 1\n"),
    ("tool_ai", "the page is opened for anyone", "   call $tk_open('tool.ai', 'admin', ctx, err)\n   if err # '' then\n      display err\n      stop", "   call $tk_open('tool.ai', '', ctx, err)\n   if err # '' then\n      display err\n      stop"),
    ("tool_ai", "the page starts a request", "   reply = kernel(K$AI.STATUS, 0)\n   if reply<1> = 'D' then", "   void kernel(K$AI.START, 'x')\n   reply = kernel(K$AI.STATUS, 0)\n   if reply<1> = 'D' then"),
    ("tool_ai", "the key is shown in the dialog's message", "      su.say = 'The key was not set: ' : hk.err\n", "      su.say = 'The key was not set: ' : hk.err : kv\n"),
    ("tool_ai", "an account that is not a person is listed", "if gerr = '' and ainfo<1> = 'USER' then", "if gerr = '' then"),
    ("voc_tool_ai", "tool.ai is another program", "$tool_ai", "$tool_audit"),
    ("tk_gate_info", "the ai gate is on as delivered", "|ai-on|ai-off|group||sdaiusers||at the next request|off|AI|", "|ai-on|ai-off|group||sdaiusers||at the next request|on|AI|"),
    ("tk_gate_info", "the ai gate is another group", "|group||sdaiusers||at the next request|off|AI|", "|group||sdusers||at the next request|off|AI|"),
    ("h_acc", "the help record points at another page", "21-the-ai-helper", "01-accounts-and-security"),
    ("h_prov", "the help says nothing of SDSYS reading the key", " On Windows SDSYS is an elevated Administrator and can read the key", " The key is safe"),
]
M_E = M_D + len(GROUP_D_MUTANTS)
GROUP_E_MUTANTS = [
    ("op_ai", "any number of earlier exchanges is taken", "    if (nhist < 1 || nhist > AI_HIST_MAX) {", "    if (nhist < 1) {"),
    ("op_ai", "a missing earlier field is not refused", "      p = strchr(prompt, FIELD_MARK);\n      if (p == NULL) {\n        free(arg);\n        ai_answer(\"ERR\", \"bad\", result);\n        return;\n      }\n      *p = '\\0';\n      hbytes",
     "      p = strchr(prompt, FIELD_MARK);\n      if (p == NULL)\n        break;\n      *p = '\\0';\n      hbytes"),
    ("op_ai", "the earlier exchanges are not counted in the audit line", "(int)(strlen(system) + strlen(prompt) + hbytes), nhist);", "(int)(strlen(system) + strlen(prompt)), nhist);"),
    ("op_ai", "the answers are sent unescaped", "      pos = ai_json_string(req, pos, hist[2 * i + 1], strlen(hist[2 * i + 1]));", "      pos += (size_t)sprintf(req + pos, \"\\\"%s\\\"\", hist[2 * i + 1]);"),
]
M_F = M_E + len(GROUP_E_MUTANTS)
GROUP_F_MUTANTS = [
    ("tool_ai", "the key field is not masked", "   screen entry sf, 'key' at 2 + su.lw,2 width 70 value su.kini mask maxlen 600\n", "   screen entry sf, 'key' at 2 + su.lw,2 width 70 value su.kini maxlen 600\n"),
    ("tool_ai", "the key is kept after the hand-over", "   close kf\n   kv = ''\n", "   close kf\n"),
    ("tool_ai", "the hand-over file is left behind", "   os.execute \"Remove-Item -LiteralPath '\" : hf : \"' -Force -ErrorAction SilentlyContinue\"\n   return", "   return"),
    ("tool_ai", "the hand-over directory is not made private", "icacls $d /inheritance:r /grant:r 'SDSYS:(OI)(CI)F' 'SYSTEM:(OI)(CI)F'", "icacls $d /grant 'Users:(OI)(CI)R'"),
    ("tool_ai", "a typed name is not checked against the list", "            if lm.list<i> = ov then found = 1\n", "            found = 1\n"),
    ("tool_ai", "the list is not asked again with a new key", "   screen set sf, 'key' value su.keep\n   gosub fetch.models\n", "   screen set sf, 'key' value su.keep\n"),
    ("tool_ai", "Save goes over a list that has only just come", "               if not(su.fetched) then gosub setup.save", "               gosub setup.save"),
    ("tool_ai", "the keep-stars are handed over as a key", "   if kv = su.keep or kv = '' then\n", "   if kv = '' then\n"),
    ("setai", "the hand-over file is kept", "drop.handover:\n   os.execute \"Remove-Item -LiteralPath '\" : hand.f : \"' -Force -ErrorAction SilentlyContinue\"\n", "drop.handover:\n"),
    ("setai", "the hand-over file is a word of the sentence", "         hand.f = @sdsys : @ds : '$aikey' : @ds : 'key'\n", "         hand.f = field(words, ' ', 5)\n"),
    ("setai", "a refusal that says not found is taken for an unreachable helper", "(trim(out<1>)[1, 7] # 'error: ' and (", "(1 and ("),
]
M_W = M_F + len(GROUP_F_MUTANTS)                           # 13 Nov 26, group W (Windows): --from=M_W runs only these
GROUP_W_MUTANTS = [
    ("win32ai", "the client may act as the caller (impersonation level)", "SECURITY_SQOS_PRESENT | SECURITY_IDENTIFICATION, NULL)", "SECURITY_SQOS_PRESENT | SECURITY_IMPERSONATION, NULL)"),
    ("win32ai", "the pipe is opened for GENERIC_WRITE", "    h = CreateFileA(pipe, AI_ACCESS, 0,", "    h = CreateFileA(pipe, GENERIC_READ | GENERIC_WRITE, 0,"),
    ("win32ai", "the owner is not checked", "  if (check_owner && !owned_by_service(h)) {", "  if (0) {"),
    ("win32ai", "the owner is checked after the handle is kept", "  if (check_owner && !owned_by_service(h)) {\n    CloseHandle(h);\n    return WIN32_AI_NOTOURS;\n  }\n", ""),
    ("win32ai", "the pipe is put in the MSYS2 descriptor table", "  slots[slot] = h;\n  return slot;", "  slots[slot] = h;\n  (void)cygwin_attach_handle_to_fd(NULL, -1, h, 1, 0);\n  return slot;"),
    ("win32ai", "any file may be opened", "  if (GetFileType(h) != FILE_TYPE_PIPE) {", "  if (0) {"),
    ("op_ai", "a squatted pipe is not audited", '    audit_message("ai refused reason=pipe.owner");\n', ""),
    ("op_ai", "the poll reads without asking what is there", "    if (want > avail)\n      want = avail;\n    n = win32_ai_read(ai.slot,", "    n = win32_ai_read(ai.slot,"),
    ("main", "remote clients are let in", "PIPE_TYPE_BYTE | PIPE_READMODE_BYTE | PIPE_WAIT | PIPE_REJECT_REMOTE_CLIENTS;", "PIPE_TYPE_BYTE | PIPE_READMODE_BYTE | PIPE_WAIT;"),
    ("main", "the first instance may join a pipe someone else made", "PIPE_ACCESS_DUPLEX | (first ? FILE_FLAG_FIRST_PIPE_INSTANCE : 0)", "PIPE_ACCESS_DUPLEX"),
    ("main", "the pipe's list is not protected", '"O:%sD:P(A;;GA;;;SY)(A;;GA;;;%s)", me, me);', '"O:%sD:(A;;GA;;;SY)(A;;GA;;;%s)", me, me);'),
    ("main", "sdusers may make pipe instances", 'snprintf(t, sizeof t, "(A;;0x%08X;;;%s)", PIPE_CLIENT_MASK, s);', 'snprintf(t, sizeof t, "(A;;GA;;;%s)", s);'),
    ("win", "the thread is not reverted", "  if (!RevertToSelf())\n    ExitProcess(5); /* never go on as anyone else */", "  RevertToSelf();"),
    ("win", "LocalSystem is a caller", 'strcmp(c->sid, "S-1-5-18") == 0 || ', ""),
    ("win", "the key is a machine blob", "CryptProtectData(&din, NULL, &ent, NULL, NULL, CRYPTPROTECT_UI_FORBIDDEN, &dout);", "CryptProtectData(&din, NULL, &ent, NULL, NULL, CRYPTPROTECT_UI_FORBIDDEN | CRYPTPROTECT_LOCAL_MACHINE, &dout);"),
    ("win", "a list of any kind passes", "    if (hdr->AceType != ACCESS_ALLOWED_ACE_TYPE) {", "    if (0) {"),
    ("main", "the connected instance is let go before the next is made", "    reap();\n    while (nxt == INVALID_HANDLE_VALUE && !stopping) {", "    spawn(g_cur);\n    reap();\n    while (nxt == INVALID_HANDLE_VALUE && !stopping) {"),
    ("main", "no watchdog", "    HANDLE dog = CreateThread(NULL, 0, watchdog, NULL, 0, NULL);\n", "    HANDLE dog = NULL;\n"),
    ("main", "a request process is not in the job", "    AssignProcessToJobObject(g_job, pi.hProcess);\n", ""),
    ("ctl", "the client trusts any pipe's owner", "if ((check_owner && !owned_by_service(h))", "if ((0)"),
    ("ctl", "the client's errors go to standard error", "  HANDLE h = GetStdHandle(STD_OUTPUT_HANDLE);\n  DWORD w;\n  size_t n = strlen(s);", "  HANDLE h = GetStdHandle(STD_ERROR_HANDLE);\n  DWORD w;\n  size_t n = strlen(s);"),
    ("https", "the Windows store is trusted beside the administrator's ca-file", "  } else if (load_windows_roots(SSL_CTX_get_cert_store(ctx)) == 0) {", "  }\n  if (load_windows_roots(SSL_CTX_get_cert_store(ctx)) == 0) {"),
    ("https", "a root barred from server authentication is trusted", "    if (!usage_ok(c, CERT_FIND_PROP_ONLY_ENHKEY_USAGE_FLAG) || !usage_ok(c, CERT_FIND_EXT_ONLY_ENHKEY_USAGE_FLAG))\n      continue;\n", ""),
    ("https", "USER32 is imported again", "void* __imp_MessageBoxW = (void*)stub_MessageBoxW;\n", ""),
    ("main", "two retries", "for (attempt = 1; attempt <= 2; attempt++) {", "for (attempt = 1; attempt <= 3; attempt++) {"),
    ("win", "the test gate is in the shipped helper", "#ifdef SDAI_TESTS\n  /* THE TEST BUILD ONLY", "#if 1\n  /* THE TEST BUILD ONLY"),
]


def load():
    t = {}
    for k, p in FILES.items():
        with open(p, encoding="latin-1") as f:
            t[k] = f.read()
    return t


def run_all(t):
    check_a(t)
    check_b(t)
    check_c(t)
    check_d(t)
    check_w(t)


def selftest(first):
    import contextlib
    import io
    global passed, failed
    base = load()
    bad = 0
    for i, (key, name, old, new) in enumerate(GROUP_A_MUTANTS + GROUP_B_MUTANTS + GROUP_C_MUTANTS + GROUP_D_MUTANTS + GROUP_E_MUTANTS + GROUP_F_MUTANTS + GROUP_W_MUTANTS):
        if i < first:
            continue
        if base[key].count(old) != 1:
            print("  [FAIL] mutant %r: the old text occurs %d times in %s, it must occur once" % (name, base[key].count(old), key))
            bad += 1
            continue
        t = dict(base)
        t[key] = base[key].replace(old, new)
        p0, f0 = passed, failed
        with contextlib.redirect_stdout(io.StringIO()):
            try:
                run_all(t)
            except (ValueError, AttributeError, IndexError):
                failed += 1                     # a rule the mutation broke so far that the text can no longer be read counts as caught
        caught = failed > f0
        passed, failed = p0, f0
        print("  [%s] mutant %d: %s" % ("caught" if caught else "MISSED", i, name))
        bad += not caught
    p0, f0 = passed, failed
    with contextlib.redirect_stdout(io.StringIO()):
        run_all(base)
    ok = failed == f0
    passed, failed = p0, f0
    print("  [%s] control: the unmutated text passes every row" % ("ok" if ok else "FAIL"))
    bad += not ok
    print("\nselftest: %s" % ("all behaved" if bad == 0 else "%d problem(s)" % bad))
    return 0 if bad == 0 else 1


def main():
    if "--selftest" in sys.argv:
        first = 0
        for a in sys.argv:
            if a.startswith("--from="):
                first = int(a[len("--from="):])
        return selftest(first)
    run_all(load())
    print("\ntest-ai-units: %d passed, %d failed" % (passed, failed))
    return 0 if failed == 0 and passed > 0 else 1


if __name__ == "__main__":
    sys.exit(main())
