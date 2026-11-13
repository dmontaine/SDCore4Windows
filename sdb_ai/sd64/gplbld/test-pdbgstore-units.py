#!/usr/bin/env python3
"""test-pdbgstore-units.py - W.11 F10b: the phantom debugger's conversation is kept in the user's private directory, not in $ipc; read off the source as text.

  python C:\\Users\\Don\\Projects\\SDCore4Windows\\sdb_ai\\sd64\\gplbld\\test-pdbgstore-units.py
  python C:\\Users\\Don\\Projects\\SDCore4Windows\\sdb_ai\\sd64\\gplbld\\test-pdbgstore-units.py --selftest

No elevation, no install, no sd.  Exit 0 every check passed, 1 a check failed, 2 it could not run.

START-HISTORY:
9 Nov 26 Windows port - from Linux debd0698 (31 Oct 26).  P3/P4 read the Windows !pdbg_store (<AppData\\Local>\\sd\\pdebug; SD_USER_HOME makes a missing
              directory below the home itself, private, so make.dir is gone), P8 reads message 12953 (Linux 11948 + 1005), and W1-W6 read the C half that
              Linux has in user_home_dir(): win32_user_home() in win32tls.c and the SD_USER_HOME case in op_sdext.c.
31 Oct 26 dm  New with F10b (Opus's decision of 30 Oct: seal the debugger's conversation by moving it out of $ipc into <home>/.local/state/sd/pdebug).
END-HISTORY

WHAT IT HOLDS.  PDEBUG (the user's session), the DEBUG subroutine it calls and PDBG (in the phantom being debugged) leave each other messages - D.n, DR.n and the
START record DR.account!logname.  They used to be records of $ipc, a file every SD user's process can write, so a user with an operating-system shell could answer a
debugger that was not theirs.  They are now records of a directory file, <AppData\\Local>\\sd\\pdebug, opened by !pdbg_store: the home is the profile's AppData\\Local
of the user the process's token names (SDEXT SD_USER_HOME: GetUserProfileDirectory, never %LOCALAPPDATA%, never a service account), nothing on the way may be a link
or let anybody else add, delete, rename or re-own an entry from the profile down, a missing directory below the home is made with a protected ACL holding only the
user, SYSTEM and Administrators, and the store itself must pass SD_FILE_PRIVATE.  A PDEBUG and a phantom reach each other only as the SAME Windows user.  The store
outlives an SD restart, which $ipc did not: PDEBUG clears the records of its own user number before it starts, and PDBG removes and does not answer a START record
whose PDEBUG has gone (kernel(K$USERS, n) is empty).

***IT READS THE SOURCE AS TEXT.***  That a conversation still works end to end, that the store's ACL is what win32_user_home() writes, and that another Windows user
cannot reach it need an install (and the last a second user).  --selftest requires each mutation to match its text exactly once and to be caught.
"""

import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SDSYS = os.path.join(HERE, os.pardir, "sdsys")
GPL = os.path.join(SDSYS, "gpl.bp")
SRC = os.path.join(HERE, os.pardir, "gplsrc")
FILES = {n: os.path.join(GPL, n) for n in ("debug", "debug.h", "pdbg", "pdebug", "pdbg_store")}
CFILES = {"win32tls.c": os.path.join(SRC, "win32tls.c"), "op_sdext.c": os.path.join(SRC, "op_sdext.c"), "keys.h": os.path.join(SRC, "keys.h"),
          "syscom/keys.h": os.path.join(SDSYS, "syscom", "keys.h")}
MSG = 12953


def strip(src):
    """the code without comment lines and trailing ;* comments"""
    out = []
    for ln in src.split("\n"):
        if ln.lstrip().startswith("*"):
            continue
        out.append(re.sub(r"\s*;\*.*$", "", ln))
    return "\n".join(out)


def cstrip(src):
    """C without /* */ and // comments (string literals are left alone: none of the checked ones holds a comment marker)"""
    src = re.sub(r"/\*.*?\*/", "", src, flags=re.S)
    return re.sub(r"//[^\n]*", "", src)


def ordered(text, *parts):
    pos = -1
    for p in parts:
        i = text.find(p, pos + 1)
        if i < 0:
            return False
        pos = i
    return True


