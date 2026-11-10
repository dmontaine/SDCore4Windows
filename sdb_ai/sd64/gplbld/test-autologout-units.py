#!/usr/bin/env python3
"""test-autologout-units.py - AUTOLOGOUT measures idle time across keyin() calls (S.88 phase 2, S3; 28 Oct 26).

  python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/test-autologout-units.py
  python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/test-autologout-units.py --selftest

No sudo, no install, no sd.  Exit 0 all checks passed, 1 a check failed, 2 it could not run.

THE DEFECT (Opus_TUI_Plan.txt S3, evidence N4): keyin() in gplsrc/linuxio.c used the inactivity timer only when
`(autologout < timeout) || !timeout`, and then for the WHOLE period from the start of that call.  The screen library waits
a second at a time ($sl_key's keycode(1), the IDE's `screen wait ... timeout 1`, the home screen, every tool page), so
every one-second wait started the period again and AUTOLOGOUT never fired in any of them.  SED and $sl_guard worked round
it by waiting for the key alone when AUTOLOGOUT was set (and so noticed a resize only at the next key).

THE CHANGE: two file-scope variables, idle_waited (milliseconds waited with nothing typed) and idle_carry (the last keyin()
ended by ITS OWN timeout).  A call carries idle_waited on only when idle_carry is set; it is set in one place, the caller's
own timeout, and every other end of a call (a byte, an interrupt) leaves it clear, so the next wait starts from 0 as before.
The wait ends at whichever comes first, the caller's timeout or the rest of the period (autologout - idle_waited); the
logout itself is the old code (message 2503, Sleep(3000), K_TERMINATE).  $sl_guard lost its work-around; SED keeps its own
(SED is frozen), which is still correct under the new rule.

THE REVIEW (28 Oct 26): the first version tested `idle_left <= timeout` in every case, so a timed wait EQUAL to the AUTOLOGOUT
period, with nothing carried, logged out where it had always returned a plain timeout.  With nothing carried (idle_waited 0)
the test is the old strict `autologout < timeout` again (A5); `<=` applies only to a carried clock, where the inactivity has
then reached the whole period.

KNOWN AND INTENDED CONSEQUENCE (not a defect; A11 holds the history line that says so): a program that polls the keyboard
with very short timed KEYINs and works between them counts as waiting.  Each poll ends by its own timeout, so the polls add
up with nothing typed and AUTOLOGOUT eventually logs the session out; only a key (or an interrupt) starts the clock again.
The time spent working between the polls is not counted, only the time spent in them.

***WHAT THIS IS AND IS NOT.***  It reads linuxio.c, sl_guard, sed and message 2503 as TEXT.  It cannot say a session is
logged out: that is sandbox-autologout.py (and sandbox-termsafe.py --slow, row S3).  --selftest mutates the sources and
requires every mutant to be caught.
"""

import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SD64 = os.path.abspath(os.path.join(HERE, os.pardir))
LINUXIO = os.path.join(SD64, "gplsrc", "linuxio.c")
SLGUARD = os.path.join(SD64, "sdsys", "gpl.bp", "sl_guard")
MSG2503 = os.path.join(SD64, "sdsys", "messages", "2503")
OPKERNEL = os.path.join(SD64, "gplsrc", "op_kernel.c")
SDH = os.path.join(SD64, "gplsrc", "sd.h")


def strip_c_comments(text):
    return re.sub(r"/\*.*?\*/", "", text, flags=re.S)


def strip_basic_comments(text):
    out = []
    for ln in text.split("\n"):
        if ln.lstrip().startswith("*"):
            continue
        out.append(re.sub(r";\s*\*.*$", "", ln))
    return "\n".join(out)


def keyin_body(src):
    m = re.search(r"^int16_t keyin\(timeout\) int timeout;[^\n]*\n\{\n(.*?)^\}\n", src, re.S | re.M)
    return m.group(1) if m else None


def squash(s):
    return re.sub(r"\s+", " ", s)


