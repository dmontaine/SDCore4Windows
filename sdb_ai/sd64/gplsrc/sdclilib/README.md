# sdclilib for Windows (MinGW GCC)

This project builds a native Windows DLL for remote access to a ScarletDME
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

`SDConnectLocal`/Unix-domain-socket connection is Linux-specific and is not
part of this Windows DLL. Use `SDConnect` for remote TCP connections.

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
