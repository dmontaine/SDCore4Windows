# SCRAM work — handoff, 19 Aug 2026

State at the end of the first session. Design and rationale are in
[SCRAM_AUTH.md](SCRAM_AUTH.md); this is the operational half — what is built,
what is deployed, and what to do next.

## Where it stands

**Phases 1 and 2 are complete and verified. Phase 3 is WRITTEN AND NOT
VERIFIED — nothing in it has been compiled. Phases 4 to 6 are not started.**

Nothing on the existing login path has changed. Request 24 still reaches
`vb.login`, which still calls `!CRED_VERIFY` with the same signature. The work
so far is entirely additive, and phase 5 remains the only point of no return.

| Phase | | Verified by |
| --- | --- | --- |
| 1 | Crypto primitives, C and the `SDEXT` bridge | `gplbld/verify-scram.c` in C; `sdsys/bp/TESTSCRAM` through BASIC |
| 2 | `$CRED` version 2, `!CRED_SET`, `!CRED_VERIFY`, `SET.PASSWORD` | `sdsys/bp/TESTCRED` |
| 3 | Server exchange, request types 47 and 48 in `APISRVR` | **written, unverified** — `gplbld/verify-scramlogin.ps1`, which needs a cycle first |
| 4 | Client exchange in `sdclilib.c` | not started |
| 5 | Retire `SrvrLogin` | not started |
| 6 | Rebuild both DLLs, re-set passwords, test against mvDeveloper | not started |

## Phase 3, what is written

| Part | State |
| --- | --- |
| `APISRVR` `vb.scram.first` / `vb.scram.final` | written, **never compiled** |
| `APISRVR` dispatch, the not-logged-in gate, `deffun` moved to the top | written, never compiled |
| `sdsys/messages/5272`, `5273`, `5274` | new |
| `gplbld/verify-scramlogin.ps1` | **`-SelfTest` run, 5/5**; the server half never run |

`-SelfTest` is unelevated, needs no server and no install, and checks the
script's own client-side derivation against the RFC 7677 vectors. Run it first
whenever the exchange fails and it is not obvious which side is wrong: if it
passes, the instrument is sound and the disagreement is SD's.

```powershell
gplbld\verify-scramlogin.ps1 -SelfTest
```

**A CYCLE IS OWED BEFORE THE REST OF IT.** `assert-current` refuses, `make sd`
is owed too (four `gplsrc` files are newer than `bin\sdclilib.dll`), and the
three new message files only exist in the source tree. Then, ELEVATED, with a
prefix nobody has used:

```powershell
gplbld\verify-scramlogin.ps1 -Prefix sdscram1
```

**What to look at first if it fails.** `47 accepted` failing means the handler
did not run or `$cred` did not open; `48 accepted` failing with `47` green
means the AuthMessage the two sides assembled differ, and the string to
suspect is `server-first` — `scram.sfirst` is stored verbatim on purpose, so a
mismatch means the client rebuilt it rather than echoing it.

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

## Phase 3, the two questions it opened, answered

**Per-session state is ordinary program variables.** `APISRVR` is one process
per connection running one `loop`, so a variable set while handling 47 is still
set when 48 arrives and no two connections share it. They are initialised
before the loop rather than in the first-time block, so `scram.stage` — the
only thing standing between a client-final and a signature check run against
empty values — is never merely unassigned.

**The "already logged in" guard sits on both**, because the main loop's gate
only *admits* 24/25/47/48 when the session is unauthenticated; it does not
block them afterwards. 48 additionally refuses itself unless `scram.stage` is
1, which is the check that gate cannot make.

Note that the server does **not** run PBKDF2 at login: it holds `StoredKey`
directly and needs two HMACs and a hash. The 600,000-iteration cost falls on
`SET.PASSWORD` alone.

`!CRED_VERIFY` stays after phase 3 — not on the login path any more, but
`SET_ACC_PASSWORD` still needs it for "changing your own password requires the
current one".

## Phase 4, the next task

Client exchange in `sdclilib.c`, behind an unchanged `QMConnect`/`SDConnect`.
`gplbld/verify-scramlogin.ps1` is a complete worked client for it — the packet
framing, the ACK wait, the message construction and the server-signature check
are all there in PowerShell, and the .NET calls map onto the `bcrypt.dll` ones
the design names.

Three things it already settles, and getting them wrong is what the C will do
by default:

- **Send the SCRAM message as the whole body, with no padding.** `SDConnect`
  pads each request-24 field to a two byte multiple with a NUL. `vb.scram.*`
  strips trailing NULs defensively, but the protocol has none.
- **Echo `server-first` verbatim into `AuthMessage`.** Do not rebuild it from
  the parsed parts.
- **A missing or wrong `v=` is a failed connection.** It is exactly the check
  that gets softened during debugging and never hardened again.

## The client side is a separate, unversioned project

`C:\Users\dmont\Projects\sdclilib32` builds the 32-bit `qmclilib.dll` that
mvDeveloper will use. **It is not a git repository** — worth fixing before
relying on it.

It has no copy of the library source: its Makefile points `SRCDIR` at
`../winsdclilib`, so both DLLs build from one `sdclilib.c`. Phase 4 edits that
one file and both builds pick it up. `winsdclilib` itself is untouched by the
SCRAM work so far and its working tree is clean.
