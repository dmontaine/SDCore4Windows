#!/usr/bin/env python3
"""test-lockids-units.py - another session's lock ids reach a program and a terminal escaped (S.88 phase 2, S1 kernel half; 28 Oct 26).

  python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/test-lockids-units.py
  python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/test-lockids-units.py --selftest

No sudo, no install, no sd.  Exit 0 all checks passed, 1 a check failed, 2 it could not run.

THE DEFECT (Opus_TUI_Plan.txt S1, evidence ADM-01): GETLOCKS() put the record id, the file path and the user name of EVERY
session's lock into its answer with %.*s / %s, and LIST.READU and tool.sessions print that answer on the administrator's
terminal.  A hashed file's record id is checked only for being empty or too long, so an ordinary user's READU on an id that
holds ESC ] 0 ; ... BEL or ESC [ 2 J wrote that sequence into the administrator's terminal.  The deadlock message 1451 printed
another session's id the same way, and SYSTEM(1083) handed the ids and paths of the other sessions in a deadlock to a program.

THE CHANGE (gplsrc/op_lock.c): lock_unsafe_byte() names the bytes that are shown as '?' - 0-31, 127, the C1 controls 128-159
and the marks 248-255 (masters.c's mst_buf_text() took 0-31 and 253-255 until the L2 review of 28 Oct; masters.c was retired 2 Nov 26, S.96 M6, and L12 with it); lock_safe_text() copies into a buffer and
lock_ts_safe() appends to the target string; getlocks_line() builds every GETLOCKS() line, with the numbers through ts_printf()
and the text through lock_ts_safe().  The lock table, UNLOCK, RELEASE and FILEINFO(f, 1039) (a program's OWN locks) are not
changed.

THE REVIEW (28 Oct 26): the process-status dump (gplsrc/kernel.c dump_status(), the $IPC record S<n> that PSTAT prints, and
PSTAT is in every account's VOC) wrote another session's last command (field 2), the path and record id it waits for (field 4)
and @PSTAT (field 6, only the marks made spaces) RAW.  So the rule became ONE shared rule: op_lock.c's functions are now
show_unsafe_byte(), show_safe_text() and show_ts_safe() (were lock_*, Private), declared in sd.h, and kernel.c's ev_safe() uses
show_unsafe_byte() for every text of the dump: the command, the program names, the path, the id and the account; @PSTAT keeps
its marks as spaces (sheet 492, sandbox-q4.py J1) and shows the rule's other bytes as '?'.  ev_printf() formats numbers only
(vsnprintf), and ev_copy() no longer adds a full chunk's bytes to string_len a second time (K-rows).

***WHAT THIS IS AND IS NOT.***  It reads op_lock.c, sd.h, kernel.c, op_dio2.c and tool_sessions as TEXT; L1 evaluates
show_unsafe_byte()'s expression for all 256 bytes.  It cannot say what a terminal receives: that is sandbox-lockids.py
(GETLOCKS(), LIST.READU, FILEINFO 1039 with a live holder, and PSTAT of a second session that waits for the planted lock) and
sandbox-termsafe.py S1-K (tool.sessions).  --selftest mutates the sources and requires every mutant to be caught.

OTHER WRITERS OF ANOTHER SESSION'S DATA, looked at 28 Oct 26 and NOT changed here (other files, other lanes): the HSM dump
(object.c hsm_dump(), record H<n>) and the profiler table (profiler.c prof_dump(), record F<n>, whose qualifiers already take
0-31 and 248-255 but not 127 and 128-159, and whose program names are raw); and $IPC itself is sdsys:sdusers 775, so any SD
user can write an S<n> record directly - pstat would have to escape what it prints for the escaping to be complete.
SINCE 28 Oct 26 (later the same day) all of that is done and held by test-ipcsafe-units.py: hsm_dump() and prof_dump() write by
the same rule, and pstat, profiler and hsm print every text of the record through kernel(K$SHOW.SAFE, ...) (op_kernel.c).
"""

import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SD64 = os.path.abspath(os.path.join(HERE, os.pardir))
OPLOCK = os.path.join(SD64, "gplsrc", "op_lock.c")
OPDIO2 = os.path.join(SD64, "gplsrc", "op_dio2.c")
SDH = os.path.join(SD64, "gplsrc", "sd.h")
KERNEL = os.path.join(SD64, "gplsrc", "kernel.c")
TOOLSESS = os.path.join(SD64, "sdsys", "gpl.bp", "tool_sessions")

