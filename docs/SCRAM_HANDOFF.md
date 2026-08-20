# SCRAM work — handoff, 19 Aug 2026

State at the end of the first session. Design and rationale are in
[SCRAM_AUTH.md](SCRAM_AUTH.md); this is the operational half — what is built,
what is deployed, and what to do next.

## Where it stands

**Phases 1 and 2 are complete and verified. Phases 3 to 6 are not started.**

Nothing on the existing login path has changed. `APISRVR` still calls
`!CRED_VERIFY` with the same signature and needs no recompile. The work so far
is entirely additive, and phase 5 remains the only point of no return.

| Phase | | Verified by |
| --- | --- | --- |
| 1 | Crypto primitives, C and the `SDEXT` bridge | `gplbld/verify-scram.c` in C; `sdsys/bp/TESTSCRAM` through BASIC |
| 2 | `$CRED` version 2, `!CRED_SET`, `!CRED_VERIFY`, `SET.PASSWORD` | `sdsys/bp/TESTCRED` |
| 3 | Server exchange, request types 47 and 48 in `APISRVR` | not started |
| 4 | Client exchange in `sdclilib.c` | not started |
| 5 | Retire `SrvrLogin` | not started |
| 6 | Rebuild both DLLs, re-set passwords, test against mvDeveloper | not started |

Both test programs use the RFC 7677 section 3 vectors, which were recomputed
independently before being written down, so a failure is the implementation and
not a mistranscribed constant.

## THE INSTALLED SYSTEM IS HAND-PATCHED

Read this before running anything that reinstalls.

`cycle.ps1` — the sanctioned deploy — **deletes both trees** and installs
fresh. That is deliberate and documented in its own synopsis. It would remove
`C:\ProgramData\SD`, and with it:

- the `don` account adopted on 19 Aug 2026,
- `APIPORT=4243` in `sd.conf`, which was commented out on a fresh install and
  had to be enabled by hand before the API would listen at all,
- `sdsys/bp/TESTSCRAM` and `sdsys/bp/TESTCRED` — though both are now in the
  source tree, so an install would restore them.

Rather than cycle, the following were copied into the running install by hand.
A proper cycle is owed before anything ships.

| Copied to the install | From |
| --- | --- |
| `usr/bin/sd.exe` | `sdb_ai/sd64/bin/sd.exe` |
| `sdsys/gpl.bp/INT$KEYS.H`, `CRED_SET`, `CRED_VERIFY`, `SET_ACC_PASSWORD` | source tree |
| `sdsys/syscom/KEYS.H` | source tree |
| `sdsys/bp/TESTSCRAM`, `TESTCRED` | source tree |

The previous `sd.exe` is backed up twice: `sdb_ai/sd64/bin/sd.exe.installed-backup-20260819`
and `C:\Program Files\SD\usr\bin\sd.exe.bak-20260819`.

**This was safe for these changes specifically** — `config.h` and `sysseg.h`
are untouched, so the shared-segment hazard HISTORY.md warns about ("fatal if
one rebuilt binary is copied onto a running system") does not apply. Check that
again before hand-patching anything else.

## Resuming

Everything that calls `SDEXT` needs SDSYS **and** internal mode, from an
**elevated** prompt:

```
sd -INTERNAL -ASDSYS
BASIC BP TESTSCRAM
RUN BP TESTSCRAM
BASIC BP TESTCRED
RUN BP TESTCRED
```

The C-side primitives test needs neither elevation nor a server, from an MSYS2
shell in `sdb_ai/sd64/gplbld`:

```
gcc -Wall -Wextra -O2 -o verify-scram.exe verify-scram.c ../gplsrc/sd_scram.c \
    -I../gplsrc -I/usr/local/include -L/usr/local/lib -lsodium && ./verify-scram.exe
```

Server build is `make sd` in `sdb_ai/sd64`, unchanged.

## Five things that bit, and will bite again

**The `SDEXT` key numbers live in two files that nothing cross-checks** —
`gplsrc/keys.h` for C and `sdsys/syscom/KEYS.H` for BASIC.

**`WARNING: SD_x is not assigned a value` is an error.** A `$define` that does
not resolve becomes an ordinary unassigned variable, so the call compiles, the
compiler reports "0 error(s)", the program is catalogued, and it calls `SDEXT`
with a null key at run time. Two programs were catalogued in that state before
it was noticed.

**`$include NAME` resolves against the source's own file, then syscom**
(`BCOMP:2990`). `gpl.bp` programs find `INT$KEYS.H` as a sibling; programs in
`bp` cannot and need `$include gpl.bp INT$KEYS.H`. `KEYS.H` is in syscom and
resolves from either.

**The source tree and the install are separate copies.** Editing the source
changes nothing until the file is copied across, and a stale installed include
fails silently in the manner above rather than reporting a missing file.

**This tree is `* -text`, and every file must stay LF.** `.gitattributes`
disables end-of-line conversion so files round-trip byte-for-byte — the tree is
a Linux distribution package stored from a Windows host, and CRLF would break
shell scripts on a Linux checkout. Any tool that rewrites a file through a
Windows text-mode write converts it to CRLF silently: Python's
`open(path, 'w')` does exactly this. The result is a commit where a two-line
change shows as 620 changed lines. Edit in place, or write bytes in binary
mode. `git show --stat` catches it — a file whose diff is far larger than the
edit was rewritten wholesale.

## Phase 3, the next task

Replace `vb.login` in `APISRVR` with handlers for request types 47 and 48. The
message formats and the derivation are in SCRAM_AUTH.md; the primitives all
exist and are proven, so this is protocol plumbing rather than cryptography.

Two things to look at before writing it:

1. **How `APISRVR` currently holds per-session state across requests.** The
   exchange is two round trips, so the client nonce, server nonce, salt and the
   assembled `AuthMessage` have to survive from 47 to 48, and a 48 arriving
   without a 47 must abort rather than proceed on empty values.
2. **Where `SrvrLogin`'s "already logged in" guard belongs** in a two-step
   exchange — whether it sits on 47, on 48, or on both.

Note that the server does **not** run PBKDF2 at login: it holds `StoredKey`
directly and needs two HMACs and a hash. The 600,000-iteration cost falls on
`SET.PASSWORD` alone.

`!CRED_VERIFY` stays after phase 3 — not on the login path any more, but
`SET_ACC_PASSWORD` still needs it for "changing your own password requires the
current one".

## The client side is a separate, unversioned project

`C:\Users\dmont\Projects\sdclilib32` builds the 32-bit `qmclilib.dll` that
mvDeveloper will use. **It is not a git repository** — worth fixing before
relying on it.

It has no copy of the library source: its Makefile points `SRCDIR` at
`../winsdclilib`, so both DLLs build from one `sdclilib.c`. Phase 4 edits that
one file and both builds pick it up. `winsdclilib` itself is untouched by the
SCRAM work so far and its working tree is clean.
