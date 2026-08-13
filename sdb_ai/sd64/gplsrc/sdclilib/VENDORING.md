# Vendoring notes

This directory is a vendored copy of the standalone client library project,
plus local additions listed below.

- Upstream: `github.com/dmontaine/winsdclilib`
- Imported commit: `b6624565cacb365d0a2788545495a7fa3ba3f743` (5 Aug 2026)
- Imported: 13 Aug 2026

It replaces the former `gplsrc/sdclilib.c`, which was the Linux client library.

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

When syncing from upstream, re-apply these; they are confined to the sections
marked in the source and do not alter upstream's protocol handling.
