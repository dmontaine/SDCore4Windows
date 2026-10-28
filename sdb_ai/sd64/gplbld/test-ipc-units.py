#!/usr/bin/env python3
# test-ipc-units.py - W.11 F10 (security-model evaluation, 24 Oct 2026): what a process takes from the file $ipc.  FREE CHECK, text only (comments removed), no
# install, no sudo, no sd.
#
#   python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/test-ipc-units.py
#   python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/test-ipc-units.py --selftest      (mutants: each must be caught by the row it names)
#
# $ipc is a hashed file in the system directory that every SD user's process writes (its %0 and %1 are sdsys:sdusers 0775), so an SD user with an operating-system
# shell can write it.  Every program that names it was read; each is one of these (the INVENTORY below, which a program not in it fails):
#
#   sealed    cproc  - the Xn, Dn and Ln records of a phantom's start-up: what it runs, stacks and sets.  PHANTOM seals them with a secret that only the process it
#                      starts is given (its environment); CPROC reads them in ONE place and uses nothing unless the seal checks (!ipc_seal)
#   display   hsm, pstat, profiler, message, _message, _getmsg, cproc (the Mn messages and the Pn register) - what is read is shown, never run, stacked or set
#   own       login, apisrvr - delete the records of their own user number at start-up
#   writer    the kernel (hsm, status and profiler tables), bbproc (makes the file), syscom.h (the slot)
#   unsealed  debug, pdbg, pdebug - the phantom debugger's conversation.  NOT SEALED: it is trusted as the rest of the shared segment is (08-sd-installation).
#             A change that seals it flips its line in the INVENTORY; until then the row says it is not
#
#   I  the inventory: which programs name the file, that the display ones run nothing, what login and apisrvr touch, what the kernel does with it
#   K  the kernel: key 144, the secret's shape, K_PHANTOM_NONCE 'S' and 'G', op_phantom's environment, the import, the secret printed nowhere
#   B  PHANTOM: the secret and the seal are made before anything is created, staged under the lock, the Xn record carries the seal, the secret is written nowhere
#   C  CPROC: the three records are read in one place under the lock, the check uses the process's own secret, a missing or failing check drops all four values,
#      and nothing is run, stacked or set before the refusal is looked at
#   S  !ipc_seal: the four values in hexadecimal in order, HMAC-SHA256 keyed by the secret, compared in constant time, 1 only after the comparison
#   M  the messages and the unique catalogue name
# NOT SAID HERE: that the phantom refuses a record it was not sealed with - that is sandbox-ipc.py.  What needs a SECOND operating-system user (the environment
# of a process is readable only by its own user) is the VM's.
import glob
import os
import re
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, ".."))
passed = failed = 0

# program (or header) in sdsys/gpl.bp that names the file in code -> its part
INVENTORY = {
    "apisrvr": "own", "login": "own", "bbproc": "writer", "syscom.h": "writer",
    "phantom": "sealed", "cproc": "sealed",
    "hsm": "display", "pstat": "display", "profiler": "display", "message": "display", "_message": "display", "_getmsg": "display",
    "debug": "unsealed", "pdbg": "unsealed", "pdebug": "unsealed",
    "upgrade_nocase": "skipped",      # 28 Oct 26 Windows port: the upgrade walk leaves $ipc alone (the service holds it open); it reads and writes nothing in it
}
DISPLAY_ONLY = ["hsm", "pstat", "profiler", "message", "_message", "_getmsg"]


def row(label, ok, detail=""):
    """LABEL starts with the row's id (I1, K3a ...), which a mutant names."""
    global passed, failed
    if ok:
        passed += 1
        print("  [PASS] " + label)
    else:
        failed += 1
        print("  [FAIL] %s%s" % (label, ("   <- " + detail) if detail else ""))


def path_of(rel):
    return os.environ.get("IPC_" + re.sub(r"\W", "_", rel).upper()) or os.path.join(ROOT, rel)


def raw(rel):
    with open(path_of(rel), encoding="latin-1") as f:
        return f.read()


def bas(name):
    """A gpl.bp program (or header) without its comment lines and trailing ;* comments."""
    out = []
    for ln in raw("sdsys/gpl.bp/" + name).split("\n"):
        st = ln.strip()
        if st.startswith("*") or st.startswith("!"):
            continue
        out.append(re.sub(r";\*.*$", "", ln).rstrip())
    return "\n".join(out)


def csrc(name):
    s = raw("gplsrc/" + name)
    s = re.sub(r"/\*.*?\*/", "", s, flags=re.S)
    return re.sub(r"//[^\n]*", "", s)


def func(src, head):
    m = re.search(re.escape(head) + r"[^;{]*\{.*?\n\}", src, re.S)
    return m.group(0) if m else ""


def between(src, a, b):
    i = src.find(a)
    j = src.find(b, i + len(a)) if i >= 0 else -1
    return src[i:j] if i >= 0 and j >= 0 else ""