def checks(files):
    src, guard, msg = files["linuxio"], files["sl_guard"], files["2503"]
    out = []

    def ck(name, ok, detail=""):
        out.append((name, bool(ok), detail))

    code_all = strip_c_comments(src)
    ck("A1 linuxio.c declares the clock at file scope: Private int64 idle_waited = 0 and Private bool idle_carry = FALSE",
       re.search(r"^Private int64 idle_waited = 0;", code_all, re.M) and re.search(r"^Private bool idle_carry = FALSE;", code_all, re.M))
    body = keyin_body(src)
    ck("A2 keyin() is there", body is not None)
    if body is None:
        return out
    code = strip_c_comments(body)
    flat = squash(code)

    ta = flat.find("if (type_ahead >= 0)")
    rs = flat.find("if (!idle_carry) idle_waited = 0;")
    cl = flat.find("idle_carry = FALSE;")
    ck("A3 on entry, before any input is looked at: if (!idle_carry) idle_waited = 0; then idle_carry = FALSE;",
       0 <= rs < cl < ta, "reset at %d, clear at %d, type_ahead at %d" % (rs, cl, ta))
    ck("A4 the old rule is gone: no '(autologout < timeout) || !timeout' and no 'timeout = autologout'",
       "(autologout < timeout)" not in flat and "timeout = autologout;" not in flat)
    m = re.search(r"if \(autologout\) \{ idle_left = \(int64\)autologout - idle_waited; if \(idle_left < 1\) idle_left = 1; "
                  r"if \(!timeout\) using_autologout = TRUE; else if \(idle_waited == 0\) using_autologout = \(idle_left < \(int64\)timeout\); "
                  r"else using_autologout = \(idle_left <= \(int64\)timeout\); \} if \(using_autologout\) timeout = \(int\)idle_left;", flat)
    ck("A5 the period left is autologout - idle_waited (at least 1 ms); it is the wait when the caller gave no timeout, or, with NOTHING "
       "carried, a strictly longer one (the old 'autologout < timeout': a wait equal to the period is a plain timeout), or, with a "
       "carried clock, one at least as long", m is not None)
    p_td = flat.find("td = t2 - t1;")
    p_add = flat.find("idle_waited += td;")
    p_exp = flat.find("if (timeout <= 0) {")
    ck("A6 every slice of the wait is added to idle_waited, after td is measured and before the expiry test",
       0 <= p_td < p_add < p_exp and flat.count("idle_waited += td;") == 1, "td %d, add %d, expiry %d" % (p_td, p_add, p_exp))
    m7 = re.search(r"if \(timeout <= 0\) \{ input_handler_enabled = TRUE; if \(using_autologout\) \{ log_printf\(\"%s\\n\", sysmsg\(2503\)\); "
                   r"Sleep\(3000\); k_exit_cause = K_TERMINATE; \} else \{ idle_carry = TRUE; \} process.status = ER_TIMEOUT; return -1; \}", flat)
    ck("A7 at expiry: AUTOLOGOUT logs out exactly as before (log_printf of 2503, Sleep(3000), K_TERMINATE); the caller's own timeout sets idle_carry", m7 is not None)
    ck("A8 idle_carry is set TRUE in that one place only (a byte, an interrupt, a lost connection or end of input leave it clear)",
       code_all.count("idle_carry = TRUE") == 1, "%d" % code_all.count("idle_carry = TRUE"))
    ck("A9 idle_waited is set only by the entry reset and the slice sum (nothing else moves the clock)",
       len(re.findall(r"\bidle_waited\s*(=(?!=)|\+=|-=)", code_all)) == 3, "%r" % re.findall(r"\bidle_waited\s*(?:=(?!=)|\+=|-=)[^;]*;", code_all))
    ck("A10 message 2503 is still the inactivity message", msg.strip() == "Inactivity timer expired - Process logged out", repr(msg.strip()))
    hist = squash(re.sub(r"\n \*", "\n", src.split("END-HISTORY", 1)[0]))
    ck("A11 the history block records the known and intended consequence: very short timed KEYIN polls with work between them count as waiting",
       "polls the keyboard with very short timed KEYINs and works between them counts as waiting" in hist
       and "KNOWN AND INTENDED" in hist)

    ck("A12 keyin_idle_ms() (28 Oct 26, the L2 review) gives the clock only while it is carried - 0 after a byte or an interrupt - clamped to 32 bits, and assigns nothing",
       re.search(r"int32_t keyin_idle_ms\(void\) \{ int64 ms = idle_carry \? idle_waited : 0; return \(ms > 0x7FFFFFFF\) \? 0x7FFFFFFF : \(int32_t\)ms; \}", squash(code_all)) is not None)
    kc = squash(strip_c_comments(files["op_kernel"]))
    ck("A13 kernel(K$AUTOLOGOUT, -2) is the clock and any other argument is the period as before: the setter (>= 0) comes first, then result = (value == -2) ? keyin_idle_ms() : autologout",
       "case K_AUTOLOGOUT: GetInt(descr); if (descr->data.value >= 0) autologout = descr->data.value; "
       "result.data.value = (descr->data.value == -2) ? keyin_idle_ms() : autologout; break;" in kc)
    ck("A14 sd.h declares int32_t keyin_idle_ms(void);", "int32_t keyin_idle_ms(void);" in squash(strip_c_comments(files["sd_h"])))

    g = strip_basic_comments(guard)
    ck("G1 $sl_guard has no AUTOLOGOUT work-around: no K$AUTOLOGOUT, no slice, no wait without a timeout",
       "K$AUTOLOGOUT" not in g and "slice" not in g and not re.search(r"keyin\(\s*\)", g))
    ck("G2 $sl_guard waits a second at a time (k = keyin(1)) and keeps a timeout apart from an ended input (kst = status(), ER$TIMEOUT)",
       re.search(r"^\s*k = keyin\(1\)", g, re.M) and re.search(r"^\s*kst = status\(\)", g, re.M) and "if kst # ER$TIMEOUT then" in g)
    ck("G3 $sl_guard no longer includes int$keys.h (it needed it only for K$AUTOLOGOUT)", "$include int$keys.h" not in g)
    return out


