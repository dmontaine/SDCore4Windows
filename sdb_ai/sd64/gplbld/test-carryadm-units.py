"""verify-carry-run.py's administrator stand-in, adm() (RELEASE_1.1 254), must dispatch and refuse as its header says.

WHY THIS EXISTS.  13 Nov 2026.  Linux's sandbox suites make administrator sessions with SDTEST_ADMIN=1 (adm()) and fixture
accounts; on Windows the administrator is the OS account SDSYS, reached only through the SDSYS seat, and the run is
elevated (verify-carry-adm.ps1).  The launcher's adm mode sends those sessions to the seat (verify-carry-seat.ps1), maps
gpl.bp onto the installed SDSYS's bp, never recompiles CPROC, and guards the installed SDSYS.  An ordinary run must refuse
every suite that needs it (exit 2), so such a suite can never read as a PASS.  None of that can be run without an
elevated sitting and SDSYS signed in, and a wrong stand-in fails quietly: a session sent as the caller instead of SDSYS, a
seat that did not run read as "SD printed nothing", a register record of the install overwritten, a refusal that lets the
suite through.  This guard drives every decision without SD: the seat is a recorder, SDSYS is a scratch folder reached
through a real junction, and the launcher's main() runs in child processes against throwaway suites.

Pure Python: no SD, no install, no elevation.  An optional argument names another copy of the launcher (that is how a
mutant is tried without touching the live file).

  python gplbld/test-carryadm-units.py [launcher.py]
  python gplbld/test-carryadm-units.py --selftest [--from=N]

--selftest makes one copy of the live launcher per MUT-ADM- line, each with that one check broken, runs this guard on it and
requires exit 1; then requires the live launcher green and byte-identical (SHA-256) afterwards.  --from=N starts at the N-th
mutant (rule 3 of the testing budget: a sitting runs its own mutants).

Exit 0 all checks passed, 1 a check failed (or a mutant survived), 2 the launcher is not there to read.
"""

import hashlib
import importlib.util
import io
import os
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
LIVE = os.path.join(HERE, "verify-carry-run.py")
ARGS = [a for a in sys.argv[1:] if not a.startswith("--")]
LAUNCHER = os.path.abspath(ARGS[0]) if ARGS else LIVE

failures = 0
passes = 0

# Each mutant: (tag on the launcher line, text in that line, what it becomes).  One check below must go red for each.
MUTANTS = [
    ("MUT-ADM-ELEV", "if not is_elevated():", "if False:"),
    ("MUT-ADM-SAMESYS", "if not same:", "if False:"),
    ("MUT-ADM-GUARD", "return rp is not None and rp in self.before", "return False"),
    ("MUT-ADM-CPROCWRITE", 'if name.lower() == "cproc":', "if False:"),
    ("MUT-ADM-MARK", "fh.read() + CPROC_MARK", "fh.read()"),
    ("MUT-ADM-LEAD", 'if lines and lines[0] == "":', "if False:"),
    ("MUT-ADM-OFF", 'if lines and lines[-1].strip().upper() == "OFF":', "if False:"),
    ("MUT-ADM-SEATFAIL", 'if m.group(1) != "1":', "if False:"),
    ("MUT-ADM-CONTROL", 'with real_open(ctl, "w", encoding="ascii", newline="\\n") as fh:', "with io.StringIO() as fh:"),
    ("MUT-ADM-GPLBP", 'c = GPLBP_WORD.sub("bp", c)', "c = c"),
    ("MUT-ADM-ACCTINT", "internal = True", "internal = internal"),
    ("MUT-ADM-RUNREFUSE", "if ADM is None and wants_admin(kw):", "if False:"),
    ("MUT-ADM-LIBREFUSE", "if ADM is None:", "if False:"),
    ("MUT-ADM-SUITEREFUSE", "if name in ADM_SUITES:", "if False:"),
]


