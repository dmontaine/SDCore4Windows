# SCRAM work — handoff, 20 Aug 2026

Design and rationale are in [SCRAM_AUTH.md](SCRAM_AUTH.md); this is the
operational half — what is built, what is deployed, and what to do next.

## Where it stands

**PHASES 1 TO 5 ARE COMPLETE AND VERIFIED. PHASE 6 IS ALL BUT DONE.**

**The cleartext login is gone.** Request 24 reaches a `vb.login` that refuses
with message 5275 and drops the connection; `!CRED_VERIFY` stays for
`SET_ACC_PASSWORD` and is no longer on any login path. The point of no return
has been passed, on purpose, once.

**THREE CLIENTS WERE MEASURED AGAINST THE PHASE 5 SERVER, not one** — the
.NET client inside `verify-scramlogin.ps1`, `sdclilib.dll` through
`remote_connect_test`, and the `!sdclient` BASIC class through `TESTSDCLI`.
Three independent implementations agreeing with one server is what makes
"SCRAM works" a measurement rather than one implementation agreeing with
itself.

| Phase | | Verified by |
| --- | --- | --- |
| 1 | Crypto primitives, C and the `SDEXT` bridge | `gplbld/verify-scram.c` in C; `sdsys/bp/TESTSCRAM` through BASIC |
| 2 | `$CRED` version 2, `!CRED_SET`, `!CRED_VERIFY`, `SET.PASSWORD` | `sdsys/bp/TESTCRED` |
| 3 | Server exchange, request types 47 and 48 in `APISRVR` | `gplbld/verify-scramlogin.ps1` — **24/24**, 21:03:41 install, 19 Aug 2026 |
| 4 | Client exchange in `sdclilib.c` | `gplbld/verify-scramclient.c` **27/27**, 64- and 32-bit; `gplbld/verify-apiport.ps1` end to end, 21:43:02 install |
| 5 | Retire `SrvrLogin`; SCRAM in the `!sdclient` class | `gplbld/verify-scramlogin.ps1` — **40/40**, 07:52:25 install, 20 Aug 2026 |
| 6 | Rebuild both DLLs, re-set passwords, test against mvDeveloper | mvDeveloper passed 19 Aug; the DLLs and the re-set are what remain |

## Phase 5, what was done and what it cost

**`vb.login` REFUSES RATHER THAN BEING DELETED, and 24 stays in the
pre-authentication gate.** Dropping 24 from that gate would answer an old
client with 5270 *"Not logged in"*, which is true and useless. It gets 5275
instead — *"Cleartext login is no longer supported; this server requires SCRAM
authentication"* — and the verifier asserts that text, not merely a non-zero
status.

**THE THING THE DESIGN DOCUMENTS MISSED: `sdsys/GPL.BP/SDCLIENT`.** The
`!sdclient` class module is the BASIC-callable half of the API — what
`sdclilib.dll` is to an application outside SD, this is to a program inside
it — and it sent request 24 at line 282. It is catalogued in `gcat` on every
install, has no caller anywhere in this tree and no test, so retiring 24 would
have broken it silently. Owner's decision, 20 Aug 2026: give it SCRAM.

**It is NOT the removed qmnet.** That distinction is what makes the decision
obvious rather than arguable: qmnet was `net_open()` in C, port 4245,
`server;file` VOC references, credentials in `sd.conf` under a substitution
cipher, removed 18 Aug (`op_dio1.c:627`). `!sdclient` opens **4243**, the API
port, and the 18 Aug note keeps qmclient explicitly.

**THE CLASS IS `$internal` NOW, and that is a privilege on the class and not
on its callers.** SCRAM needs `SDEXT`, which BCOMP admits only to a program
compiled `$internal` (`BCOMP:3777`, `int.intrinsics`). `TESTSDCLI` is
deliberately **not** `$internal` and drives the class anyway, which is what
demonstrates the flag stays inside. The class calls no `KERNEL` function and
runs nothing locally — `execute()` and `call()` send their argument to the
remote server — so there is no method through which a caller could borrow it.
Recompiling `SDCLIENT` now needs `sd -internal` from an elevated window.

**THE TWO MESSAGE GAPS THIS FILE RECORDED ARE CLOSED.** `verify-scramlogin.ps1`
now asserts the *text* of every refusal against the installed `messages`
record, so a refusal that fires on the wrong branch fails instead of passing:
5017 for a wrong password and for an unknown account, 5272 for replay, a
tampered nonce, `y,,` and `m=`, 5273 for 48-without-47, 5275 for request 24.

**AND 5274 IS EXERCISED, by breaking the server on purpose.** `$cred` is
renamed for one client-first and renamed back in a `finally`, with a second
attempt in the outer `finally` — a run that ended with the credential store
renamed would refuse every login on the machine. It is the only check here
that needs the server to be faulty, and it is what distinguishes "the
credential store will not open" from "your password is wrong".

## Phase 3, and how to re-run it

**`verify-scramlogin.ps1` is 40/40 on the 07:52:25 install of 20 Aug 2026**,
and it covers phases 3 and 5 together. It has two modes, and the offline one is
the first thing to reach for.

```powershell
gplbld\verify-scramlogin.ps1 -SelfTest             UNELEVATED, no server, no install
gplbld\verify-scramlogin.ps1 -Prefix sdscram3      ELEVATED, fresh prefix each run
```

`-SelfTest` checks the script's own client-side derivation against the RFC 7677
vectors — the same `New-ScramProof` the live checks use, not a copy. Run it
first whenever the exchange fails and it is not obvious which side is wrong: if
it passes, the instrument is sound and the disagreement is SD's.