EXPECTED_UNSAFE = set(range(0, 32)) | {127} | set(range(128, 160)) | set(range(248, 256))


def strip_c_comments(text):
    return re.sub(r"/\*.*?\*/", "", text, flags=re.S)


def squash(s):
    return re.sub(r"\s+", " ", s)


def func_body(code, header_re):
    m = re.search(header_re + r"[^{]*\{\n(.*?)^\}\n", code, re.S | re.M)
    return m.group(1) if m else None


def unsafe_set(code):
    """Evaluate show_unsafe_byte()'s return expression in Python for every byte: None when it is not a plain expression of c."""
    m = re.search(r"^bool show_unsafe_byte\(u_char c\) \{\s*return (.*?);\s*\}", code, re.S | re.M)
    if not m:
        return None
    expr = squash(m.group(1))
    if re.search(r"[^\sc0-9()<>=!&|x]", expr.replace("0x", "")):
        return None
    py = expr.replace("&&", " and ").replace("||", " or ")
    try:
        return {c for c in range(256) if eval(py, {"__builtins__": {}}, {"c": c})}
    except Exception:
        return None


def checks(files):
    code = strip_c_comments(files["op_lock"])
    out = []

    def ck(name, ok, detail=""):
        out.append((name, bool(ok), detail))

    s = unsafe_set(code)
    ck("L1 show_unsafe_byte() is true for exactly 0-31, 127, 128-159 and 248-255 (evaluated for all 256 bytes)",
       s == EXPECTED_UNSAFE, "missing %s extra %s" % (sorted(EXPECTED_UNSAFE - (s or set()))[:12], sorted((s or set()) - EXPECTED_UNSAFE)[:12]) if s is not None else "not a plain expression")
    b = func_body(code, r"^char\* show_safe_text\(char\* out, int out_size, const char\* s, int len\) ")
    fb = squash(b or "")
    ck("L2 show_safe_text() cuts the copy at out_size - 1, puts '?' for every unsafe byte and always ends with a nul",
       b is not None and "if (len > out_size - 1) len = out_size - 1;" in fb
       and "out[i] = show_unsafe_byte((u_char)(s[i])) ? '?' : s[i];" in fb and "out[len] = '\\0';" in fb)
    b = func_body(code, r"^void show_ts_safe\(const char\* s, int len\) ")
    fb = squash(b or "")
    ck("L3 show_ts_safe() appends byte by byte with '?' for every unsafe byte, and does nothing for NULL",
       b is not None and "if (s == NULL) return;" in fb and "ts_copy_byte(show_unsafe_byte((u_char)(s[i])) ? '?' : s[i]);" in fb
       and "ts_copy(" not in fb)
    b = func_body(code, r"^Private void getlocks_line\(")
    fb = squash(b or "")
    want = ['ts_printf("%d", file_id);', "ts_copy_byte(VALUE_MARK);", "show_ts_safe(path, -1);", 'ts_printf("\\xfd%d\\xfd%s\\xfd", user_no, type);',
            "show_ts_safe(id, id_len);", "ts_copy_byte(VALUE_MARK);", "show_ts_safe(user_name, -1);", 'ts_printf("\\xfd%d", (int)when);']
    ck("L4 getlocks_line() writes file_id VM path VM userno VM type VM id VM username VM time, the three texts through show_ts_safe() and nothing else",
       b is not None and squash(" ".join(want)) == fb.strip(), fb.strip()[:300])
    g = func_body(code, r"^void op_getlocks\(\) ")
    gb = squash(g or "")
    ck("L5 op_getlocks() builds its lines only with getlocks_line() (four calls) and never prints a path, an id or a user name itself",
       g is not None and gb.count("getlocks_line(") == 4 and gb.count("ts_printf(") == 1 and "%.*s" not in gb
       and "ts_copy(" not in gb and "\\xfd%s" not in gb, "%d calls, %d ts_printf" % (gb.count("getlocks_line("), gb.count("ts_printf(")))
    flat = squash(code)
    ck("L6 the deadlock message 1451 prints another session's id through show_safe_text()",
       "tio_printf(sysmsg(1451), d_lptr->file_id, (int)(d_lptr->id_len), show_safe_text(d_safe_id, sizeof(d_safe_id), d_lptr->id, d_lptr->id_len), d_lptr->owner);" in flat)
    d = func_body(code, r"^Private void deadlock_info_add\(")
    db = squash(d or "")
    ck("L7 SYSTEM(1083)'s list takes the path and the id through show_safe_text() and copies no raw byte",
       d is not None and "show_safe_text(deadlock_info + deadlock_info_len, (int)strlen(path) + 1, path, -1);" in db
       and "show_safe_text(deadlock_info + deadlock_info_len, id_len + 1, id, id_len);" in db and "memcpy(" not in db and "%s" not in db)
    ck("L10 there is ONE rule: op_lock.c defines show_unsafe_byte(), show_safe_text() and show_ts_safe() once each, not Private, and no other "
       "copy of the rule (no lock_unsafe_byte / lock_safe_text / lock_ts_safe left)",
       len(re.findall(r"^bool show_unsafe_byte\(", code, re.M)) == 1 and len(re.findall(r"^char\* show_safe_text\(", code, re.M)) == 1
       and len(re.findall(r"^void show_ts_safe\(", code, re.M)) == 1
       and not re.search(r"\block_(unsafe_byte|safe_text|ts_safe)\s*\(", code))
    sdh = squash(strip_c_comments(files["sd_h"]))
    ck("L11 sd.h declares the three for every file: bool show_unsafe_byte(u_char c); char * show_safe_text(...); void show_ts_safe(...);",
       "bool show_unsafe_byte(u_char c);" in sdh and "char * show_safe_text(char * out, int out_size, const char * s, int len);" in sdh
       and "void show_ts_safe(const char * s, int len);" in sdh)
    # L12 (masters.c's mst_buf_text) went with masters.c on 2 Nov 26 (S.96 M6: the master-file copies are retired).

    # kernel.c: the process-status dump that PSTAT prints
    kcode = strip_c_comments(files["kernel"])
    kd = func_body(kcode, r"^Private void dump_status\(\) ")
    kb = squash(kd or "")
    ck("K1 dump_status() is there", kd is not None)
    ck("K2 field 2, another session's last command, goes chunk by chunk through ev_safe(); no %s or %.*s is formatted anywhere in dump_status()",
       "ev_safe(str->data, (int)(str->bytes));" in kb and "%s" not in kb and "%.*s" not in kb and "ev_copy(str->data" not in kb)
    ck("K3 field 3's program names go through ev_safe() before the numbers",
       'ev_safe(ProgramName(prg->saved_c_base), -1); ev_printf("%c%d%c%d", SUBVALUE_MARK,' in kb)
    ck("K4 field 4: the record lock's path and id, and the file lock's path, go through ev_safe()",
       'ev_printf("%d%c", lptr->owner, VALUE_MARK); ev_safe((const char*)(FPtr(lptr->file_id)->pathname), -1); ev_printf("%c", VALUE_MARK); ev_safe(lptr->id, lptr->id_len);' in kb
       and 'ev_printf("%d%c", abs(fptr->file_lock), VALUE_MARK); ev_safe((const char*)(fptr->pathname), -1); ev_printf("%c", VALUE_MARK);' in kb)
    ck("K5 field 5, the account, goes through ev_safe()", 'ev_printf("%c", FIELD_MARK); ev_safe(account(), -1);' in kb)
    ck("K6 field 6, @PSTAT: a mark (248 and up) is a space as before, any other byte show_unsafe_byte() names is '?', one byte at a time",
       "if ((u_char)pc >= 248) pc = ' '; else if (show_unsafe_byte((u_char)pc)) pc = '?'; ev_copy(&pc, 1);" in kb
       and 'ev_printf("%c", ((u_char)pc >= 248)' not in kb)
    es = func_body(kcode, r"^Private void ev_safe\(const char\* s, int len\) ")
    esb = squash(es or "")
    ck("K7 ev_safe() puts '?' for every byte show_unsafe_byte() names and adds nothing for NULL",
       es is not None and "if (s == NULL) return;" in esb and "buf[n++] = show_unsafe_byte((u_char)(s[i])) ? '?' : s[i];" in esb)
    ec = func_body(kcode, r"^Private void ev_copy\(const char\* p, int len\) ")
    ecb = squash(ec or "")
    ck("K8 ev_copy() counts each byte once in string_len (as it is moved) and never adds a full chunk's bytes again when it starts the next",
       ec is not None and ecb.count("string_len +=") == 1 and "ev_head->string_len += bytes_to_move;" in ecb and "string_len += ev_tail->bytes" not in ecb)
    ep = func_body(kcode, r"^Private void ev_printf\(char\* template_string, \.\.\.\) ")
    epb = squash(ep or "")
    ck("K9 ev_printf() formats with vsnprintf() into its own buffer, cut at the buffer, and appends through ev_copy()",
       ep is not None and "len = vsnprintf(s, sizeof(s), template_string, arg_ptr);" in epb and "vsprintf(" not in epb
       and "if (len > (int)sizeof(s) - 1) len = (int)sizeof(s) - 1;" in epb and "ev_copy(s, len);" in epb)
    dio = squash(strip_c_comments(files["op_dio2"]))
    ck("L8 FILEINFO(f, 1039) still gives the raw ids of the CALLER'S OWN locks only (rlptr->owner == process.user_no)",
       "if ((rlptr->hash != 0) && (rlptr->owner == process.user_no) && (rlptr->file_id == fvar->file_id)) {" in dio)
    ts = files["tool_sessions"]
    m = re.search(r"^plain\.word:\n(.*?)^\s*return", ts, re.S | re.M)
    allowed = re.search(r"index\('([^']*)', word\[pi, 1\], 1\)", m.group(1)) if m else None
    ck("L9 tool.sessions' plain.word refuses '?', so an id shown escaped can never be sent to UNLOCK as if it were the real id",
       allowed is not None and "?" not in allowed.group(1), allowed.group(1) if allowed else "plain.word not found")
    return out