def between(text, start, end):
    a = text.find(start)
    if a < 0:
        return ""
    b = text.find(end, a + len(start))
    return text[a:] if b < 0 else text[a:b]


def checks(src, msgs, others, csrc):
    rows = []

    def ck(name, ok, detail=""):
        rows.append((name, bool(ok), detail))

    code = {k: strip(v) for k, v in src.items()}
    dbg, pdbg, pdebug, store, hdr = code["debug"], code["pdbg"], code["pdebug"], code["pdbg_store"], code["debug.h"]
    tls = cstrip(csrc["win32tls.c"])
    sdx = cstrip(csrc["op_sdext.c"])
    ck("P0 NULL CASE: the reader sees the five sources (debug over 30 KB - Solo's, without the full-screen debugger, is about 50 - the others not empty) and the C files",
       len(dbg) > 30000 and len(pdbg) > 1500 and len(pdebug) > 1500 and len(store) > 600 and len(hdr) > 1000 and len(tls) > 5000 and len(sdx) > 5000,
       repr([len(code[k]) for k in code] + [len(tls), len(sdx)]))

    named = [k for k in ("debug", "pdbg", "pdebug") if re.search(r"ipc\.f|\$ipc|\bipc_seal\b", code[k], re.I)]
    ck("P1a debug, pdbg and pdebug name neither the file $ipc nor ipc.f nor ipc_seal in code", not named, repr(named))
    uses = {k: len(re.findall(r"\bdbg\.store\b", code[k])) for k in ("debug", "pdbg", "pdebug")}
    # 13 Nov 26 (RELEASE_1.1 253(b)): pdbg 15, three more - run.in's debugged child opens the run's store (openpath ... to dbg.store, mark.mapping
    # dbg.store, off) and waits for its START record (readv ... from dbg.store) - all of them dbg.store.
    ck("P1b every message statement of the three goes to dbg.store: 7 uses in debug (send.message 5, dbg.stop 2), 15 in pdbg, 15 in pdebug", uses == {"debug": 7, "pdbg": 15, "pdebug": 15}, repr(uses))
    stray = []
    seen = 0
    for k in ("pdbg", "pdebug"):
        for ln in code[k].split("\n"):
            m = re.search(r"^\s*(?:readu?\s+[\w.]+\s+from|write\s+.+?\s+to|delete|recordlocku|release)\s+([\w.]+)", ln)
            # 13 Nov 26 (RELEASE_1.1 253(b)): the one other file is the debugged program's OWN SOURCE, which PDBG reads for 'SOURCE' (src.f) so that a debugger in
            # another, elevated process opens no name the debugged process gave; no message goes through it.
            if m and m.group(1) not in ("dbg.store",) and not (k == "pdbg" and m.group(1) == "src.f" and ln.strip().startswith("read src.text from src.f,")):
                stray.append(k + ": " + ln.strip()[:60])
            seen += 1 if m else 0
    ck("P1c every record statement of pdbg and pdebug (readu, read, write, delete, recordlocku, release) names dbg.store and no other file (some 20 of them), "
       "but for PDBG's read of the program's own source for 'SOURCE'",
       not stray and seen >= 18, repr((seen, stray[:3])))

    ck("P2a !pdbg_store is $internal, `subroutine pdbg_store(pf, why)`, cataloged as !pdbg_store",
       store.lstrip().startswith("$internal") and re.search(r"^subroutine pdbg_store\(pf, why\)$", store, re.M) is not None and "$catalog !pdbg_store" in store, "")
    ck("P2b ...and no other program of gpl.bp takes the catalog name", sum(1 for t in others.values() if re.search(r"^\$catalog\s+!pdbg_store\b", t, re.M | re.I)) == 0
       and len(re.findall(r"^\$catalog", store, re.M)) == 1, "")
    ck(r"P3a the directory is sd\pdebug below the home", r"STORE = 'sd\pdebug'" in store and store.count("STORE = ") == 1, "")
    ck("P3b pf and why are assigned first; a service account and an empty user are refused; the home is SD_USER_HOME's and never an environment variable",
       ordered(store, "pf = ''", "why = 'user'", "kernel(K$USERNAME, 0)", "if ps.user = '' or ps.user = 'system' then return", "why = 'home'",
               "ps.home = SDEXT('', @FALSE, SD_USER_HOME)", "if ps.home = '' then return")
       and re.search(r"getenv|environment|LOCALAPPDATA|USERPROFILE|\$HOME", store, re.I) is None, "")
    ck("P3c the directory is checked BEFORE it is opened; the file is opened with mark mapping OFF (a message keeps its field marks); `why` is '' only after that",
       ordered(store, "why = 'directory'", r"ps.dir = ps.home : '\' : STORE", "gosub check.dir", "if not(dir.ok) then return", "why = 'open'", "openpath ps.dir to pf else",
               "mark.mapping pf, off", "why = ''")
       and store.count("why = ''") == 1, "")
    ck("P3d it touches only the store and makes nothing itself: no OPENSEQ, no execute, no OSPATH at all, no os.execute (SD_USER_HOME makes the directories, private)",
       re.search(r"\b(openseq|execute|os\.execute|osopen|oscopy|ospath|umask)\b", store, re.I) is None, "")
    ck("P4b check.dir asks SD_USER_HOME for the whole path and SD_FILE_PRIVATE for 'DIR' (owner-only), and the answer is that test alone",
       ordered(store, "check.dir:", "dir.ok = @false", "if SDEXT(STORE, @FALSE, SD_USER_HOME) # ps.dir then return",
               "dir.ok = (SDEXT(ps.dir : @FM : 'DIR', @TRUE, SD_FILE_PRIVATE) = '1')")
       and store.count("dir.ok = @true") == 0, "")

    ck("P5a PDEBUG makes the store BEFORE it turns BREAK off and before any record, and stops with %d and the reason when it cannot" % MSG,
       ordered(pdebug, "call !pdbg_store(dbg.store, store.why)", "if store.why # '' then stop sysmsg(%d, store.why)" % MSG, "break off", "recordlocku dbg.store, start.id"), "")
    ck("P5b PDEBUG removes the records of its own user number (in.id, out.id) before it writes START, and START is written last of those",
       ordered(pdebug, "in.id = 'D.':@userno", "out.id = 'DR.':@userno", "recordlocku dbg.store, in.id", "delete dbg.store, in.id", "recordlocku dbg.store, out.id",
               "delete dbg.store, out.id", "start.id = 'DR.':@who:'!':@logname", "write out.msg to dbg.store, start.id"), "")
    ck("P6a PDBG makes the store before it reads START, and a store it cannot make is `cannot debug` (NO_PDEBUG, or the old stop)",
       ordered(pdbg, "call !pdbg_store(dbg.store, store.why)", "if store.why # '' then goto cannot.debug", "readu in.msg from dbg.store, id else goto cannot.debug"), "")
    ck("P6b PDBG takes START only when it says START, and a PDEBUG that is gone (kernel(K$USERS, n) empty) has its record deleted and is not answered; the answer "
       "(D.n deleted, the conversation) comes after that",
       ordered(pdbg, "if in.msg<1> # 'START' then goto cannot.debug", "debugger.uid = in.msg<2>", "if kernel(K$USERS, debugger.uid) = '' then",
               "delete dbg.store, id", "goto cannot.debug", "end", "delete dbg.store, id", "id = 'D.':debugger.uid", "debug.initialised = @true"), "")
    ck("P6c cannot.debug gives the locks back only when the store was made (a store that could not be made is not a file to release)",
       ordered(pdbg, "cannot.debug:", "if store.why = '' then release dbg.store", "caught('SYS.PROGRAM.NO_PDEBUG', 3)"), "")
    ck("P7 debug.h holds dbg.store once, in the common block /$debug/ shared by PDEBUG and DEBUG", len(re.findall(r"\bdbg\.store\b", between(hdr, "common /$debug/", "$define DE$WATCH"))) == 1, "")
    ck("P8 message %d exists, takes the reason as %%1 and says the phantom debugger cannot start; nothing but PDEBUG asks for it" % MSG,
       "%1" in msgs.get(MSG, "") and "debugger" in msgs.get(MSG, "") and len(re.findall(r"\b%d\b" % MSG, "\n".join(code[k] for k in code))) == 1
       and not any(re.search(r"\b%d\b" % MSG, strip(t)) for n, t in others.items()), repr(msgs.get(MSG)))

    # --- the C half: SD_USER_HOME on Windows ---------------------------------------------------------------------------------------------
    ck("W1 SD_USER_HOME is 112 in gplsrc/keys.h and in sdsys/syscom/keys.h (Linux's number), and op_sdext.c answers it from win32_user_home() alone, '' on failure",
       re.search(r"^#define SD_USER_HOME\s+112\b", csrc["keys.h"], re.M) is not None
       and re.search(r"^\s*\$define SD_USER_HOME\s+112\b", csrc["syscom/keys.h"], re.M) is not None
       and ordered(between(sdx, "case SD_USER_HOME:", "break;"), "home_out[0] = '\\0';", "if (argCnt != 1)", "process.status = SD_EXT_ARG_CNT;",
                   "else if (!win32_user_home(SDMEArgArray[0], home_out, sizeof(home_out), why, sizeof(why)))", "home_out[0] = '\\0';",
                   "k_put_c_string(home_out, e_stack);"), "")
    home = between(tls, "size_t whylen) {\n  HANDLE tok = NULL;", "\n}\n")   # the definition, not the declaration at the top
    ck("W2 the home is GetUserProfileDirectoryA() on the process token followed by AppData\\Local, never an environment variable; a service account has none",
       ordered(home, "OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &tok)", "TokenUser", "WinLocalSystemSid", "WinLocalServiceSid", "WinNetworkServiceSid",
               "return 0;", "GetUserProfileDirectoryA(tok, profile, &plen)")
       and re.search(r"getenv|GetEnvironmentVariable|LOCALAPPDATA|USERPROFILE|SHGetKnownFolderPath|SHGetFolderPath", tls) is None, "")
    ck("W3 every directory above the profile is held to HOME_BAD_ABOVE, and the profile, AppData and Local to HOME_BAD_BELOW, in that order, before REL is read",
       ordered(home, "home_dir_ok(work, HOME_BAD_ABOVE,", "home_dir_ok(work, HOME_BAD_ABOVE,", "home_dir_ok(work, HOME_BAD_BELOW,", "\"\\\\AppData\"",
               "home_dir_ok(work, HOME_BAD_BELOW,", "\"\\\\Local\"", "home_dir_ok(work, HOME_BAD_BELOW,", "for (p = rel;"), "")
    ok_dir = between(tls, "static int home_dir_ok(", "\n}\n")
    ck("W4 home_dir_ok refuses a link, a non-directory, a NULL DACL, a foreign owner and an entry of a kind it does not read, and skips only deny and inherit-only entries",
       ordered(ok_dir, "FILE_ATTRIBUTE_DIRECTORY", "FILE_ATTRIBUTE_REPARSE_POINT", "OWNER_SECURITY_INFORMATION | DACL_SECURITY_INFORMATION",
               "sid_is_ours(owner, user, towner) || sid_is_system_kind(owner)", "dacl == NULL", "ACCESS_DENIED_ACE_TYPE", "INHERIT_ONLY_ACE",
               "hdr->AceType != ACCESS_ALLOWED_ACE_TYPE", "(mask & bad) == 0", "ok = 0;")
       and re.search(r"#define HOME_BAD_BELOW\s+\(FILE_ADD_FILE \| FILE_ADD_SUBDIRECTORY \| FILE_DELETE_CHILD \| DELETE \| WRITE_DAC \| WRITE_OWNER \| GENERIC_ALL \| GENERIC_WRITE\)", tls)
       is not None
       and re.search(r"#define HOME_BAD_ABOVE\s+\(FILE_DELETE_CHILD \| DELETE \| WRITE_DAC \| WRITE_OWNER \| GENERIC_ALL\)", tls) is not None, "")
    ck("W5 a word of REL may not be empty, . or .., nor hold a stream or wildcard character; a missing one is made by make_private_dir and every one must then pass "
       "win32_private_to_user",
       ordered(home, "strchr(\":*?\\\"<>|\", *e) != NULL", "wl == 0 || (wl == 1 && p[0] == '.') || (wl == 2 && p[0] == '.' && p[1] == '.')",
               "GetFileAttributesA(work)", "ERROR_FILE_NOT_FOUND", "make_private_dir(work, user, why, whylen)", "win32_private_to_user(work, 1, why, whylen)"), "")
    mk = between(tls, "static int make_private_dir(", "\n}\n")
    ck("W6 make_private_dir's ACL is protected (no inheritance), owned by the user, and holds only the user, SYSTEM and Administrators",
       "\"O:%sD:P(A;OICI;FA;;;%s)(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)\", us, us" in mk and "CreateDirectoryA(dir, &sa)" in mk and mk.count("(A;") == 3, "")
    return rows