**The live run needs a `-Prefix` nobody has used**, `sdscram1` and `sdscram2`
are spent, and it
changes the installed system and puts it back in a `finally` — throwaway
account, `APIPORT` in `sd.conf`, two service restarts. It leaves the
`ACCOUNTS` and `$CRED` records for `DELETE.ACCOUNT` on purpose, so a
half-failed `CREATE.ACCOUNT` cannot hide.

**What to look at first if it fails.** `47 accepted` failing means the handler
did not run or `$cred` did not open; `48 accepted` failing with `47` green
means the AuthMessage the two sides assembled differ, and the string to
suspect is `server-first` — `scram.sfirst` is stored verbatim on purpose, so a
mismatch means the client rebuilt it rather than echoing it.

**Both gaps this section recorded are closed, 20 Aug 2026.** Every refusal now
asserts its message *text* against the installed `messages` record, and `5274`
is exercised by renaming `$cred` for one client-first. See the top of this file.

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

**`sdclilib32` IS A GIT REPOSITORY FROM 20 AUG 2026** —
`github.com/dmontaine/sdclilib32`, initial import `cf5a72a`, 12 files and no
binaries. Until then it had been built from since 15 Aug and versioned
nowhere, so every sync of it existed on disk alone.

## mvDeveloper authenticates with SCRAM — 19 Aug 2026, and this is phase 6's real test

**The 32-bit editor connected over SCRAM-SHA-256 and worked.** Read out of its
own packet log, which is the first time anything has seen the shipping client's
traffic:

```
OUT Type 47   n,,n=don,r=03buwFTPAkGwrFtQta1YtCQl
IN            r=03buwFTPAkGwrFtQta1YtCQlYifnrKvGOHvoTKQU8GwbodPv,
              s=LoeIdB1sUfL+EwQzvg3kCQ==,i=600000
OUT Type 48   c=biws,r=<combined>,p=5OMM2PJ6suvAIs/mtV2ZsOa6T0PpLL7N9lk0KiDpSJ4=
IN            v=DZZsq8z7HXBARLatE5KU4MvsVOOUoSSqcclWq5gt4z0=
OUT Type 3    don                        <- account attach, accepted
OUT Type 21   SSELECT VOC WITH ...       <- and then it just worked
```

**Request 24 never appears.** The password is not in the 1,005 bytes the
session exchanged. `i=600000`, so the credential is at full cost. The `v=`
came back and the client accepted it, which is the mutual half working against
a real client rather than against a test.

**What actually fixed it is not certain, and saying so is better than
inventing a cause.** Between the failing attempt and this one, two things
changed: the editor was restarted, and `SET.PASSWORD` had been run. The DLL
was replaced too, but only with one that adds logging, so it cannot be the
cause. The likeliest reading is that the failing attempt was made before the
credential existed — the port had only just been re-enabled — and that a
restart was needed. **`QMConnect` returning a generic "connection error" is
what made this expensive**; the packet log is the fix for that, and it is now
one environment variable away.

## Phase 5 as it was planned, and where the plan was wrong

Kept because four of its five bullets held and the fifth is the finding.

- `APISRVR`: `vb.login` refuses; **it did not "go"**, and 24 stays in the
  pre-authentication gate — see the top of this file for why the reply is 5275
  and not 5270. `vb.local.login` (25) stays untouched: `SDConnectLocal` sends
  no password. ✓
- The `deffun valid_os_name` had already been moved to the top of the program
  for this. ✓
- `verify-apiport.ps1` kept passing across the change, exactly as predicted —
  `sdapi3`, 07:52:25 install, all checks. Its comment now says the check
  survives as an assertion about the *client*, since the silent-fallback case
  it was written for cannot happen any more. ✓
- `verify-scramlogin.ps1`'s "request 24 still accepted" was **inverted, not
  deleted**, and now asserts the 5275 text as well. ✓
- **THE PLAN LISTED ONE CLIENT AND THERE WERE TWO.** `!sdclient` is not
  mentioned anywhere in these documents and would have broken silently. That
  is the lesson worth carrying: *grep the tree for the request number, not for
  the client you have in mind*. `grep -rn "SrvrLogin"` finds all four places —
  `sdclilib.c`, `SDCLIENT`, `verify-scramlogin.ps1`, and `gplsrc/sdclient.c`.

**`gplsrc/sdclient.c` IS THE FOURTH AND IT IS DEAD.** It still builds a
cleartext request 24 at line 609. `Makefile:66` removes it from `SRCS`
(`$(TEMPSRCS:sdclient.c=)`), it is not in `gpl.src`, and no target depends on
`sdclient.o` — the rule at `Makefile:214` is an orphan. So nothing links it and
phase 5 does not break it. **Left alone deliberately**: deleting source is its
own decision and was not in scope. If it is ever revived it needs the exchange
from `sdclilib.c`.

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

## The 32-bit project is versioned now — 20 Aug 2026

`C:\Users\dmont\Projects\sdclilib32` builds the 32-bit `qmclilib.dll` that
mvDeveloper uses, and `qmclient.dll` beside it. **It is a git repository from
20 Aug 2026**, `github.com/dmontaine/sdclilib32`, initial import `cf5a72a`.

This section used to say it was the only one of the three whose state nothing
recorded, so every sync of it existed on disk and nowhere else and its
`SRCDIR`, `-lbcrypt` and README changes could not be reviewed, reverted or seen
from another machine. That is closed.

**The import is 12 files and no binaries**, checked against the remote tree.
`qmclient.def` is excluded with the build products: it is generated from
`qmclilib.def`, and committing it would create the second hand-kept copy of a
99-name export list that generating it exists to prevent.

**The claim this section used to make — "`winsdclilib` is untouched by the
SCRAM work and its tree is clean" — was true and was the problem.** See the
topology section above.
