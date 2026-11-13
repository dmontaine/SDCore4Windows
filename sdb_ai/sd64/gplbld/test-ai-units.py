#!/usr/bin/env python3
#
# test-ai-units.py - the AI integration read off its source as TEXT (from Linux b1d496df, S.69 step 2; RELEASE_1.1 246).  Free: no sd, no install, no elevation.
#
#   python C:\Users\Don\Projects\SDCore4Windows\sdb_ai\sd64\gplbld\test-ai-units.py [--selftest [--from=N]]
#
# What a behaviour test cannot say: that a rule is still WRITTEN where it must be.  Exit 0 every row passed, 1 a row failed.   --selftest   each MUTANT (a rule
# taken out of a copy of the text, in memory) must turn a row red; --from=N runs the mutants from number N on.  test-aihelper-units.py RUNS the Windows parts.
#
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
FILES = {
    "helper": os.path.join(HERE, "sd-ai"),
    "ctl": os.path.join(HERE, "sd-ai-ctl"),
    "wrapper": os.path.join(HERE, "sd-ai-ctl.ps1"),
    "finder": os.path.join(HERE, "sd-ai-python.ps1"),
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


def check_a(t):
    c = code_only(t["helper"])
    row("no way to turn certificate checking off: no CERT_NONE, no verify=False, no _create_unverified_context, no 'insecure' anywhere", not re.search(r"CERT_NONE|verify\s*=\s*False|_create_unverified|insecure", c, re.I), "")
    row("the TLS context checks the host name and requires a certificate (check_hostname = True, CERT_REQUIRED) and is not older than TLS 1.2", "ctx.check_hostname = True" in c and "ctx.verify_mode = ssl.CERT_REQUIRED" in c
        and "minimum_version = ssl.TLSVersion.TLSv1_2" in c, "")
    row("the URL a request goes to must be https: URL_RE starts ^https://, and has no query string and no % escape", 'URL_RE = re.compile(r"^https://' in c and "http://" not in c.replace("https://", "")
        and re.search(r'URL_RE = re\.compile\(r"[^"]*\(/\[A-Za-z0-9\._~/\+,:-\]\{0,500\}\)\?\$"\)', c) is not None, "")
    pops = re.findall(r"subprocess\.Popen\(\[([^\]]*)\]", c)
    row("(Windows) it starts no program but ITSELF for one request (the service loop): one subprocess.Popen, of sys.executable -I -B this file --one; no os.system, os.popen, eval, exec, pickle, shell=True",
        len(pops) == 1 and pops[0].startswith('sys.executable, "-I", "-B", os.path.abspath(__file__), "--one"') and c.count("subprocess.") == 1
        and not re.search(r"os\.system|os\.popen|\beval\(|\bexec\(|\bpickle\b|shell\s*=\s*True", c), repr(pops))
    row("it never prints to stdout (the one reply is written with os.write on the connection)", not re.search(r"\bprint\(|sys\.stdout", c), "")
    row("the gate group is sdaiusers and the administrator account is SDSYS", 'GATE_GROUP = "sdaiusers"' in c and 'ADMIN_USER = "SDSYS"' in c, "")
    hall = c[c.index("def handle("):c.index("def write_all(")]
    mb = between(hall, 'if req["op"] == "models":', 'if req["op"] in ("set", "keyset", "keyclear"):')
    row("(S.170) in handle() the models request is the administrator's: is_admin is asked BEFORE the settings or the key are read, a caller who is not gets noadmin, and the list is asked last",
        ordered(mb, "not is_admin(uid)", '"code": "noadmin"', "parse_kv(", "read_key(state, name)", "list_models(conf, name, p, key, limits)"), "")
    h = hall[hall.index('if req["op"] in ("set", "keyset", "keyclear"):'):]
    row("in handle() the gate is asked BEFORE the settings are read (may_ask comes before parse_kv); the caller is read from the pipe (peer) and from nothing the caller wrote",
        h.index("if not may_ask(uid):") < h.index("parse_kv(") and "uid = peer(fd)" in hall and hall.count("peer(") == 1, "")
    m = c[c.index("def may_ask("):c.index("def ", c.index("def may_ask(") + 4)]
    row("may_ask (S.163, owner Q6): SDSYS OR a member of the gate group, and nobody else (another Windows administrator needs the gate); an unknown caller is never let through",
        "return caller is not None and (is_sdsys(caller) or in_group(caller.sid, GATE_GROUP))" in m and m.count("return") == 1, "")
    ia = c[c.index("def is_admin("):c.index("def may_ask(")]
    row("is_admin (owner Q6): SDSYS, or an ELEVATED caller with Administrators enabled - the settings only", "return caller is not None and (is_sdsys(caller) or (caller.elevated and caller.admins))" in ia, "")
    row("in handle() the key is read after the model and before the request is checked, the limits are counted before the call, and the call is last", h.index("selected(conf, table)") < h.index("read_key(")
        < h.index("counters(state, uid, time.time(), limits, count=True)") < h.index("ask(state, conf"), "")
    row("in handle() set, keyset and keyclear reach admin_op only for the administrator: is_admin is asked first, and a caller who is not gets noadmin", ordered(h, 'req["op"] in ("set", "keyset", "keyclear")',
        "not is_admin(uid)", '"code": "noadmin"', "admin_op(state, providers_path, req)") and h.count("admin_op(") == 1, "")
    s = c[c.index("def serve("):c.index("def flush_out(")]
    log = re.search(r'log\("([^"]*)"[^\n]*', s)
    row("the one log line names the caller (sid), the provider, the status and the sizes and no text or key", bool(log) and all(w in log.group(0) for w in ("sid=", "provider=", "status=", "in=", "out="))
        and not re.search(r"prompt|text|key|system", log.group(1)), repr(log.group(0) if log else None))
    row("it writes no audit trail: no 'audit' and no K$AUDIT in the helper (SD writes the line BEFORE it asks)", "audit" not in c.lower(), "")
    rk = c[c.index("def read_key("):c.index("def private_create(")]
    row("(Windows) the key file must be private BEFORE it is read: private_file (a plain file, no reparse point, an access list of this account and SYSTEM only) comes before the open; a "
        "file that is not is nokey", ordered(rk, "if not private_file(path):", '"the key file is not private"', 'open(path, "rb")', "dpapi(blob, key_entropy(name), False)")
        and "os.lstat(path)" in c and "stat.S_ISREG" in c and "FILE_ATTRIBUTE_REPARSE_POINT" in c, "")
    row("a redirect is never followed: no http.client redirect handling, no urllib.request, no requests", not re.search(r"urllib\.request|import requests|HTTPRedirectHandler", c) and "redirect, which is not followed" in c, "")
    row("the reply is cut to ASCII by hygiene() before it is returned, and an oversize reply is an error, not a cut", c.index("text, replaced = hygiene(text)") < c.index('"toobig", "the reply is over'), "")
    ad = c[c.index("def admin_op("):c.index("def readable(")]
    row("admin_op checks the whole result before it writes (selected, every limit) and write_key/write_conf replace atomically; a key reply never holds the key", ordered(ad, "selected(new, table)", "int_setting(new, k)", "write_conf(state, new)")
        and "replace(tmp, path)" in c and "replace(tmp, os.path.join(d, name))" in c and 'return {"t": "ok", "key": "set"}' in ad and 'req.get("key")' in ad
        and not re.search(r'\{[^}]*"echo"', ad), "")
    p = t["providers"]
    secs = re.findall(r"^\[([a-z]+)\]$", p, re.M)
    row("the shipped providers table has exactly anthropic, openai, google and deepseek", secs == ["anthropic", "openai", "google", "deepseek"], repr(secs))
    urls = re.findall(r"^url=(.*)$", p, re.M)
    row("every shipped URL is https and names a host", len(urls) == 4 and all(re.match(r"^https://[a-z.]+/", u) for u in urls), repr(urls))
    models = re.findall(r"^model=(.*)$", p, re.M)
    row("the shipped table holds a default model for each provider (a plain model name) and no key (the person supplies the key; the model may be changed)",
        len(models) == 4 and all(re.match(r"^[A-Za-z0-9][A-Za-z0-9._:/@+-]{0,99}$", m) for m in models) and not re.search(r"^key", p, re.M | re.I), repr(models))
    k = code_only(t["ctl"])
    kb = between(k, 'elif cmd == "key" and len(rest) == 1:', "if req is None:")
    row("sd-ai-ctl never takes a key as an argument: in the key branch the key comes from getpass or stdin only (rest holds the provider and nothing else), and it is never printed",
        'key = getpass.getpass("Key for %s (not shown): " % rest[0])' in kb and "key = sys.stdin.readline().rstrip" in kb and "rest[1]" not in kb and "sys.argv" not in kb
        and not re.search(r'say\([^)]*\bkey\s*\)|say\(.*\breq\b', k) and 'rest[0] not in PROVIDERS' in k, "")
    hb = between(k, 'elif cmd == "key" and len(rest) == 3 and rest[1] == "--handover":', 'elif cmd == "key" and len(rest) == 1:')
    row("(Windows) sd-ai-ctl key --handover: the key is the FILE's (named by the third word), read and removed BEFORE the provider is even checked, and never printed",
        ordered(hb, "key = handover_key(rest[2])", "if rest[0] not in PROVIDERS:", '"keyset"') and ordered(k, "def handover_key(path):", "f.readline()", "finally:", "os.remove(path)"), "")
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
    row("...the service runs the all-users Python, isolated and writing no bytecode, on the helper in the program folder, with --service; no Python means NO service (exit 3), never a guess",
        "$bin = '\"' + $py + '\" -I -B \"' + $helper + '\" --service'" in ins and ordered(ins, "$py = Find-SdPython", "if (-not $py) {", "Remove-Svc", "exit 3", "New-Service"), "")
    row("...the keys directory is SYSTEM's and the service's ONLY (no Administrators entry), the state directory adds Administrators READ; inheritance cut on both; ai.conf is not written (none is AI off)",
        "& icacls $keys /inheritance:r /grant:r '*S-1-5-18:(OI)(CI)F' \"${SvcAccount}:(OI)(CI)M\" | Out-Null" in ins
        and "& icacls $state /inheritance:r /grant:r '*S-1-5-18:(OI)(CI)F' \"${SvcAccount}:(OI)(CI)M\" '*S-1-5-32-544:(OI)(CI)RX' | Out-Null" in ins and "ai.conf" not in ins.replace("ai.conf is NOT written", ""), "")
    row("...nothing is deleted from the state directory (an upgrade keeps settings and keys, as Linux keeps /var/lib/sd-ai), and what was made is read back and printed (account, command, pipe, access lists)",
        not re.search(r"Remove-Item[^\n]*\$(state|keys|cnt)\b", ins) and "Get-CimInstance -ClassName Win32_Service" in ins and "$w.StartName -eq $SvcAccount" in ins and "Test-AiPipe" in ins, "")
    iss = t["iss"]
    row("(Windows) sd.iss sets up the helper AFTER the Python step (from [Code], at ssPostInstall), reports only a failure, removes the service at uninstall and deletes the group sdaiusers with the others",
        ordered(iss, "PyMsg := InstallPython;", "AiMsg := InstallAiHelper;") and "AiMsg +" in iss and "\\install-aihelper.ps1\"\" -Remove\"" in iss
        and "Exec(Net, 'localgroup sdaiusers /delete'," in iss and "if (Code = 0) or (Code = 3) then" in between(iss, "function InstallAiHelper: String;", "procedure CurStepChanged"), "")
    st = t["stage"]
    row("(Windows) stage.py ships the helper, its client, the two finders and the two data files to ProgramFiles\\lib\\sd-ai (a missing one fails the build), and install-aihelper.ps1 to {app}",
        "AI_HELPER_FILES = ['sd-ai', 'sd-ai-ctl', 'sd-ai-ctl.ps1', 'sd-ai-python.ps1', 'ai-providers', 'ai-context']" in st and "ai_dst = os.path.join(pf, 'lib', 'sd-ai')" in st
        and "raise SystemExit('missing %s - the AI helper needs it' % src)" in st and "'install-aihelper.ps1'," in st, "")
    g = ps_only(t["groups"])
    row("(Windows) sync-route-groups.ps1 makes sdaiusers with the other gate groups and adds nobody to it", "$AiGroup   = 'sdaiusers'" in g and "$null     = Ensure-Group $AiGroup $AiComment" in g
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
    row("(Windows) run.ctl: the client is run with its words quoted and NOTHING redirected, its carriage returns are taken out, no Python stops with 12934, and only then is an unreachable helper judged",
        ordered(rc, "os.execute \"& '\" : ctl : \"' \" : qargs capturing out", "out = convert(char(13), '', out)", "if trim(out<1>)[1, 16] = 'error: nopython:' then", "stop sysmsg(12934)",
                "if trim(out) = '' or (trim(out<1>)[1, 7] # 'error: ' and (index(out, 'could not be reached', 1) or index(out, 'not found', 1)"), "")
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
    row("(Windows) set.ai finds its client in the program folder (K$WINPATH of /lib/sd-ai/sd-ai-ctl.ps1), never in the SD system directory; SD_AI_CTL overrides it for the tests only; a path holding a quote is refused",
        "if ctl = '' then ctl = kernel(K$WINPATH, '/lib/sd-ai/sd-ai-ctl.ps1')" in sa and "env('SD_AI_CTL')" in sa and not re.search(r"ctl\s*=[^\n]*@sdsys", sa) and sa.count("@sdsys") == 1
        and "index(ctl, \"'\", 1)" in sa, "")
    row("set.ai is in SDSYS's VOC only: voc_template has it as a verb for $setai and newvoc has no set.ai", t["voc_template"].split("\n")[:3] == ["V", "CA", "$setai"]
        and not os.path.exists(os.path.join(SD64, "sdsys", "newvoc", "set.ai")), "")
    need = [str(n) for n in range(12611, 12628)] + ["12934"]
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
    row("messages 12611 to 12627 and 12934 exist, one line each", not bad, repr(bad))
    row("12611 is 'Account %1 has ai %2', 12614 is the usage, 12613 does not name the program, and 12934 says the AI needs Python 3.13 or later for all users",
        open(os.path.join(MESSAGES, "12611")).read() == "Account %1 has ai %2\n" and "set.ai {" in open(os.path.join(MESSAGES, "12614")).read()
        and "sd-ai" not in open(os.path.join(MESSAGES, "12613")).read() and "Python 3.13 or later" in open(os.path.join(MESSAGES, "12934")).read(), "")


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
    row("the two help records exist (title, documentation page, a paragraph) and the page asks for both by their keys", all(len(t[k].strip().split("\n")) >= 3 and t[k].split("\n")[1] == "administrator-20-the-ai-helper" for k in ("h_prov", "h_acc"))
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
    c = code_only(t["helper"])
    cp = c[c.index("def create_pipe("):c.index("class JOBOBJECT_BASIC_LIMIT_INFORMATION")]
    row("the helper's pipe REJECTS REMOTE CLIENTS (PIPE_REJECT_REMOTE_CLIENTS, 0x8: a Windows pipe is reachable over the network otherwise) and its first instance is FILE_FLAG_FIRST_PIPE_INSTANCE",
        "0x00000008" in between(cp, "pipe_mode =", "\n") and "0x00080000 if first else 0" in cp and "PIPE_REJECT_REMOTE_CLIENTS" in t["helper"], "")
    sd = c[c.index("def pipe_sddl("):c.index("def create_pipe(")]
    row("the pipe's security: owner the helper's own account, a PROTECTED list (P:), SYSTEM and the helper full, sdusers and Administrators PIPE_CLIENT_MASK only, and PIPE_CLIENT_MASK is win32ai.c's AI_ACCESS (0x00120183)",
        'parts = ["O:%sD:P(A;;GA;;;SY)(A;;GA;;;%s)" % (me, me)]' in sd and 'parts.append("(A;;0x%08X;;;%s)" % (PIPE_CLIENT_MASK, sdusers))' in sd and 'parts.append("(A;;0x%08X;;;BA)" % PIPE_CLIENT_MASK)' in sd
        and "PIPE_CLIENT_MASK = 0x00120183" in c and sd.count("GA") == 2, "")
    pr = c[c.index("def peer("):c.index("def in_group(")]
    row("the caller is read by impersonating the pipe's client and REVERTING before anything else; a failed revert ends the process; LocalSystem, LocalService and NetworkService are no caller",
        ordered(pr, "if not adv.ImpersonateNamedPipeClient(h):", "return None", "try:", "OpenThreadToken(", "caller = read_token(tok)", "finally:", "if not adv.RevertToSelf():", "os._exit(5)",
                "if caller is None or caller.sid in SERVICE_SIDS:", "return None") and 'SERVICE_SIDS = ("S-1-5-18", "S-1-5-19", "S-1-5-20")' in c, "")
    ig = c[c.index("def in_group("):c.index("def is_sdsys(")]
    row("the gate is read LIVE at each request (NetLocalGroupGetMembers, the caller's own SID among the members) and every doubt is no", "netapi.NetLocalGroupGetMembers(None, group, 0," in ig
        and "if rc not in (0, 234):" in ig and ig.count("return True") == 1 and "if sid_text(psid) == sid:" in ig, "")
    dp = c[c.index("def dpapi("):c.index("def key_entropy(")]
    row("the key is DPAPI in the helper account's OWN scope (no CRYPTPROTECT_LOCAL_MACHINE, 0x4: any process on the machine could open a machine blob), no UI, with the provider's name as entropy",
        "crypt.CryptProtectData(ctypes.byref(din), None, ctypes.byref(ent), None, None, 0x1, ctypes.byref(out))" in dp and "0x4" not in dp and "0x5" not in dp
        and 'return ("sd-ai key " + name).encode("ascii")' in c, "")
    wk = c[c.index("def write_key("):c.index("def set_context(")]
    pc = c[c.index("def private_create("):c.index("def replace(")]
    row("write_key encrypts BEFORE it writes, into a file created with a protected list of this account and SYSTEM only (not one that inherits), then replaces the old one",
        ordered(wk, "blob = dpapi(key.encode(\"ascii\"), key_entropy(name), True)", "with private_create(tmp) as f:", "f.write(blob)", "replace(tmp, os.path.join(d, name))")
        and 'sddl = "O:%sD:P(A;;FA;;;SY)(A;;FA;;;%s)" % (me, me)' in pc, "")
    pf = c[c.index("def private_file("):c.index("def read_key(")]
    row("private_file allows only this account and SYSTEM, and refuses a list it cannot read or judge (no list, an entry of a kind not known)",
        "return sids is not None and me is not None and sids <= {me, SID_SYSTEM}" in pf and "if not dacl.value:" in c and "if hdr.AceType != 0:" in c, "")
    ls = c[c.index("class Listener:"):c.index("SERVICE_WIN32_OWN_PROCESS = 0x10")]
    row("the service loop makes the NEXT instance BEFORE it lets go of the connected one (there is never a moment with no instance of ours for another user to take the name), and each request "
        "process is put in a job that ends it when the service stops", ordered(ls, "ok = k32.ConnectNamedPipe(self.cur, None)", "nxt, err = create_pipe(self.name, False, self.sa)", "self.spawn(self.cur)", "self.cur = nxt")
        and ls.count("self.spawn(") == 1 and "k32.AssignProcessToJobObject(self.job, int(child._handle))" in ls and "info.BasicLimitInformation.LimitFlags = 0x00002000" in c, "")
    sv = c[c.index("def serve("):c.index("def flush_out(")]
    row("a request process ends itself if it runs far past its deadline (the watchdog, Linux's alarm), and the reply is flushed to the client before the process ends",
        "WATCHDOG = CONNECT_TIMEOUT + 300 + 5" in c and ordered(sv, "dog = threading.Timer(WATCHDOG, stuck)", "dog.start()", "reply, prov = handle(", "write_all(fd_out, data)", "flush_out(fd_out)"), "")
    k = code_only(t["ctl"])
    row("(Windows) sd-ai-ctl writes EVERYTHING to standard output (PowerShell 5.1 would wrap standard error in error records where set.ai reads 'error:') and checks the real pipe's owner before sending",
        "sys.stderr" not in k and "print(" not in k and "check_owner = path.lower() == DEFAULT_PIPE.lower()" in k
        and ordered(k, "def talk(path, req, check_owner):", "if check_owner and not owned_by_service(h):", "raise OSError", "k32.WriteFile("), "")
    wr = ps_only(t["wrapper"])
    row("(Windows) sd-ai-ctl.ps1 finds the all-users Python (sd-ai-python.ps1) and runs the client isolated (-I -B); with none it prints one 'error: nopython:' line and exits 1",
        ordered(wr, ". (Join-Path $PSScriptRoot 'sd-ai-python.ps1')", "$py = Find-SdPython", "if (-not $py) {", "Write-Output 'error: nopython: no Python 3.13 or later is installed for all users'", "exit 1",
                "& $py -I -B (Join-Path $PSScriptRoot 'sd-ai-ctl') @args"), "")
    fd = ps_only(t["finder"])
    row("(Windows) Find-SdPython reads HKLM PythonCore only (all users; a per-user Python is out of reach of the service), 3.13 or later, a python.exe that exists, and prints nothing",
        "'HKLM:\\SOFTWARE\\Python\\PythonCore'" in fd and "HKCU" not in fd and "[version]'3.13'" in fd and "Test-Path -LiteralPath $exe -PathType Leaf" in fd and "Write-Output" not in fd, "")


GROUP_A_MUTANTS = [
    ("helper", "certificate check off", "ctx.verify_mode = ssl.CERT_REQUIRED", "ctx.verify_mode = ssl.CERT_NONE"),
    ("helper", "host name check off", "ctx.check_hostname = True", "ctx.check_hostname = False"),
    ("helper", "http accepted", 'URL_RE = re.compile(r"^https://', 'URL_RE = re.compile(r"^https?://'),
    ("helper", "a query string is accepted in a URL", "(/[A-Za-z0-9._~/+,:-]{0,500})?$", "(/[A-Za-z0-9._~/+,:?=&-]{0,500})?$"),
    ("helper", "a program is started", "        flush_out(fd_out)\n            os._exit(4)", "        flush_out(fd_out)\n            os.system('x')\n            os._exit(4)"),
    ("helper", "the helper prints", "        serve(0, 1, state, providers, sys.stderr.write)\n", "        print('x')\n        serve(0, 1, state, providers, sys.stderr.write)\n"),
    ("helper", "the gate group is renamed", 'GATE_GROUP = "sdaiusers"', 'GATE_GROUP = "sdusers"'),
    ("helper", "the key is put in the log line", 'sd-ai: sid=%s provider=%s status=%s in=%s out=%s\\n" % (time.strftime("%Y-%m-%d %H:%M:%S"), uid,', 'sd-ai: key=%s sid=%s provider=%s status=%s in=%s out=%s\\n" % (time.strftime("%Y-%m-%d %H:%M:%S"), prov, uid,'),
    ("helper", "the key file is read before it is judged", "    if not private_file(path):\n        raise Refuse(\"nokey\", \"the key file is not private\")\n", ""),
    ("helper", "the hygiene runs after the size test", "        text, replaced = hygiene(text)\n        if len(text.encode(\"ascii\"))", "        if len(text.encode(\"ascii\", \"replace\"))"),
    ("helper", "the settings are checked for the administrator after they are done", '        if uid is None or not is_admin(uid):\n            return {"t": "err", "code": "noadmin", "msg": "only the administrator may change', '        if False:\n            return {"t": "err", "code": "noadmin", "msg": "only the administrator may change'),
    ("helper", "keyset echoes the key", 'return {"t": "ok", "key": "set"}', 'return {"t": "ok", "key": "set", "echo": key}'),
    ("helper", "the result of a setting is not checked before it is written", "            selected(new, table)", "            pass  #"),
    ("helper", "any Windows administrator may ask without the gate", "return caller is not None and (is_sdsys(caller) or in_group(caller.sid, GATE_GROUP))", "return caller is not None and (is_admin(caller) or in_group(caller.sid, GATE_GROUP))"),
    ("helper", "an unelevated administrator may change settings", "(caller.elevated and caller.admins)", "(caller.admins)"),
    ("providers", "an http URL in the table", "url=https://api.openai.com", "url=http://api.openai.com"),
    ("providers", "a model in the table", "[openai]\n", "[openai]\nmodel=gpt\n"),
    ("ctl", "the key is taken from the command line", "key = getpass.getpass(", "key = rest[1] if len(rest) > 1 else getpass.getpass("),
    ("ctl", "--handover reads the file only for a known provider", "        key = handover_key(rest[2])                                   # removed first, whatever follows\n        if rest[0] not in PROVIDERS:\n            say(\"sd-ai-ctl: the provider is one of %s\" % \", \".join(PROVIDERS))\n            return 2\n",
     "        if rest[0] not in PROVIDERS:\n            say(\"sd-ai-ctl: the provider is one of %s\" % \", \".join(PROVIDERS))\n            return 2\n        key = handover_key(rest[2])\n"),
    ("context", "the standing text says Linux", "About this system: SD Core for Windows", "About this system: SD Core for Linux"),
]
M_B = len(GROUP_A_MUTANTS)
GROUP_B_MUTANTS = [
    ("install", "the service runs as LocalSystem", "& $sc config $SvcName obj= $SvcAccount | Out-Null", "& $sc config $SvcName obj= LocalSystem | Out-Null"),
    ("install", "the service SID is not restricted", "& $sc sidtype $SvcName restricted | Out-Null", "& $sc sidtype $SvcName unrestricted | Out-Null"),
    ("install", "the keys directory admits Administrators", "& icacls $keys /inheritance:r /grant:r '*S-1-5-18:(OI)(CI)F' \"${SvcAccount}:(OI)(CI)M\" | Out-Null",
     "& icacls $keys /inheritance:r /grant:r '*S-1-5-18:(OI)(CI)F' \"${SvcAccount}:(OI)(CI)M\" '*S-1-5-32-544:(OI)(CI)F' | Out-Null"),
    ("install", "the service is made with no Python", "if (-not $py) {\n    # A service", "if ($false) {\n    # A service"),
    ("install", "the state is reset on an upgrade", "foreach ($d in @($state, $keys, $cnt)) {", "Remove-Item -LiteralPath $state -Recurse -Force\nforeach ($d in @($state, $keys, $cnt)) {"),
    ("iss", "the helper is set up before Python", "    PyMsg := InstallPython;\n    { 13 Nov 26 - RELEASE_1.1 246: the AI helper runs under that Python, so it follows it. }\n    AiMsg := InstallAiHelper;\n",
     "    AiMsg := InstallAiHelper;\n    PyMsg := InstallPython;\n"),
    ("iss", "the service is left at uninstall", "    Parameters: \"-NoProfile -NonInteractive -ExecutionPolicy Bypass -File \"\"{app}\\install-aihelper.ps1\"\" -Remove\"; \\\n", "    Parameters: \"-NoProfile\"; \\\n"),
    ("iss", "the group is left at uninstall", "  Exec(Net, 'localgroup sdaiusers /delete',    '', SW_HIDE, ewWaitUntilTerminated, Code);\n", ""),
    ("stage", "the helper is not staged", "AI_HELPER_FILES = ['sd-ai', ", "AI_HELPER_FILES = ["),
    ("groups", "sdaiusers is not made", "    $null     = Ensure-Group $AiGroup $AiComment\n", ""),
    ("createacc.h", "CA$AI shares a number", "$define CA$AI              41", "$define CA$AI              40"),
    ("createa", "ai-on is not a word", "         case upcase(token) = 'AI-ON'\n            settings<CA$AI> = 1\n", ""),
    ("acc_os_info", "the manifest has no route.ai", "   info<-1> = 'route.ai: ' : aiuse", "   info<-1> = 'route.x: ' : aiuse"),
    ("restorea", "route.ai is not restored", "      if m.route.ai = '1' then settings<CA$AI> = 1\n", ""),
    ("setai", "the administrator is not asked first", "   if not(kernel(K$ADMINISTRATOR, -1)) then\n      stop sysmsg(2001) ;* Command requires administrator privileges\n   end\n", ""),
    ("setai", "a semicolon is an allowed character", "0123456789._:/@+,-'", "0123456789._:/@+,-;'"),
    ("setai", "the key is captured by SD", "         os.execute \"& '\" : ctl : \"' 'key' '\" : prov : \"'\"\n", "         os.execute \"& '\" : ctl : \"' 'key' '\" : prov : \"'\" capturing keyout\n"),
    ("setai", "the whole URL goes to the audit trail", "' host=' : chost)", "' host=' : curl)"),
    ("setai", "the client is looked for in the SD system directory", "if ctl = '' then ctl = kernel(K$WINPATH, '/lib/sd-ai/sd-ai-ctl.ps1')", "if ctl = '' then ctl = @sdsys : @ds : 'bin' : @ds : 'sd-ai-ctl.ps1'"),
    ("setai", "the carriage returns are left in", "   out = convert(char(13), '', out)\n*  13 Nov 26 Windows port: the wrapper", "*  13 Nov 26 Windows port: the wrapper"),
    ("setai", "no Python is taken for an unreachable helper", "   if trim(out<1>)[1, 16] = 'error: nopython:' then\n      @system.return.code = -ER$FAILED\n      stop sysmsg(12934)                                                                  ;* The AI needs",
     "   if 0 then\n      @system.return.code = -ER$FAILED\n      stop sysmsg(12934)                                                                  ;* The AI needs"),
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
    ("h_acc", "the help record points at another page", "20-the-ai-helper", "01-accounts-and-security"),
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
    ("helper", "remote clients are let in", "0x00000000 | 0x00000000 | 0x00000000 | 0x00000008", "0x00000000 | 0x00000000 | 0x00000000 | 0x00000000"),
    ("helper", "the pipe's list is not protected", 'parts = ["O:%sD:P(A;;GA;;;SY)', 'parts = ["O:%sD:(A;;GA;;;SY)'),
    ("helper", "sdusers may make pipe instances", 'parts.append("(A;;0x%08X;;;%s)" % (PIPE_CLIENT_MASK, sdusers))', 'parts.append("(A;;GA;;;%s)" % sdusers)'),
    ("helper", "the thread is not reverted", "        if not adv.RevertToSelf():\n            os._exit(5)", "        pass"),
    ("helper", "LocalSystem is a caller", 'SERVICE_SIDS = ("S-1-5-18", "S-1-5-19", "S-1-5-20")', 'SERVICE_SIDS = ("S-1-5-19", "S-1-5-20")'),
    ("helper", "the key is a machine blob", "None, None, 0x1, ctypes.byref(out))\n    else:", "None, None, 0x5, ctypes.byref(out))\n    else:"),
    ("helper", "a list of any kind passes", "            if hdr.AceType != 0:                          # anything but a plain ALLOW", "            if False:                          # anything but a plain ALLOW"),
    ("helper", "the connected instance is let go before the next is made", "            self.reap()\n            nxt = None\n", "            self.spawn(self.cur)\n            self.reap()\n            nxt = None\n"),
    ("helper", "no watchdog", "        dog.start()\n", ""),
    ("ctl", "the client trusts any pipe's owner", "        if check_owner and not owned_by_service(h):", "        if False:"),
    ("ctl", "the client's errors go to standard error", "def say(s):\n    sys.stdout.write(s + \"\\n\")", "def say(s):\n    sys.stderr.write(s + \"\\n\")"),
    ("wrapper", "no Python is not said", "    Write-Output 'error: nopython: no Python 3.13 or later is installed for all users'\n", ""),
    ("wrapper", "the client is not isolated", "& $py -I -B (Join-Path", "& $py (Join-Path"),
    ("finder", "a per-user Python is used", "'HKLM:\\SOFTWARE\\Python\\PythonCore'", "'HKCU:\\SOFTWARE\\Python\\PythonCore'"),
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