def load():
    src = {}
    for k, p in FILES.items():
        with open(p, encoding="latin-1") as f:
            src[k] = f.read()
    csrc = {}
    for k, p in CFILES.items():
        with open(p, encoding="latin-1") as f:
            csrc[k] = f.read()
    msgs = {}
    p = os.path.join(SDSYS, "messages", str(MSG))
    if os.path.isfile(p):
        with open(p, encoding="latin-1") as f:
            msgs[MSG] = f.read()
    others = {}
    for n in sorted(os.listdir(GPL)):
        p = os.path.join(GPL, n)
        if n not in FILES and os.path.isfile(p):
            with open(p, encoding="latin-1") as f:
                others[n] = f.read()
    return src, msgs, others, csrc


def report(rows):
    bad = 0
    for name, ok, detail in rows:
        bad += 0 if ok else 1
        print("  [%s] %s%s" % ("PASS" if ok else "FAIL", name, "" if ok else "   <- " + detail))
    return bad


# (file, name, old, new): each must match its file's text once and be caught
MUTANTS = [
    ("pdbg", "PDBG reads START from $ipc again", "readu in.msg from dbg.store, id else goto cannot.debug", "readu in.msg from ipc.f, id else goto cannot.debug"),
    ("pdebug", "PDEBUG writes START to $ipc again", "write out.msg to dbg.store, start.id", "write out.msg to ipc.f, start.id"),
    ("debug", "DEBUG sends its message through $ipc again", "   write out.msg to dbg.store, id\n   wake debugger.uid\n\n   id = 'D.':@userno", "   write out.msg to ipc.f, id\n   wake debugger.uid\n\n   id = 'D.':@userno"),
    ("pdbg", "PDBG answers through a second, unnamed file", "      write out.msg to dbg.store, id\n      wake debugger.uid", "      write out.msg to other.f, id\n      wake debugger.uid"),
    ("pdbg_store", "a service account may have a store", "   if ps.user = '' or ps.user = 'system' then return", "   if ps.user = '' then return"),
    ("pdbg_store", "the home is not the trusted one", "   ps.home = SDEXT('', @FALSE, SD_USER_HOME)", "   ps.home = 'C:\\Temp'"),
    ("pdbg_store", "the file keeps the mark mapping (a field mark becomes a line end)", "   mark.mapping pf, off\n", ""),
    ("pdbg_store", "the directory is opened without being checked", "   gosub check.dir\n   if not(dir.ok) then return\n", ""),
    ("pdbg_store", "the owner-only test is gone", "   dir.ok = (SDEXT(ps.dir : @FM : 'DIR', @TRUE, SD_FILE_PRIVATE) = '1')", "   dir.ok = @true"),
    ("pdbg_store", "the store makes its own directory (it would inherit the parent's entries)", "   gosub check.dir\n", "   void ospath(ps.dir, OS$MKDIR)\n   gosub check.dir\n"),
    ("pdbg_store", "the store is somewhere else", "STORE = 'sd\\pdebug'", "STORE = 'sd\\pdebug2'"),
    ("pdbg_store", "the store reads the environment", "   ps.user = downcase(trim(kernel(K$USERNAME, 0)))", "   ps.user = downcase(trim(kernel(K$USERNAME, 0)))\n   ps.env = getenv('LOCALAPPDATA')"),
    ("pdebug", "PDEBUG makes the store after it turned BREAK off", "   call !pdbg_store(dbg.store, store.why)\n   if store.why # '' then stop sysmsg(12953, store.why)\n\n   break off\n", "   break off\n\n   call !pdbg_store(dbg.store, store.why)\n   if store.why # '' then stop sysmsg(12953, store.why)\n"),
    ("pdebug", "PDEBUG goes on without a store", "   if store.why # '' then stop sysmsg(12953, store.why)\n", ""),
    ("pdebug", "PDEBUG leaves the records of its user number", "   recordlocku dbg.store, in.id\n   delete dbg.store, in.id\n   recordlocku dbg.store, out.id\n   delete dbg.store, out.id\n", ""),
    ("pdbg", "PDBG answers a START whose PDEBUG has gone", "      if kernel(K$USERS, debugger.uid) = '' then\n         delete dbg.store, id      ;* PDEBUG has gone and left its record: nobody is waiting\n         goto cannot.debug\n      end\n", ""),
    ("pdbg", "PDBG goes on when it has no store", "      if store.why # '' then goto cannot.debug\n", ""),
    ("pdbg", "cannot.debug releases a store that was never made", "   if store.why = '' then release dbg.store      ;* store.why is set by the call above, before any jump here", "   release dbg.store"),
    ("debug.h", "the common block has no store", "dbg.store                    ;* 9 Nov 26", "dbg.store2                   ;* 9 Nov 26"),
]
# (C file, name, old, new)
CMUTANTS = [
    ("keys.h", "the key is renumbered", "#define SD_USER_HOME    112", "#define SD_USER_HOME    113"),
    ("syscom/keys.h", "BASIC's key is renumbered", "$define SD_USER_HOME    112", "$define SD_USER_HOME    113"),
    ("op_sdext.c", "a failure answers what was half-built", "        home_out[0] = '\\0';\n      k_put_c_string(home_out, e_stack);", "        ;\n      k_put_c_string(home_out, e_stack);"),
    ("win32tls.c", "the home comes from the environment", "  if (!GetUserProfileDirectoryA(tok, profile, &plen)) {", "  if (!GetEnvironmentVariableA(\"USERPROFILE\", profile, plen)) {"),
    ("win32tls.c", "LocalSystem has a home", "  if (IsWellKnownSid(user, WinLocalSystemSid) || IsWellKnownSid(user, WinLocalServiceSid)", "  if (IsWellKnownSid(user, WinLocalServiceSid)"),
    ("win32tls.c", "the drive root is not checked", "  if (!home_dir_ok(work, HOME_BAD_ABOVE, user, towner, why, whylen))\n    return 0;\n  for (i = 3;", "  for (i = 3;"),
    ("win32tls.c", "Local is held to the weaker rule", "  strcat(work, \"\\\\Local\");\n  if (!home_dir_ok(work, HOME_BAD_BELOW,", "  strcat(work, \"\\\\Local\");\n  if (!home_dir_ok(work, HOME_BAD_ABOVE,"),
    ("win32tls.c", "a link on the way is followed", "  if (attr & FILE_ATTRIBUTE_REPARSE_POINT) {\n    snprintf(why, whylen, \"%s is a link\", dir);", "  if (0) {\n    snprintf(why, whylen, \"%s is a link\", dir);"),
    ("win32tls.c", "anybody may own a directory on the way", "  if (owner == NULL || !(sid_is_ours(owner, user, towner) || sid_is_system_kind(owner))) {", "  if (owner == NULL) {"),
    ("win32tls.c", "a delete right is allowed below the profile", "#define HOME_BAD_BELOW  (FILE_ADD_FILE | FILE_ADD_SUBDIRECTORY | FILE_DELETE_CHILD | DELETE |", "#define HOME_BAD_BELOW  (FILE_ADD_FILE | FILE_ADD_SUBDIRECTORY | FILE_DELETE_CHILD |"),
    ("win32tls.c", "a rename right is allowed above the profile", "#define HOME_BAD_ABOVE  (FILE_DELETE_CHILD | DELETE |", "#define HOME_BAD_ABOVE  (DELETE |"),
    ("win32tls.c", ".. is a word", "(wl == 2 && p[0] == '.' && p[1] == '.')", "(wl == 2 && p[0] == '.' && p[1] == '!')"),
    ("win32tls.c", "a stream name is a word", "strchr(\":*?\\\"<>|\", *e) != NULL", "strchr(\"*?\\\"<>|\", *e) != NULL"),
    ("win32tls.c", "a directory below the home is not held private", "    if (!win32_private_to_user(work, 1, why, whylen))\n      return 0;\n  }", "  }"),
    ("win32tls.c", "the store inherits its parent's entries", "\"O:%sD:P(A;OICI;FA;;;%s)", "\"O:%sD:(A;OICI;FA;;;%s)"),
    ("win32tls.c", "the store lets Everyone in", "(A;OICI;FA;;;BA)\", us, us", "(A;OICI;FA;;;BA)(A;OICI;FA;;;WD)\", us, us"),
]
MSG_MUTANTS = [("message 12953 is missing", None), ("message 12953 has no reason in it", "The debugger's private directory could not be set up\n")]