def mutants(files):
    src = files["op_lock"]
    M = []

    def lk(name, old, new):
        M.append((name, dict(files, op_lock=src.replace(old, new, 1))))

    lk("the C1 controls are let through", " || ((c >= 128) && (c <= 159))", "")
    lk("DEL is let through", " || (c == 127)", "")
    lk("only mst_buf_text()'s marks (0xFD and up)", "(c >= 248);", "(c >= 253);")
    lk("control bytes are let through", "return (c < 32) || ", "return ")
    lk("show_safe_text() does not cut at its buffer", "  if (len > out_size - 1)\n    len = out_size - 1;\n", "")
    lk("the path goes out raw", "  show_ts_safe(path, -1);\n", "  ts_copy((char*)path, (int)strlen(path));\n")
    lk("the id goes out raw", "  show_ts_safe(id, id_len);\n", "  if (id != NULL)\n    ts_copy((char*)id, id_len);\n")
    lk("the user name goes out raw", "  show_ts_safe(user_name, -1);\n", "  if (user_name != NULL)\n    ts_copy((char*)user_name, (int)strlen(user_name));\n")
    lk("the rule goes back to being op_lock.c's own (Private)", "bool show_unsafe_byte(u_char c) {", "Private bool show_unsafe_byte(u_char c) {")
    M.append(("sd.h no longer declares the rule", dict(files, sd_h=files["sd_h"].replace("bool show_unsafe_byte(u_char c);\n", "", 1))))
    kn = files["kernel"]

    def kx(name, old, new):
        M.append((name, dict(files, kernel=kn.replace(old, new, 1))))

    kx("the command goes out raw (the review's finding)", "    ev_safe(str->data, (int)(str->bytes));\n",
       "    ev_printf(\"%.*s\", (int)(str->bytes), str->data);\n")
    kx("the command copied raw without formatting", "    ev_safe(str->data, (int)(str->bytes));\n", "    ev_copy(str->data, (int)(str->bytes));\n")
    kx("the waited-for record id goes out raw", "      ev_safe(lptr->id, lptr->id_len);\n", "      ev_copy(lptr->id, lptr->id_len);\n")
    kx("the waited-for path goes out raw", "      ev_safe((const char*)(FPtr(lptr->file_id)->pathname), -1);\n",
       "      ev_printf(\"%s\", FPtr(lptr->file_id)->pathname);\n")
    kx("a file lock's path goes out raw", "      ev_safe((const char*)(fptr->pathname), -1);\n", "      ev_copy((const char*)(fptr->pathname), (int)strlen((const char*)(fptr->pathname)));\n")
    kx("the account goes out raw", "  ev_printf(\"%c\", FIELD_MARK);\n  ev_safe(account(), -1);\n", "  ev_printf(\"%c%s\", FIELD_MARK, account());\n")
    kx("a program name goes out raw", "      ev_safe(ProgramName(prg->saved_c_base), -1);", "      ev_copy(ProgramName(prg->saved_c_base), (int)strlen(ProgramName(prg->saved_c_base)));")
    kx("@PSTAT: only the marks are touched (the review's finding)", "          else if (show_unsafe_byte((u_char)pc))\n            pc = '?';\n", "")
    kx("@PSTAT: the marks become '?' instead of spaces (sheet 492 changed)", "          if ((u_char)pc >= 248)\n            pc = ' ';\n          else if",
       "          if")
    kx("ev_safe() lets the bytes through", "    buf[n++] = show_unsafe_byte((u_char)(s[i])) ? '?' : s[i];", "    buf[n++] = s[i];")
    kx("ev_copy() counts a full chunk twice again", "    if (bytes_remaining == 0) {\n      ev_tail->next",
       "    if (bytes_remaining == 0) {\n      ev_head->string_len += ev_tail->bytes;\n      ev_tail->next")
    kx("ev_printf() back to an unbounded vsprintf()", "  len = vsnprintf(s, sizeof(s), template_string, arg_ptr);", "  len = vsprintf(s, template_string, arg_ptr);")
    lk("a record lock line printed the old way",
       "        getlocks_line((int)(rlptr->file_id), (char*)(fptr->pathname), (int)lock_owner,\n",
       "        ts_printf(\"%d\\xfd%s\\xfd%.*s\", (int)(rlptr->file_id), fptr->pathname, rlptr->id_len, rlptr->id);\n        getlocks_line((int)(rlptr->file_id), (char*)(fptr->pathname), (int)lock_owner,\n")
    lk("message 1451 prints the raw id", "show_safe_text(d_safe_id, sizeof(d_safe_id), d_lptr->id, d_lptr->id_len)", "d_lptr->id")
    lk("SYSTEM(1083) copies the raw id", "    (void)show_safe_text(deadlock_info + deadlock_info_len, id_len + 1, id, id_len);\n",
       "    memcpy(deadlock_info + deadlock_info_len, id, id_len);\n")
    M.append(("FILEINFO 1039 gives every session's locks", dict(files, op_dio2=files["op_dio2"].replace(
        "(rlptr->hash != 0) && (rlptr->owner == process.user_no) && (rlptr->file_id == fvar->file_id)", "(rlptr->hash != 0) && (rlptr->file_id == fvar->file_id)", 1))))
    M.append(("tool.sessions lets '?' into an UNLOCK sentence", dict(files, tool_sessions=files["tool_sessions"].replace(
        "index('abcdefghijklmnopqrstuvwxyz0123456789.-_', word[pi, 1], 1)", "index('abcdefghijklmnopqrstuvwxyz0123456789.-_?', word[pi, 1], 1)", 1))))
    return M


