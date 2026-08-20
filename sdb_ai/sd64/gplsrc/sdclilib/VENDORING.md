# Vendoring notes

**THIS DIRECTORY IS THE SOURCE OF TRUTH FOR THE CLIENT LIBRARY, AS OF
19 Aug 2026. It used to be the copy; the arrow has turned round.**

It began as a vendored copy of `github.com/dmontaine/winsdclilib`, imported at
commit `b6624565cacb365d0a2788545495a7fa3ba3f743` (5 Aug 2026) on 13 Aug 2026,
replacing the former `gplsrc/sdclilib.c` which was the Linux client library.
It then moved a long way ahead of it — `SDConnectLocal()`, `sysdir()`, the
socket-or-pipe transport layer, and SCRAM-SHA-256 — while upstream stood still.

## The three locations, and which way things flow

| | Holds | Built product |
| --- | --- | --- |
| **`sd64/gplsrc/sdclilib`** (here) | the source | `sdclilib.dll`, 64-bit |
| `Projects/winsdclilib` | a mirror of the source | `sdclilib.dll` **and `sdclient.dll`**, 64-bit |
| `Projects/sdclilib32` | no source at all | `qmclilib.dll` **and `qmclient.dll`**, **32-bit** |

**THE SECOND NAME IN EACH IS THE SAME LIBRARY, NOT A VARIANT — 20 Aug 2026.**
Owner's decision: each client project builds its DLL twice, under the name it
has always produced and under the name its installer ships. `sdclilib.dll` and
`qmclilib.dll` are what existing applications ask for and neither moves;
`sdclient.dll` and `qmclient.dll` are for new work.

**They are second LINKS, not copies of the file**, because an import library
records the name of the DLL its symbols come from — a renamed copy hands out an
implib pointing back at the original. In the 32-bit project the `.def` carries
a `LIBRARY` statement that sets that name too, so `qmclient.def` is generated
from `qmclilib.def` by rewriting one line rather than being a second copy of a
99-name export list. Both projects' `make check` now run a test through each
import library, which is the only thing that catches either mistake.

**THIS TREE STILL BUILDS ONE DLL AND THAT IS DELIBERATE.** `make sd` here
produces `sdclilib.dll` for the server's own use — `make check-local` and
anything beside `sd.exe`. The second name exists for distribution, and
distribution is what the two client projects are for.

**AND THEY NOW HAVE INSTALLERS**: `winsdclilib/sdclient.iss` and
`sdclilib32/qmclient.iss`, both packaging an already-built tree exactly as
`gplbld/sd.iss` does. Until 20 Aug 2026 the only way to obtain the client
library was to find it inside an installed SD server, which is the wrong shape
for a client — it exists to run on a machine that is not the server.

**Edits are made here.** `winsdclilib` takes them; it is a mirror, not a
fork, and nothing should be changed there that is not changed here first.
`sdclilib32` holds no copy of the source at all — its `Makefile` sets
`SRCDIR ?= ../sd4windows/sdb_ai/sd64/gplsrc/sdclilib` and builds from these
files directly.

**`sdclilib32` was repointed here on 19 Aug 2026, and the reason is worth
keeping.** It used to build from `../winsdclilib`, which had not moved since
15 Aug — so the 32-bit `qmclilib.dll` that ships with mvDeveloper was being
built from source with no SCRAM in it, still sending the password in clear,
and **nothing in that project would have reported it**. Two hops meant the
middle one could lag silently; one hop cannot. It is the failure its own
Makefile comment had predicted in the abstract.

**What is genuinely 32-bit-specific stays in `sdclilib32`**: `qmcompat.c`, the
`qmclilib.def` export table that produces the QM-named aliases, `qmclilib.h`,
`-static-libgcc`, and the pinned `i686` compiler with the `ARCH` guard that
refuses to build a 64-bit DLL under a 32-bit name.

**Nothing binary is tracked in any of the three.** All three `.gitignore`
build products, so "the same version" means each builds a current DLL from the
same source, not that a DLL is committed anywhere.

## Keeping them in step

```sh
# from Projects/
cp sd4windows/sdb_ai/sd64/gplsrc/sdclilib/{sdclilib.c,scram_client.h,sdclilib.h,sdclient.h,err.h,revstamp.h,sdclilib.bi} winsdclilib/
cp sd4windows/sdb_ai/sd64/gplsrc/sdclilib/tests/{smoke_test.c,internal_state_test.c} winsdclilib/tests/
```

`local_connect_test.c`, `remote_connect_test.c` and the probe programs stay
here: they need an installed SD, the API port, or `gplbld`'s harness, none of
which the standalone project has.

**Then build and check all three** — `make check` in `winsdclilib` and in
`sdclilib32`, and `make sdclilib` from `sd64`. The 32-bit one is the one that
matters: it is a shipping deliverable, not a test convenience.

## Why it lives in its own directory

Its `sdclient.h`, `err.h` and `revstamp.h` are not the same files as the ones
in `gplsrc`. `revstamp.h` in particular feeds `MAJOR_REV`/`MINOR_REV`/`BUILD`
into `SYSSEG_REVSTAMP` in `sysseg.c`, which stamps the shared memory segment,
so the server's copy must not be displaced by this one. Keeping the library
self-contained avoids the collision and keeps upstream syncs simple.

## Toolchain

Built with the UCRT64 compiler (`C:\msys64\ucrt64\bin\gcc.exe`), not the MSYS2
runtime compiler used for the server. The result is a native Win32 DLL with no
dependency on `msys-2.0.dll`.

The differing runtimes never meet: a client links this DLL and reaches the
server over a socket or a named pipe, so the two are always separate processes.

Built from `sd64` with `make sdclilib`, or directly here with `make` and
`make check`. Override the compiler with `UCRT_CC=...`.

## Local additions

`SDConnectLocal()` was absent upstream, because that project targets a Windows
client connecting to a remote Linux server, where a local connection has no
meaning. Now that the server runs on Windows it does, and the function is part
of the published API that `examples/python/python_api_test/sdclilibwrap.py`
binds, so it was added back:

- `SDConnectLocal()`, modelled on the implementation in `gplsrc/sdclient.c`:
  create a named pipe, start `sd.exe -Q -C <pipe>` with `CreateProcess`, wait
  with `ConnectNamedPipe`, then `SrvrLocalLogin` and `SrvrAccount`.
- `sysdir()`, which reads `SDSYS=` from the `[sd]` section of the file named by
  `SD_CONFIG`, or of `sd.ini` in the Windows directory.
- A transport layer (`transport_recv`, `transport_send`, `transport_live`,
  `transport_error`) so `read_packet()` and `write_packet()` work over either a
  socket or a pipe. Upstream's error handling and connection abandonment are
  unchanged; only the byte moving is dispatched.
- `hPipe` and `is_local` on the session, closed by `CloseSocket()`.

Two differences from the `sdclient.c` original, both deliberate:

- `ConnectNamedPipe()` returning `ERROR_PIPE_CONNECTED` is treated as success.
  It means the child connected before we called, which is not a failure.
- The process handle from `CreateProcess` is closed as well as the thread
  handle. The original closed only the thread handle and leaked the other.

**These no longer need re-applying after a sync.** That instruction belonged to
the arrangement where this directory was the copy; since 19 Aug 2026 the flow
is outwards, so they are simply part of the source and `winsdclilib` receives
them. Kept here because they still record *why* the additions exist and how
they differ from the `gplsrc/sdclient.c` original they were modelled on.