def selftest():
    src, msgs, others, csrc = load()
    if any(not ok for _, ok, _ in checks(src, msgs, others, csrc)):
        print("REFUSING - the unmutated source already fails", file=sys.stderr)
        return 2
    holes = 0
    print("--- self-test: each mutation must be CAUGHT and match its text once ---")
    for table, base in ((MUTANTS, "bp"), (CMUTANTS, "c")):
        for fk, name, old, new in table:
            pool = src if base == "bp" else csrc
            if pool[fk].count(old) != 1:
                print("  [FAIL] %s: the text matches %d times in %s, not once" % (name, pool[fk].count(old), fk))
                holes += 1
                continue
            mut = dict(pool)
            mut[fk] = pool[fk].replace(old, new)
            rows = checks(mut, msgs, others, csrc) if base == "bp" else checks(src, msgs, others, mut)
            caught = [n.split(" ")[0] for n, ok, _ in rows if not ok]
            print("  [%s] %s%s" % ("pass" if caught else "FAIL", name, ": caught by " + ", ".join(caught[:3]) if caught else ": NOT CAUGHT"))
            holes += 0 if caught else 1
    for name, text in MSG_MUTANTS:
        m2 = dict(msgs)
        if text is None:
            m2.pop(MSG, None)
        else:
            m2[MSG] = text
        caught = [n.split(" ")[0] for n, ok, _ in checks(src, m2, others, csrc) if not ok]
        print("  [%s] %s%s" % ("pass" if caught else "FAIL", name, ": caught by " + ", ".join(caught) if caught else ": NOT CAUGHT"))
        holes += 0 if caught else 1
    # another program takes the catalog name
    o2 = dict(others)
    o2["zz_clash"] = "$internal\nsubroutine zz_clash\n$catalog !pdbg_store\nend\n"
    caught = [n.split(" ")[0] for n, ok, _ in checks(src, msgs, o2, csrc) if not ok]
    print("  [%s] another program takes the catalog name%s" % ("pass" if caught else "FAIL", ": caught by " + ", ".join(caught) if caught else ": NOT CAUGHT"))
    holes += 0 if caught else 1
    total = len(MUTANTS) + len(CMUTANTS) + len(MSG_MUTANTS) + 1
    print("\n%d of %d mutants caught, %d missed" % (total - holes, total, holes))
    return 1 if holes else 0


def main():
    missing = [p for p in list(FILES.values()) + list(CFILES.values()) if not os.path.isfile(p)]
    if missing:
        print("test-pdbgstore-units: CANNOT RUN - not readable: %s" % missing, file=sys.stderr)
        return 2
    if "--selftest" in sys.argv[1:]:
        return selftest()
    src, msgs, others, csrc = load()
    rows = checks(src, msgs, others, csrc)
    bad = report(rows)
    print("\nNOT MEASURED HERE: that a conversation works end to end, that the store's ACL on disk is what win32_user_home() writes, that another Windows user cannot enter the directory (a second user).")
    print("test-pdbgstore-units: %d checks, %d failed" % (len(rows), bad))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