def check(label, ok, detail=""):
    global failures, passes
    if ok:
        passes += 1
        print("  [PASS] " + label)
    else:
        failures += 1
        print("  [FAIL] " + label + ("   <- " + str(detail) if detail else ""))


def load():
    if not os.path.isfile(LAUNCHER):
        print("test-carryadm-units: no launcher at %s" % LAUNCHER)
        sys.exit(2)
    spec = importlib.util.spec_from_file_location("vca_under_test", LAUNCHER)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def raises_cannot(mod, fn):
    """(True, message) when fn() raises the launcher's CarryCannotRun."""
    try:
        fn()
    except mod.CarryCannotRun as e:
        return True, str(e)
    except Exception as e:                      # noqa: BLE001 - any other outcome is the failure being looked for
        return False, "%s: %s" % (type(e).__name__, e)
    return False, "nothing was raised"


def put(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(text)


def junction(link, target):
    r = subprocess.run(["cmd", "/c", "mklink", "/J", link, target], capture_output=True, text=True)
    return r.returncode == 0 and os.path.isdir(link)


def child(args, env_extra, drop=()):
    env = dict(os.environ)
    for k in list(env):
        if k.startswith("SD_CARRY_") or k == "SDTEST_ADMIN" or k in drop:
            env.pop(k, None)
    env.update(env_extra)
    return subprocess.run([sys.executable, "-X", "utf8", LAUNCHER] + args, capture_output=True, text=True, errors="replace",
                          env=env, timeout=120)


SUITE_BODY = """import importlib.util, os, subprocess, sys
here = os.path.dirname(os.path.abspath(__file__))
box = os.path.abspath(sys.argv[1])
mode = %r
if mode == "lib":
    importlib.util.spec_from_file_location("q3", os.path.join(here, "sandbox-stmt-q3.py"))
if mode in ("admin", "plain"):
    env = dict(os.environ)
    if mode == "admin":
        env["SDTEST_ADMIN"] = "1"
    subprocess.run([os.path.join(box, "sys", "bin", "sd")], input="", env=env, capture_output=True, text=True, timeout=60)
open(os.path.join(box, "ran-" + os.path.basename(__file__) + ".txt"), "w").close()
print("  [PASS] the throwaway suite ran (%%s)" %% mode)
"""


def main_checks(scratch):
    """The launcher's main(): an ordinary run refuses what needs adm(), and still runs what does not."""
    print("\n--- an ordinary run (no SD_CARRY_ADM): refusals, and the control that a suite still runs ----------------------")
    sdir = os.path.join(scratch, "suites")
    box = os.path.join(scratch, "obox")
    os.makedirs(os.path.join(box, "sys"))
    os.makedirs(sdir)
    # SD_EXE is this python: the launcher's "no sd.exe" refusal must not be what answers (a refusal that would pass trivially).
    env = {"SD_EXE": sys.executable, "SD_CARRY_CONF": os.path.join(scratch, "no-such.conf")}

    def run_suite(fname, mode):
        p = os.path.join(sdir, fname)
        put(p, SUITE_BODY % mode)
        r = child([p, box], env)
        ran = os.path.isfile(os.path.join(box, "ran-" + fname + ".txt"))
        return r, ran

    r, ran = run_suite("verify-carry-zzctl.py", "none")
    check("M0 CONTROL: a suite that needs nothing runs in an ordinary run, exit 0, its row printed",
          r.returncode == 0 and ran and "[PASS] the throwaway suite ran" in r.stdout, (r.returncode, ran, r.stdout[-300:]))
    r, ran = run_suite("verify-carry-zzplain.py", "plain")
    check("M1 CONTROL: an ordinary session (no SDTEST_ADMIN) is still sent to SD_EXE, exit 0",
          r.returncode == 0 and ran, (r.returncode, ran, r.stdout[-300:], r.stderr[-300:]))
    r, ran = run_suite("verify-carry-gates.py", "none")
    check("M2 a suite in ADM_SUITES (gates) is refused before it runs: exit 2, CANNOT RUN, nothing of it executed",
          r.returncode == 2 and not ran and "CANNOT RUN" in r.stdout and "verify-carry-adm.ps1" in r.stdout,
          (r.returncode, ran, r.stdout[-300:]))
    r, ran = run_suite("verify-carry-zzlib.py", "lib")
    check("M3 a suite that loads sandbox-stmt-q3.py is refused: exit 2, CANNOT RUN, and its later lines never ran",
          r.returncode == 2 and not ran and "CANNOT RUN" in r.stdout, (r.returncode, ran, r.stdout[-300:]))
    r, ran = run_suite("verify-carry-zzadm.py", "admin")
    check("M4 a suite that starts an SDTEST_ADMIN=1 session is refused: exit 2, CANNOT RUN, nothing after it ran",
          r.returncode == 2 and not ran and "SDTEST_ADMIN" in r.stdout, (r.returncode, ran, r.stdout[-300:]))
    r = child([os.path.join(sdir, "verify-carry-zzctl.py"), box], dict(env, SD_CARRY_ADM="1", SD_CARRY_RUN="zz1"))
    check("M5 adm mode for a suite NOT in ADM_SUITES is refused (the installed SDSYS is only for the cleared suites)",
          r.returncode == 2 and "not one of the suites cleared" in r.stdout, (r.returncode, r.stdout[-300:]))
    r = child(["--adm-suites"], {})
    listed = [ln.strip() for ln in r.stdout.splitlines() if ln.strip()]
    check("M6 --adm-suites lists the nine of row 254, the stmt-q3 family and net (what verify-carry-adm.ps1 runs)",
          r.returncode == 0 and all(n in listed for n in ("gates", "sdaccts", "shared", "editgates", "runin", "ospath", "prof",
                                                           "resetall", "stmt-q3", "classinit", "nameindex", "q4", "q5",
                                                           "restricted", "net")), listed)
    check("M7 the suites that change SDSYS's own files (cmd-a9 deletes stacks, inhibit-q8 writes login.inhibit) are NOT cleared",
          r.returncode == 0 and not any(n in listed for n in ("cmd-a9", "inhibit-q8", "listu-a5", "crypt")), listed)


def adm_checks(mod, scratch):
    print("\n--- adm mode: the seat, the gpl.bp map, CPROC, the guard ------------------------------------------------------")
    sdsys = os.path.join(scratch, "sdsys")
    for d in ("accounts", "bp", "bp.out", "gcat"):
        os.makedirs(os.path.join(sdsys, d))
    put(os.path.join(sdsys, "accounts", "shared"), "C:/ProgramData/SD/user_accounts/shared\n")
    put(os.path.join(sdsys, "accounts", "zzold"), "a zz record that was there before the suite\n")
    put(os.path.join(sdsys, "audit"), "")
    gplsrc = os.path.join(scratch, "gplsrc")
    put(os.path.join(gplsrc, "cproc"), "* the tree's cproc source\n   $catalog $CPROC\n")
    put(os.path.join(gplsrc, "blockprt"), "* the tree's blockprt source\n")
    box = os.path.join(scratch, "abox")
    os.makedirs(os.path.join(box, "user_accounts"))
    sys_link = os.path.join(box, "sys")
    if not junction(sys_link, sdsys):
        check("A0 a junction <box>/sys -> the scratch SDSYS could be made (mklink /J)", False, sys_link)
        return
    try:
        cfg = mod.adm_config({"SD_CARRY_ADM": "1", "SD_CARRY_SDSYS": sdsys, "SD_CARRY_GROUP": "sdu_zztest",
                              "SD_CARRY_SEAT": LAUNCHER, "SD_CARRY_GPLSRC": gplsrc, "SD_CARRY_RUN": "zz1"}, box)
        check("A0 adm_config is None without SD_CARRY_ADM=1, a dict with it",
              mod.adm_config({}, box) is None and isinstance(cfg, dict) and cfg["sys"] == sys_link, cfg)

        # --- preflight ------------------------------------------------------------------------------------------
        real_elev = mod.is_elevated
        mod.is_elevated = lambda: True
        check("A1 CONTROL: preflight passes an elevated run of a cleared suite whose sys IS the SDSYS",
              mod.adm_preflight(cfg, "gates") == [], mod.adm_preflight(cfg, "gates"))
        mod.is_elevated = lambda: False
        bad = mod.adm_preflight(cfg, "gates")
        check("A2 preflight refuses an UNELEVATED run", any("not elevated" in b for b in bad), bad)
        mod.is_elevated = lambda: True
        other = dict(cfg, sys=os.path.join(scratch, "elsewhere"))
        os.makedirs(other["sys"])
        bad = mod.adm_preflight(other, "gates")
        check("A3 preflight refuses a <box>/sys that is not the installed SDSYS", any("is not the installed SDSYS" in b for b in bad), bad)
        bad = mod.adm_preflight(dict(cfg, run="Bad-1", group=""), "cmd-a9")
        check("A4 preflight refuses a suite not cleared, a bad run token and a missing group (three reasons)", len(bad) == 3, bad)
        mod.is_elevated = real_elev

        mod.ADM = cfg
        mod.ADM_GUARD = mod.SdsysGuard(sdsys)
        mod.ADM_STATE["gpl_written"] = set()
        seen = []
        replies = {"text": ":TERM 200,9999\nCompiled 1 program(s) with no errors\n:OFF\n"}

        def fake_seat(lines, internal, timeout):
            seen.append((list(lines), internal))
            return replies["text"]
        mod.SEAT_RUNNER = fake_seat
        plain_calls = []
        mod.real_run = lambda args, *a, **kw: plain_calls.append(list(args)) or mod.subprocess.CompletedProcess(args, 0, "", "")
        sd = os.path.join(box, "sys", "bin", "sd")
        admin_env = {"SDTEST_ADMIN": "1"}

        # --- dispatch -------------------------------------------------------------------------------------------
        r = mod.patched_run([sd], input="\nTERM 200,9999\nBASIC bp zzfix\nRUN bp zzfix\nOFF\n", env=admin_env,
                            capture_output=True, text=True)
        check("D1 an SDTEST_ADMIN session goes to the seat with Linux's lines, minus its leading empty line and closing OFF",
              seen and seen[-1] == (["TERM 200,9999", "BASIC bp zzfix", "RUN bp zzfix"], False) and not plain_calls, seen[-1:])
        check("D2 ...and the suite gets SD's text back as str in text mode",
              isinstance(r.stdout, str) and "Compiled 1 program(s) with no errors" in r.stdout, repr(r.stdout)[:120])
        r = mod.patched_run([sd, "-internal"], input=b"\nTERM 200,9999\nWHO\nOFF\n", env={}, capture_output=True)
        check("D3 -internal (even without SDTEST_ADMIN) is the seat's internal door; bytes in, bytes out",
              seen[-1] == (["TERM 200,9999", "WHO"], True) and isinstance(r.stdout, bytes), (seen[-1], type(r.stdout)))
        mod.patched_run([sd, "-internal"], input="\nTERM 200,9999\nBASIC gpl.bp zzkf zzkp\nRUN gpl.bp.out x\nOFF\n",
                        env=admin_env, capture_output=True, text=True)
        check("D4 'gpl.bp' in an administrator command reads 'bp' (the installed SDSYS has no gpl.bp); gpl.bp.out is untouched",
              seen[-1][0] == ["TERM 200,9999", "BASIC bp zzkf zzkp", "RUN gpl.bp.out x"], seen[-1])
        say_lines = io.StringIO()
        real_stdout = sys.stdout
        sys.stdout = say_lines
        try:
            mod.patched_run([sd, "-azzoff"], input="\nTERM 200,9999\nZZKF\nOFF\n", env=admin_env, capture_output=True, text=True)
        finally:
            sys.stdout = real_stdout
        check("D5 an administrator session in a fixture account is the INTERNAL seat with LOGTO first, and says LOGTO ends it",
              seen[-1] == (["LOGTO zzoff", "TERM 200,9999", "ZZKF"], True) and "LOGTO ends the administrator session" in say_lines.getvalue(),
              (seen[-1], say_lines.getvalue()[-200:]))
        n_seat = len(seen)
        mod.patched_run([sd, "-azzoff"], input="\nTERM 200,9999\nZZKF\nOFF\n", env={}, capture_output=True, text=True)
        check("D6 CONTROL: an ordinary session in adm mode is NOT the seat: it goes to sd.exe as the caller",
              len(seen) == n_seat and plain_calls and plain_calls[-1] == [mod.SD_EXE, "-azzoff"], plain_calls[-1:])
        r = mod.patched_run(["id", "-gn"], capture_output=True, text=True)
        check("D7 `id -gn` answers the fixture accounts' group", r.stdout == "sdu_zztest\n", repr(r.stdout))
        ok, msg = raises_cannot(mod, lambda: mod.patched_run(["id", "-u"], capture_output=True, text=True))
        check("D8 any other `id` stops the suite (exit 2), not a made-up answer", ok, msg)
        ok, msg = raises_cannot(mod, lambda: mod.PatchedPopen([sd], stdin=subprocess.PIPE, env=admin_env))
        check("D9 a HELD administrator session (Popen, SDTEST_ADMIN=1) stops the suite: the seat is one batch", ok, msg)
        ok, msg = raises_cannot(mod, lambda: mod.patched_run([sd, "-x"], input="\nWHO\nOFF\n", env=admin_env, text=True))
        check("D10 an administrator session with an argument the seat cannot pass stops the suite", ok, msg)

        # --- the seat's report ----------------------------------------------------------------------------------
        good = "SEATBRIDGE ok=1\nwhy=\ndetail=task x, LastTaskResult 0\n---\n:TERM 200,9999\n1 SDSYS\nENDOFBRIDGE\n"
        check("S1 CONTROL: a whole report gives SD's lines", mod.parse_bridge(good) == ":TERM 200,9999\n1 SDSYS",
              repr(mod.parse_bridge(good)))
        ok, msg = raises_cannot(mod, lambda: mod.parse_bridge(good.replace("ok=1", "ok=0").replace("why=", "why=no live session for SDSYS")))
        check("S2 a seat that did not run (ok=0) stops the suite, with the seat's reason", ok and "no live session" in msg, msg)
        ok, msg = raises_cannot(mod, lambda: mod.parse_bridge(good.replace("ENDOFBRIDGE\n", "")))
        check("S3 a report cut off (no ENDOFBRIDGE) stops the suite", ok, msg)
        ok, msg = raises_cannot(mod, lambda: mod.parse_bridge("", 1, "powershell: cannot find the file"))
        check("S4 NULL CASE: no report at all stops the suite; it is never read as 'SD printed nothing'", ok, msg)

        # --- CPROC ----------------------------------------------------------------------------------------------
        gp = os.path.join(box, "sys", "gpl.bp")
        handled, res = mod.adm_open(os.path.join(gp, "cproc"), "r", (), {"encoding": "utf-8", "errors": "replace"})
        text = res.read() if handled else ""
        check("C1 a read of <sys>/gpl.bp/cproc is the tree's source with a comment naming SDTEST_ADMIN (so prepare() patches nothing)",
              handled and "the tree's cproc source" in text and "SDTEST_ADMIN" in text, repr(text)[:160])
        before = len(seen)
        real_stdout = sys.stdout
        sys.stdout = say_lines = io.StringIO()
        try:
            r = mod.patched_run([sd, "-internal"], input="\nTERM 200,9999\nBASIC gpl.bp cproc\nOFF\n", env=admin_env,
                                capture_output=True, text=True)
        finally:
            sys.stdout = real_stdout
        ctl = os.path.join(sdsys, "bp", mod.CONTROL_PROG)
        check("C2 'BASIC gpl.bp cproc' is NOT sent: the seat compiles the control program instead, and says so",
              len(seen) == before + 1 and seen[-1][0] == ["TERM 200,9999", "BASIC bp " + mod.CONTROL_PROG]
              and "IS NOT RUN" in say_lines.getvalue(), (seen[-1:], say_lines.getvalue()[-160:]))
        check("C3 ...the control program really is in SDSYS's bp for SD to compile (the compile line is SD's own)",
              os.path.isfile(ctl) and "carry adm control" in open(ctl).read(), ctl)
        ok, msg = raises_cannot(mod, lambda: mod.adm_open(os.path.join(gp, "cproc"), "w", (), {}))
        check("C4 a suite that WRITES a cproc (runin's --mutant) stops: the installed CPROC is never recompiled", ok, msg)

        # --- gpl.bp ---------------------------------------------------------------------------------------------
        handled, p = mod.adm_open(os.path.join(gp, "zzkf"), "w", (), {})
        check("G1 a write of <sys>/gpl.bp/zzkf goes to <sys>/bp/zzkf", not handled and p == os.path.join(box, "sys", "bp", "zzkf"), p)
        put(p, "$internal\ncrt 'KFLAGS'\nend\n")
        handled, p2 = mod.adm_open(os.path.join(gp, "zzkf"), "r", (), {})
        check("G2 ...and reading it back finds the one written", not handled and p2 == p, p2)
        handled, p3 = mod.adm_open(os.path.join(gp, "blockprt"), "r", (), {})
        check("G3 a read of a gpl.bp source the suite did not write is the tree's", not handled and p3 == os.path.join(gplsrc, "blockprt"), p3)

        # --- the guard ------------------------------------------------------------------------------------------
        ok, msg = raises_cannot(mod, lambda: mod.adm_open(os.path.join(box, "sys", "accounts", "shared"), "w", (), {}))
        check("R1 a register record the install owns (accounts/shared) may not be written through the junction", ok, msg)
        handled, f = mod.adm_open(os.path.join(box, "sys", "audit"), "a", (), {})
        ok, msg = raises_cannot(mod, lambda: f.write("x"))
        if handled:
            f.close()
        check("R2 append-open of an install file (the suites' 'make sure it exists') is allowed; a write through it stops",
              handled and ok and os.path.getsize(os.path.join(sdsys, "audit")) == 0, (handled, msg))
        newrec = os.path.join(box, "sys", "accounts", "zzoff")
        handled, p = mod.adm_open(newrec, "w", (), {})
        put(p, "C:/x\n\nsdu_zztest\n")
        check("R3 CONTROL: a NEW register record (a fixture account) may be written", not handled and os.path.isfile(newrec), p)
        rm = mod.guarded(os.remove, "delete")
        ok, msg = raises_cannot(mod, lambda: rm(os.path.join(box, "sys", "accounts", "zzold")))
        check("R4 deleting a file the install owns stops the suite, even a zz-named one that was there before", ok, msg)
        put(os.path.join(sdsys, "gcat", "$zzkf"), "object")            # what SD makes when it catalogues a probe
        put(os.path.join(sdsys, "bp.out", "zzfix"), "object")
        put(os.path.join(sdsys, "errlog.1"), "SD's own new file")
        removed, kept, failed = mod.ADM_GUARD.cleanup()
        gone = [os.path.basename(x) for x in removed]
        check("R5 cleanup removes what the run made: the record it wrote, the probes, SD's objects of them, the control",
              all(n in gone for n in ("zzoff", "$zzkf", "zzfix", "zzkf", mod.CONTROL_PROG)) and not failed, (gone, failed))
        check("R6 cleanup keeps (and names) a new file that is SD's own, and never touches what was there before",
              any(k.endswith("errlog.1") for k in kept) and os.path.isfile(os.path.join(sdsys, "accounts", "shared"))
              and os.path.isfile(os.path.join(sdsys, "accounts", "zzold")), (kept, gone))

        # --- refusals in an ordinary run (in-process) ------------------------------------------------------------
        mod.ADM = None
        mod.ADM_GUARD = None
        ok, msg = raises_cannot(mod, lambda: mod.patched_run([sd], input="\nWHO\nOFF\n", env=admin_env, text=True))
        check("O1 ordinary run: an SDTEST_ADMIN session stops the suite (exit 2), it is never run as the caller", ok, msg)
        ok, msg = raises_cannot(mod, lambda: mod.patched_spec("q3", os.path.join(HERE, "sandbox-stmt-q3.py")))
        check("O2 ordinary run: loading sandbox-stmt-q3.py stops the suite", ok, msg)
        ok, msg = raises_cannot(mod, lambda: mod.PatchedPopen([sd], stdin=subprocess.PIPE, env=admin_env))
        check("O3 ordinary run: a held SDTEST_ADMIN session stops the suite", ok, msg)
    finally:
        mod.ADM = None
        mod.ADM_GUARD = None
        try:
            os.rmdir(sys_link)                   # the junction itself, before anything removes the folder it points at
        except OSError:
            pass


def static_checks():
    print("\n--- verify-carry-adm.ps1, verify-carry-seat.ps1, verify-carry-known.psd1 -------------------------------------")
    adm = open(os.path.join(HERE, "verify-carry-adm.ps1"), encoding="utf-8").read().replace("\r\n", "\n")
    seat = open(os.path.join(HERE, "verify-carry-seat.ps1"), encoding="utf-8").read().replace("\r\n", "\n")
    i_elev = adm.find("WindowsBuiltInRole]::Administrator")
    check("P1 verify-carry-adm.ps1 refuses an unelevated shell with exit 2 before anything runs",
          i_elev > 0 and re.search(r"Administrator\)\)\s*\{\s*\n\s*Bail 2 'NOT ELEVATED", adm) is not None
          and i_elev < adm.find("& (Join-Path $Gplbld 'assert-current.ps1')"))
    check("P2 it requires a -Run token of lower-case letters and digits and refuses a spent one (the box exists)",
          "$Run -notmatch '^[a-z0-9]+$'" in adm and "is spent" in adm)
    i_try = adm.find("$noJunction = $false\ntry {")
    i_j = adm.find("New-Item -ItemType Junction")
    i_del = adm.find("[System.IO.Directory]::Delete($sysLink, $false)")
    i_rm = adm.find("Remove-Item -LiteralPath $box -Recurse")
    check("P3 the junction to SDSYS is made inside the try, and removed by itself BEFORE the box is removed recursively",
          0 < i_try < i_j and 0 < i_del < i_rm, (i_try, i_j, i_del, i_rm))
    check("P4 it sets SD_CARRY_ADM=1 for the launcher and proves the seat's internal door first (Assert-SdSeat -Internal)",
          "$env:SD_CARRY_ADM    = '1'" in adm and "Assert-SdSeat -Label 'verify-carry-adm' -Internal" in adm)
    check("P5 the seat bridge dot-sources sdsys-seat.ps1, runs Invoke-SdViaSeat and frames its report",
          "'sdsys-seat.ps1'" in seat and "Invoke-SdViaSeat" in seat and "SEATBRIDGE ok=" in seat and "ENDOFBRIDGE" in seat)
    psd1 = open(os.path.join(HERE, "verify-carry-known.psd1"), encoding="utf-8").read()
    m = re.search(r"(?ms)^\s*NotRun\s*=\s*@\{(.*?)^\s*Rows\s*=\s*@\{", psd1)
    notrun = m.group(1) if m else ""
    missing = []
    src = open(LIVE, encoding="utf-8").read()
    m = re.search(r"ADM_SUITES = \(([^)]*)\)", src)
    names = re.findall(r'"([a-z0-9-]+)"', m.group(1)) if m else []
    for n in names:
        if os.path.isfile(os.path.join(HERE, "verify-carry-%s.py" % n)) and not re.search(r"(?m)^\s*'%s'\s*=" % re.escape(n), notrun):
            missing.append(n)
    check("P6 every carried adm suite is NotRun in verify-carry-known.psd1, so verify-carry.ps1 never starts it unelevated",
          names and not missing, missing or "no ADM_SUITES found")


def selftest(start):
    print("test-carryadm-units --selftest: mutants of %s, from %d" % (LIVE, start))
    with open(LIVE, "rb") as fh:
        live_bytes = fh.read()
    h0 = hashlib.sha256(live_bytes).hexdigest()
    text = live_bytes.decode("utf-8")
    scratch = tempfile.mkdtemp(prefix="vcamut")
    bad = 0
    try:
        for i, (tag, old, new) in enumerate(MUTANTS, 1):
            if i < start:
                continue
            lines = text.split("\n")
            hits = [k for k, ln in enumerate(lines) if ("# " + tag) in ln and old in ln]
            if len(hits) != 1:
                print("  [FAIL] mutant %d %s: its line must be found once, found %d" % (i, tag, len(hits)))
                bad += 1
                continue
            lines[hits[0]] = lines[hits[0]].replace(old, new, 1)
            copy = os.path.join(scratch, "m%02d" % i, "verify-carry-run.py")
            os.makedirs(os.path.dirname(copy))
            with open(copy, "w", encoding="utf-8", newline="") as fh:
                fh.write("\n".join(lines))
            r = subprocess.run([sys.executable, "-X", "utf8", os.path.abspath(__file__), copy], capture_output=True, text=True,
                               errors="replace", timeout=600)
            red = [ln.strip() for ln in r.stdout.splitlines() if ln.strip().startswith("[FAIL]")]
            if r.returncode == 1 and red:
                print("  [PASS] mutant %d %s went red (%d check(s)): %s" % (i, tag, len(red), red[0][:110]))
            else:
                print("  [FAIL] mutant %d %s SURVIVED (exit %d)" % (i, tag, r.returncode))
                bad += 1
    finally:
        shutil.rmtree(scratch, ignore_errors=True)
    r = subprocess.run([sys.executable, "-X", "utf8", os.path.abspath(__file__)], capture_output=True, text=True, errors="replace",
                       timeout=600)
    with open(LIVE, "rb") as fh:
        h1 = hashlib.sha256(fh.read()).hexdigest()
    ok = r.returncode == 0 and h0 == h1
    print("  [%s] the live launcher is green (exit %d) and unchanged (SHA-256 %s)" % ("PASS" if ok else "FAIL", r.returncode, h1[:16]))
    if not ok:
        bad += 1
    print("test-carryadm-units --selftest: %d mutant(s) tried, %d problem(s)" % (len([m for i, m in enumerate(MUTANTS, 1) if i >= start]), bad))
    return 1 if bad else 0


def main():
    if sys.platform != "win32":
        print("test-carryadm-units: Windows only")
        return 2
    if "--selftest" in sys.argv:
        start = 1
        for a in sys.argv[1:]:
            if a.startswith("--from="):
                start = int(a.split("=", 1)[1])
        return selftest(start)
    print("test-carryadm-units: launcher %s" % LAUNCHER)
    mod = load()
    scratch = tempfile.mkdtemp(prefix="vcaunits")
    try:
        main_checks(scratch)
        adm_checks(mod, scratch)
        static_checks()
    finally:
        link = os.path.join(scratch, "abox", "sys")
        if os.path.isdir(link):
            try:
                os.rmdir(link)
            except OSError:
                pass
        shutil.rmtree(scratch, ignore_errors=True)
    print("\ntest-carryadm-units: %d passed, %d failed" % (passes, failures))
    if passes == 0:
        print("test-carryadm-units: NOTHING WAS CHECKED")
        return 1
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
