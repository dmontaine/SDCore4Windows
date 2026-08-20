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
| 4 | Client exchange in `sdclilib.c` | `gplbld/verify-scramclient.c` **27/27**, 64- and 32-bit; `gplbld/verify-apiport.ps1` end to end, 21:43:02 install |
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

## Phase 4, what was built

`gplsrc/sdclilib/scram_client.h` holds the primitives — base64 both ways,
SHA-256, HMAC-SHA256, PBKDF2 and the whole derivation — and `scram_login()` in
`sdclilib.c` runs the exchange. `SDConnect` calls it instead of sending
`SrvrLogin`; `QMConnect`'s signature, return and `QMError()` are unchanged, so
applications are unaffected and unaware.

**A header of `static` functions, not a second `.c`.** The client ships as ONE
binary; source may be split, the binary may not. It also lets
`gplbld/verify-scramclient.c` include the same file and check it against the
RFC 7677 vectors, so the constants test what ships rather than a second
implementation written to agree with the first. Same arrangement as
`gplsrc/sd_scram.c` and `gplbld/verify-scram.c` on the server side.

**Everything comes from `bcrypt.dll`**, which is part of Windows, so the DLL
stays a single file that can be copied next to an application. Base64 is
implemented in the header rather than taken from `crypt32` — thirty lines
against a second system dependency and `CryptBinaryToStringA`'s line-wrapping
behaviour. `-lbcrypt` is in `gplsrc/sdclilib/Makefile`.

```sh
cd sdb_ai/sd64/gplbld
gcc -Wall -Wextra -O2 -o verify-scramclient.exe verify-scramclient.c \
    -I../gplsrc/sdclilib -lbcrypt && ./verify-scramclient.exe
```

**27/27, and it was run 32-bit as well** — `/c/msys64/mingw32/bin/gcc.exe`
with `-static-libgcc`, producing a PE32 i386 binary that passes identically.
That is the constraint the whole KDF decision rested on, so it is checked
rather than assumed.

**Three things the implementation had to get right**, each recorded because
the default would have been wrong:

- **The body is the SCRAM message and nothing else.** `SrvrLogin`'s body pads
  each field to a two byte multiple with a NUL; the packet already carries its
  own length, so SCRAM adds nothing.
- **`server-first` is echoed into `AuthMessage` verbatim**, never rebuilt from
  the parsed parts. `scram_login()` parses a copy for exactly this reason.
- **A missing or wrong `v=` fails the connection.** Not a warning. It is the
  check that gets softened while debugging and never hardened again.

**The iteration count from the server is bounded, 4096 to 10,000,000.** A
server is not trusted to set the client's CPU cost, and a server asking for
almost none would weaken the derivation a captured exchange is judged against.

## The three locations, synchronised 19 Aug 2026

**The stale-32-bit-DLL blocker recorded here is resolved.** `winsdclilib` had
not moved since 15 Aug while this tree added `SDConnectLocal`, the transport
layer and SCRAM, and `sdclilib32` built from `winsdclilib` — so the
`qmclilib.dll` intended for mvDeveloper was being built from source with no
SCRAM in it, still sending the password in clear, and nothing in either project
would have said so.

| | Holds | Product |
| --- | --- | --- |
| `sd64/gplsrc/sdclilib` | **the source** | `sdclilib.dll`, 64-bit |
| `Projects/winsdclilib` | a mirror, `master` `e35376a` | `sdclilib.dll`, 64-bit |
| `Projects/sdclilib32` | no source; `SRCDIR` points here | `qmclilib.dll`, **32-bit** |

`sdclilib32`'s `SRCDIR` was repointed from `../winsdclilib` to this tree, so
there is now **one hop, not two** — the middle copy can no longer lag. The
seven shared files are byte-identical across the two that hold source;
`gplsrc/sdclilib/VENDORING.md` has the full topology, the sync commands and
what stays 32-bit-specific.

**Verified after the sync:** `make check` green in `winsdclilib` (smoke,
internal state) and in `sdclilib32` (smoke, internal state, **QM alias**), by
both the Makefile and `build.cmd` routes; `qmclilib.dll` is PE32 i386 and
depends only on `bcrypt`, `KERNEL32`, `msvcrt` and `WS2_32` — all Windows, so
it is still a single file that can be copied next to an application.

**`make check` earned its keep**: `internal_state_test.c` includes
`sdclilib.c` directly, so it needed `-lbcrypt` too. That was missing in all
three Makefiles and both `build.cmd`s, and only the test link failed — the DLL
itself had been fine.

`sdclilib32` is still not a git repository.

## Phase 5, the next task

Retire `SrvrLogin`. **This is the point of no return for old clients**, and it
is deliberately concentrated here so it happens once, knowingly.

- `APISRVR`: `vb.login` goes, and request 24 refuses rather than falling
  through. `vb.local.login` (25) stays — `SDConnectLocal` sends no password.
- The `deffun valid_os_name` was already moved to the top of the program for
  this, so deleting `vb.login` cannot take it with it.
- `verify-apiport.ps1`'s packet check asserts request 24 is never sent by this
  client, so it should keep passing across the change.
- `verify-scramlogin.ps1`'s "request 24 still accepted" check is the one that
  must be **inverted** at that point, not deleted: it becomes the proof the
  old path is gone.

## Which login the client speaks is measured, not argued

**`verify-apiport.ps1 -Prefix sdapi2`, 21:58:11 install: all checks passed.**
A successful login does **not** on its own prove the client spoke SCRAM — the
server still serves request 24, so a client that had fallen back would be
admitted just as readily and every other check would still be green. Source
says it cannot, `sdclilib.c` having no `SrvrLogin` call left and no
`login_data` at all, but that is an argument. This is the reading:

```
request types sent: 1, 2, 3, 21, 47, 48
   client sent SCRAM client-first (47)      PASS
   client sent SCRAM client-final (48)      PASS
   client sent NO cleartext login (24)      PASS
   password absent from the bytes sent      PASS   963 bytes reassembled
   same search finds the user name          PASS   <- the control
```

It works off the client's own `SDDebug(1)` log, enabled by `SD_CLIENT_DEBUG`
in `tests/remote_connect_test.c`. **The password search reassembles the byte
stream from the hex columns first**, because `debug()` dumps 16 bytes per line
and a 20 character password splits across two of them — a plain text search of
the log would have passed whether or not the password had been sent. The user
name is sent in clear, in `n=`, so finding it proves the search can find
something.

`sdapi1` and `sdapi2` are both spent; use a fresh prefix.

## The 32-bit project is still unversioned

`C:\Users\dmont\Projects\sdclilib32` builds the 32-bit `qmclilib.dll` that
mvDeveloper will use. **It is not a git repository** — worth fixing, and more
so now: it is the only one of the three whose state nothing records, so the
19 Aug sync of it exists on disk and nowhere else. Its `SRCDIR`, `-lbcrypt`
and README changes cannot be reviewed, reverted or seen from another machine.

**The claim this section used to make — "`winsdclilib` is untouched by the
SCRAM work and its tree is clean" — was true and was the problem.** See the
topology section above.
