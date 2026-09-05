# sdclilib for Windows (MinGW GCC)

This project builds a native Windows DLL for remote access to an SD
server. It combines the complete, platform-neutral client behavior from the
Linux library with the Winsock transport from the existing Visual Studio port.

See [USER_GUIDE.md](USER_GUIDE.md) for application linking, deployment,
connection examples, memory ownership, error handling, and the complete API
overview.

## Requirements

- 64-bit MinGW GCC (the installed MSYS2 UCRT64 GCC is supported)
- GNU Make (`mingw32-make`, `make`, or `C:\msys64\usr\bin\make.exe`)

> **Build provenance:** The prebuilt Windows DLL and import library included
> with this repository were compiled using the GCC toolchain provided by the
> MSYS2 application, specifically the UCRT64 compiler at
> `C:\msys64\ucrt64\bin\gcc.exe`.

## Build

From a Windows command prompt or PowerShell (recommended on this machine):

```bat
build.cmd
```

From an MSYS2 UCRT64 shell with Make installed:

```sh
make
make check
```

From PowerShell without Make:

```powershell
C:\msys64\ucrt64\bin\gcc.exe -O2 -std=c11 -DBUILDING_SDCLILIB `
  -shared -o sdclilib.dll sdclilib.c -lws2_32 `
  -Wl,--out-implib,libsdclilib.dll.a
```

Outputs:

- `sdclilib.dll` - runtime DLL
- `libsdclilib.dll.a` - GCC/MinGW import library
- `sdclilib.h` - public C/C++ API
- `sdclilib.bi` - complete FreeBASIC declarations

Client programs link with `-L. -lsdclilib` and must be able to find
`sdclilib.dll` at runtime.

`SDConnectLocal` **is** part of this DLL and is exported. It connects to SD on
the same machine over a Windows **named pipe**, starting an `sd.exe` for the
session; there is no network and no password, because the server identifies you
from the process owner. Corrected 17 Aug 2026 — this file previously called it
"Linux-specific and not part of this Windows DLL", which was wrong on both
counts.

***BUT IT WORKS ONLY FROM A DIRECTORY THAT ALSO HOLDS `sd.exe`, WHICH MEANS
`usr\bin` AND NOWHERE ELSE.*** Added 4 Sep 2026, PRE_RELEASE_FIXES 163. The
function finds the server by taking **its own module path** and appending
`\sd.exe`, so the copy in `C:\Program Files\SD\usr\bin` — which sits beside the
server — can start a session, and a copy taken from
`C:\Program Files\SD\usr\clients\client64` to an application's directory or to
`windows\system32` **cannot**. Everything else in the library works from a
copied DLL; this one call does not.

**That is not a limitation in practice.** A Windows application talks to SD
over the API — `SDConnect` to `127.0.0.1` when the server is on the same
machine — which is the supported route and the one the documentation describes.
The 32-bit DLLs have never provided a local connection at all: `QMConnectLocal`
is exported as a stub that always fails.

`gplbld/verify-localconnect.ps1` is the standing test of this path, and of the
grant check that decides it. It runs in `VerifyInstall1`, unelevated, because
the identity being checked is the process owner's.

`SDConnectUDS` is the Unix-domain-socket entry point and is genuinely not here.

Use `SDConnect` for servers on another computer.

The smoke test exercises local string functions without requiring a server.

## Windows port behavior

- Record writes larger than `MAX_STRING_SIZE` are rejected locally with
  `ER_MAX_STRING` before a packet is sent.
- The Windows library supports TCP through Winsock only; Linux local-process,
  pipe, and Unix-domain-socket transport paths are not included.
- `SV_ERROR` identifies a request that reached the server but failed there.
  When the follow-up error-text exchange succeeds, the original operation
  remains `SV_ERROR` without being reported as a messaging failure.
- `SV_ECONTXT` identifies a client call made in the wrong session context, and
  `SV_EMSG_PAIR` identifies failure to complete the request/response exchange.

## License

Licensed under the GNU Lesser General Public License, version 3 or later
(LGPL-3.0-or-later). See [LICENSE](LICENSE) for the full LGPLv3 text.

LGPLv3 incorporates the terms of the GNU General Public License version 3 by
reference; the full GPLv3 text is included as [GPLv3.txt](GPLv3.txt).