def mutants(files):
    src, guard = files["linuxio"], files["sl_guard"]
    M = []

    def lx(name, old, new):
        M.append((name, dict(files, linuxio=src.replace(old, new, 1))))

    def gd(name, old, new):
        M.append((name, dict(files, sl_guard=guard.replace(old, new, 1))))

    lx("the old rule: AUTOLOGOUT only when it is shorter than the caller's timeout",
       "      if (!timeout)\n        using_autologout = TRUE;\n      else if (idle_waited == 0)\n        using_autologout = (idle_left < (int64)timeout);\n"
       "      else\n        using_autologout = (idle_left <= (int64)timeout);\n", "      using_autologout = (autologout < timeout) || !timeout;\n")
    lx("nothing carried and a wait EQUAL to the period logs out (the review's finding: '<=' with no carry)",
       "      else if (idle_waited == 0)\n        using_autologout = (idle_left < (int64)timeout);\n",
       "      else if (idle_waited == 0)\n        using_autologout = (idle_left <= (int64)timeout);\n")
    lx("one '<=' test for both cases (the version the review found)",
       "      if (!timeout)\n        using_autologout = TRUE;\n      else if (idle_waited == 0)\n        using_autologout = (idle_left < (int64)timeout);\n"
       "      else\n        using_autologout = (idle_left <= (int64)timeout);\n", "      using_autologout = (!timeout) || (idle_left <= (int64)timeout);\n")
    lx("a carried clock tested strictly (the rest of the period equal to the caller's timeout would not log out)",
       "      else\n        using_autologout = (idle_left <= (int64)timeout);\n", "      else\n        using_autologout = (idle_left < (int64)timeout);\n")
    lx("a wait with no timeout of its own no longer takes the inactivity period", "      if (!timeout)\n        using_autologout = TRUE;\n",
       "      if (!timeout)\n        using_autologout = FALSE;\n")
    lx("the polling consequence is no longer written down",
       "KNOWN AND\n *               INTENDED", "As\n *               it happens")
    lx("the whole period every call (idle_waited not subtracted)",
       "idle_left = (int64)autologout - idle_waited;", "idle_left = (int64)autologout;")
    lx("the wait is not added to the clock", "          idle_waited += td; /* 28 Oct 26 S.88 (S3): the time waited with nothing typed */\n", "")
    lx("the clock is never started again on entry", "  if (!idle_carry)\n    idle_waited = 0;\n", "")
    lx("idle_carry is not cleared on entry (a byte would not start the clock again)", "    idle_waited = 0;\n  idle_carry = FALSE;\n", "    idle_waited = 0;\n")
    lx("the caller's timeout does not carry the clock",
       "            } else {\n              idle_carry = TRUE; /* 28 Oct 26 S.88 (S3): the caller's own timeout: the next wait goes on counting */\n            }\n",
       "            }\n")
    lx("an interrupt carries the clock",
       "          /* Force our way out for logout, etc */\n          input_handler_enabled = TRUE;\n          return 0;",
       "          /* Force our way out for logout, etc */\n          input_handler_enabled = TRUE;\n          idle_carry = TRUE;\n          return 0;")
    lx("a byte of input carries the clock", "exit_keyin:\n", "exit_keyin:\n  idle_carry = TRUE;\n")
    lx("the logout no longer ends the session", "              Sleep(3000);\n              k_exit_cause = K_TERMINATE;\n", "              Sleep(3000);\n")
    lx("the logout says something else", "log_printf(\"%s\\n\", sysmsg(2503));", "log_printf(\"%s\\n\", sysmsg(2504));")
    lx("the clock is moved somewhere else as well", "    if (using_autologout)\n      timeout = (int)idle_left;", "    if (using_autologout)\n      timeout = (int)idle_left;\n    idle_waited = 0;")
    gd("$sl_guard waits for the key alone with AUTOLOGOUT set again",
       "      k = keyin(1)", "      slice = (if kernel(K$AUTOLOGOUT, -1) then 0 else 1)\n      if slice then k = keyin(slice) else k = keyin()")
    gd("$sl_guard no longer tells a timeout from an ended input", "         if kst # ER$TIMEOUT then", "         if 1 then")
    gd("$sl_guard waits for ever", "      k = keyin(1)", "      k = keyin()")
    lx("keyin_idle_ms() gives the clock after a byte too (the carry is not asked)", "int64 ms = idle_carry ? idle_waited : 0;", "int64 ms = idle_waited;")
    M.append(("kernel(K$AUTOLOGOUT, -2) answers the period", dict(files, op_kernel=files["op_kernel"].replace(
        "(descr->data.value == -2) ? keyin_idle_ms() : autologout", "autologout", 1))))
    return M


def load():
    files = {}
    for k, p in (("linuxio", LINUXIO), ("sl_guard", SLGUARD), ("2503", MSG2503), ("op_kernel", OPKERNEL), ("sd_h", SDH)):
        if not os.path.isfile(p):
            return None, p
        with open(p, encoding="latin-1") as f:
            files[k] = f.read()
    return files, None


def main():
    files, missing = load()
    if files is None:
        print("test-autologout-units: CANNOT RUN - no file %s" % missing)
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
        print("test-autologout-units --selftest: %d mutant(s), %d not caught" % (len(ms), bad))
        return 1 if bad else 0
    print("linuxio.c : %s\nsl_guard  : %s\nmessage   : %s" % (LINUXIO, SLGUARD, MSG2503))
    res = checks(files)
    fails = 0
    for name, ok, detail in res:
        print("  [%s] %s%s" % ("PASS" if ok else "FAIL", name, "" if ok or not detail else "  (" + str(detail) + ")"))
        fails += 0 if ok else 1
    if len(res) < 11:
        print("test-autologout-units: only %d checks ran - refusing to pass" % len(res))
        return 1
    print("test-autologout-units: %d checks, %d failed" % (len(res), fails))
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