def load():
    files = {}
    for k, p in (("op_lock", OPLOCK), ("op_dio2", OPDIO2), ("tool_sessions", TOOLSESS), ("sd_h", SDH), ("kernel", KERNEL)):
        if not os.path.isfile(p):
            return None, p
        with open(p, encoding="latin-1") as f:
            files[k] = f.read()
    return files, None


def main():
    files, missing = load()
    if files is None:
        print("test-lockids-units: CANNOT RUN - no file %s" % missing)
        return 2
    if "--selftest" in sys.argv:
        base = checks(files)
        if not all(ok for _, ok, _ in base):
            print("selftest: CANNOT RUN - the unmutated sources already fail:")
            for n, ok, d in base:
                if not ok:
                    print("  FAIL %s (%s)" % (n, d))
            return 2
        bad = 0
        ms = mutants(files)
        for name, mf in ms:
            if mf == files:
                print("  [NOT APPLIED] %s" % name)
                bad += 1
                continue
            caught = [n.split(" ", 1)[0] for n, ok, _ in checks(mf) if not ok]
            if caught:
                print("  [caught] %s  (by %s)" % (name, ", ".join(caught)))
            else:
                print("  [MISSED] %s" % name)
                bad += 1
        print("test-lockids-units --selftest: %d mutant(s), %d not caught" % (len(ms), bad))
        return 1 if bad else 0
    print("op_lock.c     : %s\nop_dio2.c     : %s\ntool_sessions : %s\nsd.h          : %s\nkernel.c      : %s" % (OPLOCK, OPDIO2, TOOLSESS, SDH, KERNEL))
    res = checks(files)
    fails = 0
    for name, ok, detail in res:
        print("  [%s] %s%s" % ("PASS" if ok else "FAIL", name, "" if ok or not detail else "  (" + str(detail) + ")"))
        fails += 0 if ok else 1
    if len(res) < 20:
        print("test-lockids-units: only %d checks ran - refusing to pass" % len(res))
        return 1
    print("test-lockids-units: %d checks, %d failed" % (len(res), fails))
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