def ordered(text, *parts):
    """True when every part is in TEXT and the first occurrences are in the order given."""
    at = -1
    for p in parts:
        i = text.find(p)
        if i < 0 or i < at:
            return False
        at = i
    return True


def no_strings(s):
    return re.sub(r"'[^'\n]*'|\"[^\"\n]*\"", "''", s)


def gplbp_names():
    return sorted(n for n in os.listdir(os.path.join(ROOT, "sdsys", "gpl.bp")) if os.path.isfile(os.path.join(ROOT, "sdsys", "gpl.bp", n)))


def run():
    # --- I -------------------------------------------------------------------------------------------------------------------
    named = [n for n in gplbp_names() if re.search(r"ipc\.f|\$ipc|syscom\.ipc", bas(n), re.I)]
    row("I0 NULL CASE: the reader sees the programs (at least 12 name the file, cproc is not empty)", len(named) >= 12 and len(bas("cproc")) > 50000, repr(len(named)))
    optional = {"upgrade_nocase"}      # 28 Oct 26 Windows port: SD Core has it, Solo does not carry it; every other program must be present
    row("I1 the programs that name $ipc are exactly the inventory (a new one must be classified here first)", sorted(named) == sorted(n for n in INVENTORY if n not in optional or n in named),
        "new: %s; gone: %s" % (sorted(set(named) - set(INVENTORY)), sorted(set(INVENTORY) - set(named) - optional)))
    bad = []
    for n in DISPLAY_ONLY:
        t = no_strings(bas(n))
        if re.search(r"(^\s*|\bthen\s+|\belse\s+)(execute|perform|chain|data)\b", t, re.I | re.M):
            bad.append(n)
        if "K$SET.OPTIONS" in t or "ipc_seal" in t:
            bad.append(n + "(!)")
    row("I2 the display programs (%s) run, stack and set nothing" % ", ".join(DISPLAY_ONLY), not bad, repr(bad))
    own = [r"^openpath @sdsys:@ds:'\$ipc' to ipc\.f then$", r"^(recordlocku|delete) ipc\.f ?, ?'[MP]':@userno$", r"^void fcontrol(\.int)?\(ipc\.f, FCI?\$NON\.TXN, 0\)$"]      # 28 Oct 26 Windows port: SD Core Solo's login spells the call without .int
    odd = []
    for n in ("login", "apisrvr"):
        for ln in bas(n).split("\n"):
            ln = re.sub(r"\s+", " ", ln.strip())
            if re.search(r"ipc\.f|\$ipc", ln) and not any(re.search(p, ln) for p in own):
                odd.append(n + ": " + ln[:80])
    row("I3 login and apisrvr touch only the M and P records of their own user number", not odd, repr(odd))
    kc = csrc("kernel.c")
    holders = [os.path.basename(p) for p in sorted(glob.glob(os.path.join(ROOT, "gplsrc", "*.c"))) if "SYSCOM_IPC" in csrc(os.path.basename(p))]
    row("I4 only kernel.c uses the slot, three times, and only to dh_write the tables it was asked for (no dh_read of it)",
        holders == ["kernel.c"] and kc.count("SYSCOM_IPC") == 3 and kc.count("dh_write(dh_file") == 3 and "dh_read(" not in kc, repr((holders, kc.count("SYSCOM_IPC"))))
    seal_users = sorted(n for n in gplbp_names() if "ipc_seal" in bas(n) and n != "ipc_seal")
    row("I5 the sealed programs are PHANTOM and CPROC alone, and the debugger (%s) is still NOT sealed, as the inventory says" % "debug, pdbg, pdebug",
        seal_users == ["cproc", "phantom"], repr(seal_users))

    # --- K -------------------------------------------------------------------------------------------------------------------
    kh, bk, opk = csrc("keys.h"), bas("int$keys.h"), csrc("op_kernel.c")
    row("K1 the key is 144 in the kernel's keys.h and in int$keys.h, and no other key has that number",
        bool(re.search(r"#define K_PHANTOM_NONCE\s+144\b", kh)) and bool(re.search(r"\$define K\$PHANTOM\.NONCE\s+144\b", bk))
        and len(re.findall(r"#define K_\w+\s+144\b", kh)) == 1 and len(re.findall(r"\$define K\$[\w.]+\s+144\b", bk)) == 1)
    row("K2a the secret is 16 to 64 characters", "#define PHANTOM_NONCE_MIN 16" in opk and "#define PHANTOM_NONCE_MAX 64" in opk)
    fv = func(opk, "Private bool phantom_nonce_valid(const char *t)")
    row("K2b phantom_nonce_valid() refuses a length outside the two bounds and any character outside A-Z a-z 0-9 + / =",
        bool(fv) and "(len < PHANTOM_NONCE_MIN) || (len > PHANTOM_NONCE_MAX)" in fv and all(t in fv for t in ("'A'", "'Z'", "'a'", "'z'", "'0'", "'9'", "c == '+'", "c == '/'", "c == '='"))
        and fv.count("return FALSE") == 2 and "return TRUE" in fv, fv[:200])
    cs = between(opk, "case K_PHANTOM_NONCE:", "case K_PROFILER:")      # 28 Oct 26 Windows port: K_LOCK_TRACE is not carried, the next case is K_PROFILER
    row("K3a 'S' empties the staged secret, then stages the text after it only if phantom_nonce_valid() says so", ordered(cs, "s[0] == 'S'", "phantom_nonce_next[0] = '\\0'", "phantom_nonce_valid(s + 1)", "strcpy(phantom_nonce_next, s + 1)"), cs[:200])
    row("K3b 'G' answers the secret this process was started with, for the argument 'G' alone", "(s[0] == 'G') && (s[1] == '\\0')" in cs and "k_put_c_string(phantom_nonce_mine, &result)" in cs)
    row("K3c the staged secret is never answered or printed: 5 mentions (declaration, 'S' twice, op_phantom twice) and no k_put_c_string of it",
        opk.count("phantom_nonce_next") == 5 and "k_put_c_string(phantom_nonce_next" not in opk, str(opk.count("phantom_nonce_next")))
    fp = func(opk, "void op_phantom()")
    row("K4a op_phantom() makes the child's environment from the staged secret BEFORE it reserves the user cell and forks",
        bool(fp) and ordered(fp, "phantom_child_environment(phantom_nonce_next", "StartExclusive(SHORT_CODE, 38)", "fork()"), fp[:200])
    row("K4b ... and clears the staged secret at once, before it can fail (one phantom() only)", ordered(fp, "phantom_child_environment(phantom_nonce_next", "phantom_nonce_next[0] = '\\0'", "if (child_env == NULL)", "StartExclusive"))
    row("K4c ... the child is started with execle() and that environment, never execl()", "execle(path, path, option, (char *)NULL, child_env)" in fp and "execl(" not in fp.replace("execle(", ""))
    row("K4d ... nothing in it, or in the function that builds the environment, calls setenv() or putenv(): this process's own environment is never changed",
        "setenv(" not in fp and "putenv(" not in fp and "setenv(" not in func(opk, "Private char **phantom_child_environment(const char *nonce, char *buf, size_t bufsz)"))
    row("K4e ... and the array is freed after the exit label", ordered(fp, "exit_op_phantom:", "free(child_env)"))
    fe = func(opk, "Private char **phantom_child_environment(const char *nonce, char *buf, size_t bufsz)")
    row("K5 the environment copy leaves out any SD_PHANTOM_NONCE already in this process's and adds one only for a non-empty secret",
        bool(fe) and 'if (strncmp(environ[k], PHANTOM_NONCE_ENV "=", sizeof(PHANTOM_NONCE_ENV)) != 0)' in fe and "env[m++] = environ[k];" in fe
        and "if (nonce[0] != '\\0')" in fe and "env[m] = NULL;" in fe, fe[:200])
    fi = func(opk, "void phantom_nonce_import(void)")
    row("K6a phantom_nonce_import() takes the variable, keeps it only if it is of the right shape, WIPES the string where it stands (unsetenv drops only the pointer; the string is what /proc/<pid>/environ shows) and removes it from the environment either way",
        bool(fi) and "getenv(PHANTOM_NONCE_ENV)" in fi and bool(re.search(r"if \(phantom_nonce_valid\(p\)\)\s*strcpy\(phantom_nonce_mine, p\);\s*(?:/\*.*?\*/\s*)?memset\(\(char \*\)p, 0, strlen\(p\)\);\s*unsetenv\(PHANTOM_NONCE_ENV\);", fi, re.S)), fi[:300])
    i_tio, i_imp, i_retry = kc.find("tio_init()"), kc.find("phantom_nonce_import();"), kc.find("retry_login:")
    row("K6b kernel.c calls it for a phantom only, after tio_init() and before the first user table work",
        bool(re.search(r"if \(is_phantom\)\s*phantom_nonce_import\(\);", kc)) and 0 < i_tio < i_imp < i_retry, "%d %d %d" % (i_tio, i_imp, i_retry))
    bad = []
    for p in sorted(glob.glob(os.path.join(ROOT, "gplsrc", "*.c"))):
        n = os.path.basename(p)
        for ln in csrc(n).split("\n"):
            if re.search(r"phantom_nonce_|PHANTOM_NONCE_ENV|SD_PHANTOM_NONCE", ln) and re.search(r"printf\(|log_message|k_error|audit_message|syslog|fputs|puts\(", ln) and "snprintf(buf, bufsz" not in ln:
                bad.append("%s: %s" % (n, ln.strip()[:70]))
    others = [os.path.basename(p) for p in sorted(glob.glob(os.path.join(ROOT, "gplsrc", "*.c")))
              if os.path.basename(p) != "op_kernel.c" and re.search(r"SD_PHANTOM_NONCE|phantom_nonce_(?!import\b)", csrc(os.path.basename(p)))]
    row("K7 the secret is printed, logged and audited nowhere, and no other C source names it", not bad and not others, repr((bad, others)))
    row("K8 no shipped BASIC program reads the variable by name", not [n for n in gplbp_names() if "SD_PHANTOM_NONCE" in bas(n)])

    # --- B -------------------------------------------------------------------------------------------------------------------
    ph = bas("phantom")
    row("B0 NULL CASE: phantom is read (it holds the verb's two writes)", "to ipc.f, 'X':uid" in ph and len(ph) > 3000)
    row("B1 the secret, then the seal, are made before the lock; the secret is staged under the lock; then phantom(); then the Xn record; then the unlock",
        ordered(ph, "SDEXT('24', @TRUE, SD_RANDBYTES)", "ipc_seal('make'", "if seal = '' then", "filelock ipc.f", "kernel(K$PHANTOM.NONCE, 'S':nonce)", "uid = phantom()",
                "to ipc.f, 'X':uid") and ph.rfind("fileunlock ipc.f") > ph.find("to ipc.f, 'X':uid") > 0, "")
    row("B2 the Xn record is the seal, the option flags and the command, in that order, and is the only record of that name PHANTOM writes",
        "write seal:@fm:opt.s:@fm:ph.command to ipc.f, 'X':uid" in ph and ph.count("to ipc.f, 'X':") == 1)
    row("B3 the seal is made from exactly the values written: the flags, the command, the DATA queue and the log file name",
        "seal = ipc_seal('make', nonce, '', opt.s, ph.command, dq, log.file)" in ph and "dq = if pass.data then @data.pending else ''" in ph
        and "write dq to ipc.f, 'D':uid" in ph and "write log.file to ipc.f, 'L':uid" in ph)
    lines = [ln.strip() for ln in ph.split("\n") if re.search(r"\bnonce\b", ln)]
    ok_lines = [l for l in lines if l.startswith(("nonce = SDEXT(", "seal = ipc_seal(", "if kernel(K$PHANTOM.NONCE, 'S':nonce)"))]
    row("B4 the secret is mentioned in three lines only (made, sealed with, staged) and never in a line that touches $ipc", len(lines) == 3 and len(ok_lines) == 3 and not [l for l in lines if "ipc.f" in l], repr(lines))
    blk = between(ph, "if kernel(K$PHANTOM.NONCE, 'S':nonce) # 1 then", "if req.user # '' then void kernel(K$PHANTOM.USER")
    row("B5 a stage that is refused gives the lock back and stops with message 12951", ordered(blk, "fileunlock ipc.f", "stop sysmsg(12951)"), blk[:120])
    blk = between(ph, "if seal = '' then", "filelock ipc.f")
    row("B6 no seal, no process: PHANTOM stops with 12951 before the lock", "stop sysmsg(12951)" in blk, blk[:120])

    # --- C -------------------------------------------------------------------------------------------------------------------
    cp = bas("cproc")
    sub = between(cp, "read.phantom.cargo:\n", "\n   return\n")
    row("C0 NULL CASE: the subroutine is found and holds the three reads", bool(sub) and sub.count("read ph.") == 3, sub[:100])
    outside = cp.replace(sub, "")
    row("C1 the Xn, Dn and Ln records are read in that one place: nowhere else does cproc name them",
        sub.count("'X':@userno") == 2 and sub.count("'D':@userno") == 2 and sub.count("'L':@userno") == 2 and "'X':@userno" not in outside and "'D':@userno" not in outside and "'L':@userno" not in outside
        and "read phantom.command from ipc.f" not in cp and "read ph.data from ipc.f" not in outside)
    row("C2 the check is made with the secret THIS process was started with, over the values it read, and it is the only call",
        "ipc_seal('check', kernel(K$PHANTOM.NONCE, 'G'), ph.rec<1>, ph.opts, phantom.command, ph.data, ph.log.file)" in sub and cp.count("ipc_seal('") == 1
        and cp.count("kernel(K$PHANTOM.NONCE") == 1)
    row("C3a an absent Xn record is refused, and so is a seal that does not check", bool(re.search(r"if ph\.rec = '' then\s*ph\.refused = @true\s*end else\s*if not\(ipc_seal\('check'.*\) then ph\.refused = @true", sub, re.S)), sub[:200])
    blk = sub[sub.find("if ph.refused then"):] if "if ph.refused then" in sub else ""
    row("C3b a refusal blanks the option flags, the command, the DATA queue and the log file name", all(("%s = ''" % v) in blk for v in ("ph.opts", "phantom.command", "ph.data", "ph.log.file")), blk[:200])
    row("C4a the cargo is read under the lock and before the COMO log is opened (the log file name comes from it)",
        ordered(cp, "filelock ipc.f\n         gosub read.phantom.cargo\n         fileunlock ipc.f", 'execute "COMO ON PH"'), "")
    row("C4b nothing is run, stacked or set before the refusal is looked at: the refusal, then the options, then the DATA lines, then the command",
        ordered(cp, "if ph.refused then", "kernel(K$SET.OPTIONS, ph.opts)", "data ph.data<ph.i>", "at.command = phantom.command"))
    ref = between(cp, "if ph.refused then\n            message", "if ph.opts # ''")
    row("C5 a refusal says so (12952), writes 'phantom refused' to the audit trail and ends the phantom through terminate.phantom",
        "sysmsg(12952, @userno)" in ref and "kernel(K$AUDIT, 'phantom refused phantom=' : @userno" in ref and "goto terminate.phantom" in ref, ref[:200])
    row("C6 the option flags come only from ph.opts, once, and a DATA line from ph.data (the other DATA statement is the command paragraph's own)",
        cp.count("kernel(K$SET.OPTIONS") == 1 and "kernel(K$SET.OPTIONS, ph.opts)" in cp and sorted(re.findall(r"^\s*data\s+(\S+)", cp, re.M)) == ["ph.data<ph.i>", "s"])
    row("C7 the lock is on while the three are read", "ph.log.file = ''\n         filelock ipc.f\n         gosub read.phantom.cargo" in cp)

    # --- S -------------------------------------------------------------------------------------------------------------------
    sl = bas("ipc_seal")
    raws = raw("sdsys/gpl.bp/ipc_seal")
    row("S0 NULL CASE: ipc_seal is read, internal, catalogued as !ipc_seal", "$internal" in sl and "$catalog !ipc_seal" in raws and "function ipc_seal(" in sl)
    row("S1 a secret shorter than 16 characters answers 0 for 'check' and the null string for 'make'", bool(re.search(r"if len\(nonce\) < 16 then\s*if checking then return 0\s*return ''\s*end", sl)))
    row("S2 the signed text is the four values in hexadecimal, in the order flags, command, DATA, log file, joined by colons",
        "signed = oconv(opt, 'MX0C') : ':' : oconv(cmd, 'MX0C') : ':' : oconv(dq, 'MX0C') : ':' : oconv(logf, 'MX0C')" in sl)
    row("S3a the seal is HMAC-SHA256 keyed by the secret", "mac = SDEXT(nonce : @FM : signed, @TRUE, SD_HMACSHA256)" in sl)
    row("S3b 'check' answers 0 for a missing seal or mac, compares in constant time, and returns 1 only after that comparison",
        "if not(checking) then return mac" in sl and "if mac = '' or seal = '' then return 0" in sl and "if SDEXT(mac : @FM : seal, @TRUE, SD_CTEQUAL) = '1' then return 1" in sl
        and sl.count("return 1") == 1 and ordered(sl, "SD_CTEQUAL", "return 1"))

    # --- M -------------------------------------------------------------------------------------------------------------------
    m6, m7 = raw("sdsys/messages/12951"), raw("sdsys/messages/12952")
    row("M1 messages 12951 and 12952 are there, 12952 takes the phantom's number and says nothing was run",
        len(m6.strip()) > 20 and "%1" in m7 and "nothing was run" in m7 and "not from the process that started it" in m7, repr((m6[:40], m7[:60])))
    names = []
    for n in gplbp_names():
        names += [c.lower() for c in re.findall(r"^\$catalog\s+(\S+)", raw("sdsys/gpl.bp/" + n), re.M | re.I)]
    row("M2 the catalogue name !ipc_seal is held by one program", names.count("!ipc_seal") == 1, str(names.count("!ipc_seal")))
    print("test-ipc-units: %d passed, %d failed" % (passed, failed))
    return 0 if failed == 0 else 1


