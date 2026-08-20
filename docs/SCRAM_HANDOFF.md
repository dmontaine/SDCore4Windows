# SCRAM work — handoff, 19 Aug 2026

State at the end of the first session. Design and rationale are in
[SCRAM_AUTH.md](SCRAM_AUTH.md); this is the operational half — what is built,
what is deployed, and what to do next.

## Where it stands

**Phases 1 to 3 are complete and verified. Phases 4 to 6 are not started.**

Nothing on the existing login path has changed. Request 24 still reaches
`vb.login`, which still calls `!CRED_VERIFY` with the same signature — and
that is a measured check, not an assumption. The work so far is entirely
additive, and phase 5 remains the only point of no return.

| Phase | | Verified by |
| --- | --- | --- |
| 1 | Crypto primitives, C and the `SDEXT` bridge | `gplbld/verify-scram.c` in C; `sdsys/bp/TESTSCRAM` through BASIC |
| 2 | `$CRED` version 2, `!CRED_SET`, `!CRED_VERIFY`, `SET.PASSWORD` | `sdsys/bp/TESTCRED` |
| 3 | Server exchange, request types 47 and 48 in `APISRVR` | `gplbld/verify-scramlogin.ps1` — **24/24**, 21:03:41 install, 19 Aug 2026 |
| 4 | Client exchange in `sdclilib.c` | not started |
| 5 | Retire `SrvrLogin` | not started |
| 6 | Rebuild both DLLs, re-set passwords, test against mvDeveloper | not started |

## Phase 3, and how to re-run it

**`verify-scramlogin.ps1` is 24/24 on the 21:03:41 install of 19 Aug 2026.**
It has two modes, and the offline one is the first thing to reach for.

```powershell
gplbld\verify-scramlogin.ps1 -SelfTest             UNELEVATED, no server, no install
gplbld\verify-scramlogin.ps1 -Prefix sdscram2      ELEVATED, fresh prefix each run
```

`-SelfTest` checks the script's own client-side derivation against the RFC 7677
vectors — the same `New-ScramProof` the live checks use, not a copy. Run it
first whenever the exchange fails and it is not obvious which side is wrong: if
it passes, the instrument is sound and the disagreement is SD's.

**The live run needs a `-Prefix` nobody has used**, `sdscram1` is spent, and it
changes the installed system and puts it back in a `finally` — throwaway
account, `APIPORT` in `sd.conf`, two service restarts. It leaves the
`ACCOUNTS` and `$CRED` records for `DELETE.ACCOUNT` on purpose, so a
half-failed `CREATE.ACCOUNT` cannot hide.

**What to look at first if it fails.** `47 accepted` failing means the handler
did not run or `$cred` did not open; `48 accepted` failing with `47` green
means the AuthMessage the two sides assembled differ, and the string to
suspect is `server-first` — `scram.sfirst` is stored verbatim on purpose, so a
mismatch means the client rebuilt it rather than echoing it.

**Two gaps in the suite, neither needing a cycle.** The `5272` refusals assert
only that `server.error` was non-zero and never check the message text; `5274`
is unexercised, being the server-fault path. `5017` and `5273` were both
observed reaching the client.

Both test programs use the RFC 7677 section 3 vectors, which were recomputed
independently before being written down, so a failure is the implementation and
not a mistranscribed constant.

## THE HAND-PATCHING IS GONE — this section is kept for what it warns about

Until 19 Aug 2026 the install was hand-patched: `sd.exe`, `INT$KEYS.H`,
`CRED_SET`, `CRED_VERIFY`, `SET_ACC_PASSWORD`, `KEYS.H`, `TESTSCRAM` and
`TESTCRED` had been copied in rather than installed, because cycling would
delete `C:\ProgramData\SD`. **The cycle of 19 Aug did exactly that and the
tree was rebuilt from source**, so none of it applies any more.
`assert-current` is exit 0 against the 21:03:41 install.

**What the episode is worth remembering for:**

- **A cycle deletes the data tree, and things that only exist there go with
  it.** The `don` account and `APIPORT=4243` both did. `APIPORT` ships
  commented out, so the API does not listen at all on a fresh install until
  something sets it — `verify-scramlogin.ps1` and `verify-apiport.ps1` both
  set it and put it back rather than depending on it.
- **Hand-patching is safe only while `config.h` and `sysseg.h` are untouched.**
  Those fix the shared-segment layout, and HISTORY.md records that copying one
  rebuilt binary onto a running system is fatal when they change. That is why
  the hand-patching was survivable, not that it was a good idea.

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