# (name, file under sd64, old text, new text, the row that must fail).  Each takes one safeguard out or puts one read back.
MUTANTS = [
    # the inventory
    ("new-program-names-ipc", "sdsys/gpl.bp/ipc_seal", "$internal\nfunction ipc_seal(", "$internal\n   read zz from ipc.f, 'X'\nfunction ipc_seal(", "I1"),
    ("display-program-runs-a-record", "sdsys/gpl.bp/hsm", '   parser = "!PARSER"\n', '   parser = "!PARSER"\n   execute s\n', "I2"),
    ("display-program-sets-options", "sdsys/gpl.bp/pstat", '   parser = "!PARSER"\n', '   parser = "!PARSER"\n   void kernel(K$SET.OPTIONS, s)\n', "I2"),
    ("login-deletes-another-record", "sdsys/gpl.bp/login", "delete ipc.f, 'M':@userno", "delete ipc.f, 'X':@userno", "I3"),
    ("kernel-reads-the-ipc-file", "gplsrc/kernel.c", '        sprintf(id, "F%d", (int)process.user_no);', '        sprintf(id, "F%d", (int)process.user_no);\n        dh_read(dh_file, id, strlen(id));', "I4"),
    ("debugger-seals-with-no-inventory-change", "sdsys/gpl.bp/pdbg", "      debug.initialised = @true", "      zz = ipc_seal('check', '', '', '', '', '', '')\n      debug.initialised = @true", "I5"),
    # the kernel
    ("key-renumbered", "gplsrc/keys.h", "#define K_PHANTOM_NONCE      144", "#define K_PHANTOM_NONCE      143", "K1"),
    ("minimum-length-gone", "gplsrc/op_kernel.c", "#define PHANTOM_NONCE_MIN 16", "#define PHANTOM_NONCE_MIN 1", "K2a"),
    ("no-length-minimum", "gplsrc/op_kernel.c", "if ((len < PHANTOM_NONCE_MIN) || (len > PHANTOM_NONCE_MAX))", "if (len > PHANTOM_NONCE_MAX)", "K2b"),
    ("plus-allowed-no-more", "gplsrc/op_kernel.c", " || (c == '+') ||", " ||", "K2b"),
    ("stage-without-checking", "gplsrc/op_kernel.c", "        if (phantom_nonce_valid(s + 1)) {", "        if (1) {", "K3a"),
    ("stage-does-not-empty", "gplsrc/op_kernel.c", "        phantom_nonce_next[0] = '\\0';\n        if (phantom_nonce_valid(s + 1)) {", "        if (phantom_nonce_valid(s + 1)) {", "K3a"),
    ("get-answers-the-staged-secret", "gplsrc/op_kernel.c", "k_put_c_string(phantom_nonce_mine, &result);", "k_put_c_string(phantom_nonce_next, &result);", "K3b"),
    ("get-takes-anything-starting-with-g", "gplsrc/op_kernel.c", "((s[0] == 'G') && (s[1] == '\\0'))", "(s[0] == 'G')", "K3b"),
    ("staged-secret-kept-after-use", "gplsrc/op_kernel.c", "  phantom_nonce_next[0] = '\\0';\n  if (child_env == NULL)", "  if (child_env == NULL)", "K3c"),
    ("staged-secret-cleared-after-the-cell", "gplsrc/op_kernel.c", "  phantom_nonce_next[0] = '\\0';\n  if (child_env == NULL)\n    goto exit_op_phantom;\n\n  StartExclusive(SHORT_CODE, 38);",
     "  if (child_env == NULL)\n    goto exit_op_phantom;\n\n  StartExclusive(SHORT_CODE, 38);\n  phantom_nonce_next[0] = '\\0';", "K4b"),
    ("environment-made-after-the-cell", "gplsrc/op_kernel.c", "  child_env = phantom_child_environment(phantom_nonce_next, nonce_var, sizeof(nonce_var));\n  phantom_nonce_next[0] = '\\0';\n  if (child_env == NULL)\n    goto exit_op_phantom;\n\n  StartExclusive(SHORT_CODE, 38);",
     "  StartExclusive(SHORT_CODE, 38);\n  child_env = phantom_child_environment(phantom_nonce_next, nonce_var, sizeof(nonce_var));\n  phantom_nonce_next[0] = '\\0';\n  if (child_env == NULL)\n    goto exit_op_phantom;", "K4a"),
    ("execl-with-the-parents-environment", "gplsrc/op_kernel.c", "execle(path, path, option, (char *)NULL, child_env);", "execl(path, path, option, NULL);", "K4c"),
    ("parent-sets-its-own-environment", "gplsrc/op_kernel.c", "  child_env = phantom_child_environment(phantom_nonce_next, nonce_var, sizeof(nonce_var));\n",
     "  setenv(PHANTOM_NONCE_ENV, phantom_nonce_next, 1);\n  child_env = phantom_child_environment(phantom_nonce_next, nonce_var, sizeof(nonce_var));\n", "K4d"),
    ("environment-array-leaks", "gplsrc/op_kernel.c", "  free(child_env);", "  (void)child_env;", "K4e"),
    ("old-secret-passed-on", "gplsrc/op_kernel.c", 'if (strncmp(environ[k], PHANTOM_NONCE_ENV "=", sizeof(PHANTOM_NONCE_ENV)) != 0)', "if (1)", "K5"),
    ("no-secret-for-an-unstaged-phantom-forgotten", "gplsrc/op_kernel.c", "  if (nonce[0] != '\\0') {\n    snprintf(buf, bufsz", "  if (1) {\n    snprintf(buf, bufsz", "K5"),
    ("import-leaves-the-variable", "gplsrc/op_kernel.c", "    unsetenv(PHANTOM_NONCE_ENV);\n", "", "K6a"),
    ("import-does-not-wipe-the-string", "gplsrc/op_kernel.c", "    memset((char *)p, 0, strlen(p));\n", "", "K6a"),
    ("import-for-every-process", "gplsrc/kernel.c", "  if (is_phantom)\n    phantom_nonce_import();", "  phantom_nonce_import();", "K6b"),
    ("import-prints-the-secret", "gplsrc/op_kernel.c", "      strcpy(phantom_nonce_mine, p);\n", '      strcpy(phantom_nonce_mine, p);\n    tio_printf("%s", phantom_nonce_mine);\n', "K7"),
    ("second-file-names-the-variable", "gplsrc/kernel.c", "void phantom_nonce_import(void); /* op_kernel.c */", 'void phantom_nonce_import(void); /* op_kernel.c SD_PHANTOM_NONCE */\nstatic const char *zz_name = "SD_PHANTOM_NONCE";', "K7"),
    ("basic-reads-the-variable", "sdsys/gpl.bp/ipc_seal", "   set.status 0\n", "   set.status 0\n   zz = env('SD_PHANTOM_NONCE')\n", "K8"),
    # PHANTOM
    ("secret-is-constant", "sdsys/gpl.bp/phantom", "      nonce = SDEXT('24', @TRUE, SD_RANDBYTES)", "      nonce = 'QUJDREVGR0hJSktMTU5PUFFSU1RVVldY'", "B1"),
    ("lock-taken-before-the-seal", "sdsys/gpl.bp/phantom", "      opt.s = if option(OPT.INHERIT)", "      filelock ipc.f\n      opt.s = if option(OPT.INHERIT)", "B1"),
    ("record-carries-no-seal", "sdsys/gpl.bp/phantom", "write seal:@fm:opt.s:@fm:ph.command to ipc.f, 'X':uid", "write opt.s:@fm:ph.command to ipc.f, 'X':uid", "B2"),
    ("seal-without-the-data", "sdsys/gpl.bp/phantom", "seal = ipc_seal('make', nonce, '', opt.s, ph.command, dq, log.file)", "seal = ipc_seal('make', nonce, '', opt.s, ph.command, '', log.file)", "B3"),
    ("data-not-captured-before-the-lock", "sdsys/gpl.bp/phantom", "      dq = if pass.data then @data.pending else ''", "      dq = ''", "B3"),
    ("secret-written-to-ipc", "sdsys/gpl.bp/phantom", "      write seal:@fm:opt.s:@fm:ph.command to ipc.f, 'X':uid", "      write nonce to ipc.f, 'N':uid\n      write seal:@fm:opt.s:@fm:ph.command to ipc.f, 'X':uid", "B4"),
    ("stage-refused-keeps-the-lock", "sdsys/gpl.bp/phantom", "         fileunlock ipc.f\n         @system.return.code = -ER$PROCESS\n         stop sysmsg(12951)\n      end\n\n      if req.user",
     "         @system.return.code = -ER$PROCESS\n         stop sysmsg(12951)\n      end\n\n      if req.user", "B5"),
    ("no-seal-still-starts", "sdsys/gpl.bp/phantom", "      if seal = '' then\n         @system.return.code = -ER$PROCESS\n         stop sysmsg(12951)\n      end", "      if 0 then\n         @system.return.code = -ER$PROCESS\n         stop sysmsg(12951)\n      end", "B6"),
    ("secret-never-staged", "sdsys/gpl.bp/phantom", "      if kernel(K$PHANTOM.NONCE, 'S':nonce) # 1 then", "      if 0 then", "B1"),
    # CPROC
    ("second-reader-of-the-record", "sdsys/gpl.bp/cproc", "         ph.log.file = trim(ph.log.file)\n", "         ph.log.file = trim(ph.log.file)\n         read zz from ipc.f, 'X':@userno else null\n", "C1"),
    ("check-uses-the-record-as-secret", "sdsys/gpl.bp/cproc", "ipc_seal('check', kernel(K$PHANTOM.NONCE, 'G'), ph.rec<1>,", "ipc_seal('check', ph.rec<1>, ph.rec<1>,", "C2"),
    ("check-over-fewer-values", "sdsys/gpl.bp/cproc", "ph.opts, phantom.command, ph.data, ph.log.file)) then ph.refused", "ph.opts, phantom.command, '', ph.log.file)) then ph.refused", "C2"),
    ("check-never-refuses", "sdsys/gpl.bp/cproc", "if not(ipc_seal('check',", "if 0 and not(ipc_seal('check',", "C3a"),
    ("absent-record-accepted", "sdsys/gpl.bp/cproc", "   if ph.rec = '' then\n      ph.refused = @true\n   end else", "   if ph.rec = '' then\n      null\n   end else", "C3a"),
    ("refusal-keeps-the-options", "sdsys/gpl.bp/cproc", "      ph.opts = ''\n      phantom.command = ''\n", "      phantom.command = ''\n", "C3b"),
    ("refusal-keeps-the-command", "sdsys/gpl.bp/cproc", "      phantom.command = ''\n      ph.data = ''\n      ph.log.file = ''\n   end\n", "      ph.data = ''\n      ph.log.file = ''\n   end\n", "C3b"),
    ("refusal-keeps-the-data", "sdsys/gpl.bp/cproc", "      ph.data = ''\n      ph.log.file = ''\n   end\n\n   return", "      ph.log.file = ''\n   end\n\n   return", "C3b"),
    ("refusal-keeps-the-log-file", "sdsys/gpl.bp/cproc", "      ph.log.file = ''\n   end\n\n   return", "   end\n\n   return", "C3b"),
    ("cargo-read-after-the-como-log", "sdsys/gpl.bp/cproc", "         gosub read.phantom.cargo\n", "", "C4a"),
    ("refusal-after-the-options", "sdsys/gpl.bp/cproc", "         if ph.refused then\n            message = sysmsg(12952, @userno)", "         if ph.opts # '' then void kernel(K$SET.OPTIONS, ph.opts)\n         if ph.refused then\n            message = sysmsg(12952, @userno)", "C4b"),
    ("refusal-does-not-end-the-phantom", "sdsys/gpl.bp/cproc", "            goto terminate.phantom\n         end\n\n         * The option flags", "         end\n\n         * The option flags", "C5"),
    ("refusal-not-audited", "sdsys/gpl.bp/cproc", "            void kernel(K$AUDIT, 'phantom refused phantom='", "            void kernel(K$AUDIT, 'phantom held phantom='", "C5"),
    ("options-from-the-raw-record", "sdsys/gpl.bp/cproc", "if ph.opts # '' then void kernel(K$SET.OPTIONS, ph.opts)", "if ph.opts # '' then void kernel(K$SET.OPTIONS, ph.rec<2>)", "C6"),
    ("cargo-read-without-the-lock", "sdsys/gpl.bp/cproc", "         ph.log.file = ''\n         filelock ipc.f\n         gosub read.phantom.cargo\n         fileunlock ipc.f", "         ph.log.file = ''\n         gosub read.phantom.cargo", "C7"),
    # !ipc_seal
    ("short-secret-accepted", "sdsys/gpl.bp/ipc_seal", "   if len(nonce) < 16 then", "   if len(nonce) < 0 then", "S1"),
    ("values-in-another-order", "sdsys/gpl.bp/ipc_seal", "oconv(opt, 'MX0C') : ':' : oconv(cmd, 'MX0C')", "oconv(cmd, 'MX0C') : ':' : oconv(opt, 'MX0C')", "S2"),
    ("data-not-in-hexadecimal", "sdsys/gpl.bp/ipc_seal", "oconv(dq, 'MX0C')", "dq", "S2"),
    ("hash-without-the-key", "sdsys/gpl.bp/ipc_seal", "SD_HMACSHA256", "SD_SHA256", "S3a"),
    ("secret-not-the-key", "sdsys/gpl.bp/ipc_seal", "mac = SDEXT(nonce : @FM : signed,", "mac = SDEXT(signed : @FM : signed,", "S3a"),
    ("seals-compared-with-an-equals-sign", "sdsys/gpl.bp/ipc_seal", "if SDEXT(mac : @FM : seal, @TRUE, SD_CTEQUAL) = '1' then return 1", "if mac = seal then return 1", "S3b"),
    ("empty-seal-checked", "sdsys/gpl.bp/ipc_seal", "   if mac = '' or seal = '' then return 0\n", "", "S3b"),
    # messages
    ("refusal-message-without-the-number", "sdsys/messages/12952", "Phantom %1 :", "Phantom :", "M1"),
    ("two-programs-with-the-name", "sdsys/gpl.bp/is_grp_member", "$catalog !is_grp_member", "$catalog !ipc_seal", "M2"),
]


def selftest():
    import shutil
    t = tempfile.mkdtemp()
    caught = missed = 0
    ids = {}

    def mutant(name, rel, old, new, want):
        nonlocal caught, missed
        with open(os.path.join(ROOT, rel), encoding="latin-1") as f:
            real = f.read()
        if real.count(old) != 1:
            print("  [MISSED] %s: the text to change is in %s %d times, not once" % (name, rel, real.count(old)))
            missed += 1
            return
        f = os.path.join(t, name + "-" + os.path.basename(rel))
        with open(f, "w", encoding="latin-1") as g:
            g.write(real.replace(old, new, 1))
        env = dict(os.environ)
        env["IPC_" + re.sub(r"\W", "_", rel).upper()] = f
        r = subprocess.run([sys.executable, os.path.abspath(__file__)], env=env, capture_output=True, text=True)
        failed_ids = re.findall(r"^  \[FAIL\] (\S+) ", r.stdout, re.M)
        if want in failed_ids:
            print("  [caught] %s (row %s failed%s)" % (name, want, "" if failed_ids == [want] else "; also " + ", ".join(i for i in failed_ids if i != want)))
            caught += 1
            ids[want] = ids.get(want, 0) + 1
        else:
            print("  [MISSED] %s: row %s did not fail (failed: %s, exit %d)" % (name, want, failed_ids, r.returncode))
            missed += 1

    print("selftest: the real files first (must pass), then mutants (each must fail the row it names)")
    r = subprocess.run([sys.executable, os.path.abspath(__file__)], capture_output=True, text=True)
    if r.returncode != 0:
        print("  [FAIL] the real files do not pass:\n" + r.stdout[-900:])
        return 1
    print("  [ok] the real files pass")
    for m in MUTANTS:
        mutant(*m)
    shutil.rmtree(t, ignore_errors=True)
    print("selftest: %d of %d mutants caught, %d missed; rows named: %s" % (caught, caught + missed, missed, ", ".join(sorted(ids))))
    return 0 if missed == 0 and caught > 0 else 1


if __name__ == "__main__":
    sys.exit(selftest() if "--selftest" in sys.argv else run())
