# SD Client DLL for Windows

## 1. Overview

`sdclilib.dll` is a 64-bit native Windows C library for accessing a
ScarletDME database server over TCP. It provides the same remote client API as
the Linux SD client library, including file operations, record locking,
select lists, command execution, catalogued subroutine calls, dynamic-array
operations, and multiple sessions.

`SDConnectLocal` connects to SD on this machine and **is** provided. It creates
a Windows named pipe, starts an `sd.exe` attached to it, and speaks the same
protocol over it; no password is sent, because the server takes your identity
from the process owner. Corrected 17 Aug 2026 — this guide previously said the
Windows DLL did not provide it and that it depended on Linux facilities.
Neither was true: the transport is a named pipe, which has no Linux equivalent
in this library at all.

`SDConnectUDS` is not provided; it needs a Unix-domain socket.

Use `SDConnect` for servers running on another computer.

The library is **not thread-safe**: call it from a single thread or serialize
all calls yourself. See [Threading](#threading) under Connection and session
lifecycle for details.

## 2. Distributed files

| File | Purpose |
|---|---|
| `sdclilib.dll` | Runtime DLL |
| `libsdclilib.dll.a` | MinGW/GCC import library |
| `sdclilib.h` | Public C and C++ declarations |
| `build.cmd` | Windows build and smoke-test script |
| `Makefile` | Alternative GNU Make build |

Applications need `sdclilib.h` when compiling, `libsdclilib.dll.a` when
linking, and `sdclilib.dll` when running.

## 3. Building the DLL

Open Command Prompt or PowerShell and run:

```bat
cd C:\Users\Don\sdclilib\gccsdclilib
build.cmd
```

The script uses `C:\msys64\ucrt64\bin\gcc.exe` when present and otherwise uses
`gcc` from `PATH`. It builds the DLL and import library, builds the smoke test,
and runs the test.

## 4. Building an application

Given an application named `example.c`:

```bat
C:\msys64\ucrt64\bin\gcc.exe -O2 -o example.exe example.c ^
  -IC:\Users\Don\sdclilib\gccsdclilib ^
  -LC:\Users\Don\sdclilib\gccsdclilib -lsdclilib
```

At runtime, put `sdclilib.dll` in one of these locations:

1. The same directory as the application executable.
2. A directory in the process's `PATH`.
3. A directory explicitly added using the Windows DLL search APIs.

The header includes `extern "C"` protection and can therefore also be included
from C++.

## 5. Complete connection example

```c
#include <stdio.h>
#include "sdclilib.h"

int main(void) {
    int file_no;
    int err;
    char *record;

    if (!SDConnect("localhost", 4242, "username", "password", "ACCOUNT")) {
        fprintf(stderr, "Connection failed: %s\n", SDError());
        return 1;
    }

    file_no = SDOpen("CUSTOMERS");
    if (file_no == 0) {
        fprintf(stderr, "Open failed; STATUS()=%d, error=%s\n",
                SDStatus(), SDError());
        SDDisconnect();
        return 1;
    }

    record = SDRead(file_no, "1001", &err);
    if (record != NULL) {
        printf("Record: %s\n", record);
        SDFree(record);
    } else {
        fprintf(stderr, "Read failed; server result=%d, STATUS()=%d\n",
                err, SDStatus());
    }

    SDClose(file_no);
    SDDisconnect();
    return 0;
}
```

Replace port `4242` with the port configured for the SD client server.
Windows applications can normally reach a TCP service running in WSL through
`localhost`, provided the SD service is listening on an accessible TCP port.

## 6. Connection and session lifecycle

### Opening a connection

```c
int ok = SDConnect(host, port, username, password, account);
```

The return value is nonzero for success and zero for failure. On failure,
call `SDError()` for descriptive client error text.

Usernames and passwords are limited to 32 bytes by the current protocol
implementation.

### Checking and closing

```c
if (SDConnected()) {
    SDDisconnect();
}
```

`SDDisconnect()` closes the current session. `SDDisconnectAll()` closes every
active session.

### Multiple sessions

The library supports up to four simultaneous sessions. `SDConnect` selects the
new session automatically.

```c
int first;
int second;

SDConnect("server1", 4242, "user", "password", "ACCOUNT1");
first = SDGetSession();

SDConnect("server2", 4242, "user", "password", "ACCOUNT2");
second = SDGetSession();

SDSetSession(first);
/* Operations now use server1. */

SDSetSession(second);
/* Operations now use server2. */
```

`SDSetSession` returns nonzero only when the requested session exists and is
connected.

### Threading

**The library is not thread-safe. Call it from a single thread, or serialize
all calls with your own lock.**

Although up to four sessions can be open at once, "session" here means a
selectable connection, not a thread. Key state is process-global and shared
across every session and thread:

- the current session index set by `SDConnect` / `SDSetSession`,
- the single network transfer buffer used to build and receive every packet,
- the `SDCallx` return-argument store read back by `SDGetArg`,
- the scratch state used by `SDMatch` / `SDMatchfield`.

Two threads calling into the DLL at the same time — even on different sessions —
will corrupt one another's buffer, current-session selection, and returned
data. If you need concurrency, wrap every `SD…` call in a single
application-level mutex, or confine all use to one thread.

## 7. Memory ownership

Many functions return a newly allocated string. Release such strings with
`SDFree`; do not use the application's `free()`:

```c
char *value = SDExtract(record, 1, 0, 0);
if (value != NULL) {
    puts(value);
    SDFree(value);
}
```

Functions returning allocated strings include:

- `SDChange`, `SDDel`, `SDExtract`, `SDField`, `SDIns`, and `SDReplace`
- `SDExecute` and `SDRespond`
- `SDGetArg`
- `SDMatchfield`
- `SDRead`, `SDReadl`, `SDReadu`, `SDReadList`, and `SDReadNext`
- `SDSelectLeft` and `SDSelectRight`

`SDError()` returns library-owned storage and must not be freed.

## 8. Errors and status

There are three related result mechanisms:

- Function return values indicate immediate success, failure, or returned data.
- Output parameters such as `err` return the server result code.
- `SDStatus()` returns the database `STATUS()` value for the current session.
- `SDError()` returns extended client or abort text.

Server result constants are declared in `sdclilib.h`:

| Constant | Value | Meaning |
|---|---:|---|
| `SV_OK` | 0 | Operation succeeded |
| `SV_ON_ERROR` | 1 | An `ON ERROR` condition occurred |
| `SV_ELSE` | 2 | An `ELSE` condition occurred |
| `SV_ERROR` | 3 | Operation failed; error text may be available |
| `SV_LOCKED` | 4 | A lock prevented the operation |
| `SV_PROMPT` | 5 | The server is waiting for command input |
| `SV_ECONTXT` | 6 | A client function was called in the wrong session context |
| `SV_EMSG_PAIR` | 7 | The client could not complete the request/response exchange |

Check the function's direct result first, then inspect its output error,
`SDStatus()`, or `SDError()` as appropriate.

## 9. File and record operations

Open and close a database file:

```c
int fno = SDOpen("CUSTOMERS");
if (fno != 0) {
    /* Use the file. */
    SDClose(fno);
}
```

Read a record:

```c
int err;
char *record = SDRead(fno, "1001", &err);
if (record != NULL) {
    /* Use record. */
    SDFree(record);
}
```

Locking reads:

```c
char *shared = SDReadl(fno, "1001", 1, &err);
char *update = SDReadu(fno, "1001", 1, &err);
```

The `wait` argument is zero to return immediately or nonzero to wait for the
lock. Release an acquired record lock with:

```c
SDRelease(fno, "1001");
```

Write and delete:

```c
SDWrite(fno, "1001", record);
SDWriteu(fno, "1001", record); /* Retains the update lock. */
SDDelete(fno, "1001");
SDDeleteu(fno, "1001");        /* Retains the update lock. */
```

## 10. Select lists and indexes

```c
SDSelect(fno, 0);

for (;;) {
    char *id = SDReadNext(0);
    if (id == NULL || id[0] == '\0') {
        SDFree(id);
        break;
    }
    printf("%s\n", id);
    SDFree(id);
}

SDClearSelect(0);
```

Additional index operations are available through `SDSelectIndex`,
`SDSelectLeft`, `SDSelectRight`, `SDSetLeft`, and `SDSetRight`.

## 11. Dynamic arrays and strings

SD dynamic arrays use field, value, and subvalue positions. A zero position
means that the deeper level is not selected.

```c
char *field = SDExtract(record, 3, 0, 0);
char *value = SDExtract(record, 3, 2, 0);
char *subvalue = SDExtract(record, 3, 2, 1);

SDFree(field);
SDFree(value);
SDFree(subvalue);
```

The corresponding modification functions are:

- `SDReplace` — replace a field, value, or subvalue.
- `SDIns` — insert a field, value, or subvalue.
- `SDDel` — delete a field, value, or subvalue.
- `SDLocate` — locate an item and return its position.

General string functions are `SDChange`, `SDDcount`, `SDField`, `SDMatch`, and
`SDMatchfield`.

## 12. Executing commands

```c
int err;
char *reply = SDExecute("LIST CUSTOMERS", &err);

while (err == SV_PROMPT) {
    SDFree(reply);
    reply = SDRespond("response text", &err);
}

if (reply != NULL) {
    puts(reply);
    SDFree(reply);
}
```

If an executing command must be cancelled while waiting for a response, call
`SDEndCommand()`.

## 13. Calling catalogued subroutines

### `SDCall`

`SDCall` follows the original API and writes returned arguments into the
buffers supplied by the caller:

```c
char arg1[1024] = "input";
char arg2[1024] = "";

SDCall("MY.SUBROUTINE", 2, arg1, arg2);
printf("arg1=%s\narg2=%s\n", arg1, arg2);
```

Each caller buffer must be large enough for the value returned by the server.
The API cannot determine the buffer capacity.

### `SDCallx` and `SDGetArg`

`SDCallx` retains returned arguments internally. Retrieve each one using its
one-based argument number:

```c
char *arg1;
char *arg2;

SDCallx("MY.SUBROUTINE", 2, "input", "");

arg1 = SDGetArg(1);
arg2 = SDGetArg(2);

if (arg1 != NULL) {
    printf("arg1=%s\n", arg1);
    SDFree(arg1);
}
if (arg2 != NULL) {
    printf("arg2=%s\n", arg2);
    SDFree(arg2);
}
```

A later `SDCallx` replaces the previously retained argument values. The
retained argument area is shared across sessions.

## 14. Account and package operations

Use `SDLogto` to change the account for the current session:

```c
if (!SDLogto("OTHER.ACCOUNT")) {
    fprintf(stderr, "LOGTO failed; STATUS()=%d\n", SDStatus());
}
```

Licensed packages can be entered and exited with `SDEnterPackage` and
`SDExitPackage`.

## 15. Packet debugging

```c
SDDebug(1); /* Enable. */
/* Perform operations. */
SDDebug(0); /* Disable and close the log. */
```

By default, the implementation writes packet diagnostics to
`sdclilib.log` in the current user's Windows temporary directory. Set the
`SD_CLIENT_DEBUG` environment variable to an absolute file path to choose a
different location:

```bat
set SD_CLIENT_DEBUG=C:\logs\sdclilib.log
```

The application must have permission to create the selected file. If the file
cannot be opened, `SDError()` reports the failure. Debug logs may contain
database traffic and should be protected accordingly.

## 16. Using the DLL with FreeBASIC

FreeBASIC can link directly to the supplied MinGW import library. The
FreeBASIC compiler, import library, DLL, and application must all target the
same architecture. The supplied `sdclilib.dll` is 64-bit, so use a 64-bit
Windows FreeBASIC compiler. A 32-bit FreeBASIC application requires a separate
32-bit build of the DLL.

### FreeBASIC declarations

Create an include file named `sdclilib.bi` containing the declarations needed
by the application. The following subset supports connecting, opening and
reading a file, reporting errors, and disconnecting:

```freebasic
#Ifndef __SDCLILIB_BI__
#Define __SDCLILIB_BI__

' Requests libsdclilib.dll.a during the link step.
#Inclib "sdclilib"

Extern "C"
    Declare Function SDConnect Alias "SDConnect" ( _
        ByVal host As ZString Ptr, _
        ByVal port As Long, _
        ByVal username As ZString Ptr, _
        ByVal password As ZString Ptr, _
        ByVal account As ZString Ptr) As Long

    Declare Function SDConnected Alias "SDConnected" () As Long
    Declare Sub SDDisconnect Alias "SDDisconnect" ()

    Declare Function SDError Alias "SDError" () As ZString Ptr
    Declare Function SDStatus Alias "SDStatus" () As Long

    Declare Function SDOpen Alias "SDOpen" ( _
        ByVal filename As ZString Ptr) As Long
    Declare Sub SDClose Alias "SDClose" (ByVal fileNo As Long)

    Declare Function SDRead Alias "SDRead" ( _
        ByVal fileNo As Long, _
        ByVal recordId As ZString Ptr, _
        ByRef serverError As Long) As ZString Ptr

    Declare Sub SDFree Alias "SDFree" (ByVal p As Any Ptr)
End Extern

#EndIf
```

Important type mappings are:

| C type | FreeBASIC type |
|---|---|
| `int` / `int32_t` | `Long` |
| `int16_t` | `Short` |
| `char *` input | `ZString Ptr` |
| `char *` returned string | `ZString Ptr` |
| `void *` | `Any Ptr` |
| `int *` output parameter | `ByRef ... As Long` |

`Extern "C"` selects C-compatible linkage, and each `Alias` preserves the
exact mixed-case DLL export name.

### FreeBASIC connection and read example

Save the following as `sd_example.bas`:

```freebasic
#Include Once "sdclilib.bi"

Dim host As String = "localhost"
Dim username As String = "username"
Dim password As String = "password"
Dim account As String = "ACCOUNT"
Dim filename As String = "CUSTOMERS"
Dim recordId As String = "1001"

Dim fileNo As Long
Dim serverError As Long
Dim record As ZString Ptr

If SDConnect(StrPtr(host), 4242, StrPtr(username), _
             StrPtr(password), StrPtr(account)) = 0 Then
    Dim errorText As ZString Ptr = SDError()
    If errorText <> 0 Then
        Print "Connection failed: "; *errorText
    Else
        Print "Connection failed"
    End If
    End 1
End If

fileNo = SDOpen(StrPtr(filename))
If fileNo = 0 Then
    Print "Open failed; STATUS()="; SDStatus()
    SDDisconnect()
    End 1
End If

record = SDRead(fileNo, StrPtr(recordId), serverError)
If record <> 0 Then
    Print "Record: "; *record
    SDFree(record)
Else
    Print "Read failed; server result="; serverError
    Print "STATUS()="; SDStatus()
End If

SDClose(fileNo)
SDDisconnect()
```

`StrPtr` supplies a pointer to a FreeBASIC string's null-terminated character
data. Keep the corresponding `String` variable alive for the duration of the
DLL call.

Compile from a command prompt:

```bat
fbc sd_example.bas ^
  -i C:\Users\Don\sdclilib\gccsdclilib ^
  -p C:\Users\Don\sdclilib\gccsdclilib
```

The `-i` option adds the directory containing `sdclilib.bi`. The `-p` option
adds the directory containing `libsdclilib.dll.a`. Because the include file
uses `#Inclib "sdclilib"`, no additional `-l` option is needed. Alternatively,
remove `#Inclib` and add `-l sdclilib` to the compiler command.

Copy `sdclilib.dll` into the same directory as `sd_example.exe` before running
the program:

```bat
copy C:\Users\Don\sdclilib\gccsdclilib\sdclilib.dll .
sd_example.exe
```

### FreeBASIC memory handling

Do not convert an allocated return value to a FreeBASIC `String` and then lose
the original pointer. Save the pointer, copy or use its contents, and release
it with `SDFree`:

```freebasic
Dim p As ZString Ptr = SDRead(fileNo, StrPtr(recordId), serverError)
If p <> 0 Then
    Dim value As String = *p
    SDFree(p)
    Print value
End If
```

Do not call `SDFree` on the pointer returned by `SDError`; that storage belongs
to the DLL.

The full C API is available to FreeBASIC by declaring the remaining functions
from `sdclilib.h` with the same type mappings. Variadic functions such as
`SDCall` and `SDCallx` require `Cdecl` declarations and additional care with
argument buffers. For most FreeBASIC programs, a small fixed-signature C
wrapper around each required subroutine call is safer than invoking a
variadic function directly.

## 17. Function-by-function C and FreeBASIC reference

In C, include `sdclilib.h`. In FreeBASIC, include `sdclilib.bi`. Both include
files are supplied with the project and arrange linking to the same exported
DLL names. C declarations below omit the `SD_API` decoration for readability.
FreeBASIC declarations are inside the `extern "C"` block in `sdclilib.bi`.

For C input strings, pass `char *` values. For FreeBASIC input strings, pass
`StrPtr(stringVariable)` to `zstring ptr` parameters. A returned `char *` or
`zstring ptr` must normally be released with `SDFree`; the exception is
`SDError()`, which returns DLL-owned storage.

### Connections and sessions


<u><b>SDConnect</b></u>

<small><b>C:</b></small>

```c
int SDConnect(char *host, int port, char *username, char *password,
              char *account);
```

<small><b>FreeBASIC:</b></small>

```freebasic
declare function SDConnect(byval host as zstring ptr, byval port as long, _
    byval username as zstring ptr, byval password as zstring ptr, _
    byval account as zstring ptr) as long
```


<u><b>SDConnected</b></u>

<small><b>C:</b></small>

```c
int SDConnected(void);
```

<small><b>FreeBASIC:</b></small>

```freebasic
declare function SDConnected() as long
```


<u><b>SDDisconnect</b></u>

<small><b>C:</b></small>

```c
void SDDisconnect(void);
```

<small><b>FreeBASIC:</b></small>

```freebasic
declare sub SDDisconnect()
```


<u><b>SDDisconnectAll</b></u>

<small><b>C:</b></small>

```c
void SDDisconnectAll(void);
```

<small><b>FreeBASIC:</b></small>

```freebasic
declare sub SDDisconnectAll()
```


<u><b>SDGetSession</b></u>

<small><b>C:</b></small>

```c
int SDGetSession(void);
```

<small><b>FreeBASIC:</b></small>

```freebasic
declare function SDGetSession() as long
```


<u><b>SDSetSession</b></u>

<small><b>C:</b></small>

```c
int SDSetSession(int session);
```

<small><b>FreeBASIC:</b></small>

```freebasic
declare function SDSetSession(byval session as long) as long
```


<u><b>SDLogto</b></u>

<small><b>C:</b></small>

```c
int SDLogto(char *account_name);
```

<small><b>FreeBASIC:</b></small>

```freebasic
declare function SDLogto(byval account_name as zstring ptr) as long
```

### File and record operations


<u><b>SDOpen</b></u>

<small><b>C:</b></small>

```c
int SDOpen(char *filename);
```

<small><b>FreeBASIC:</b></small>

```freebasic
declare function SDOpen(byval filename as zstring ptr) as long
```


<u><b>SDClose</b></u>

<small><b>C:</b></small>

```c
void SDClose(int fno);
```

<small><b>FreeBASIC:</b></small>

```freebasic
declare sub SDClose(byval fno as long)
```


<u><b>SDRead</b></u>

<small><b>C:</b></small>

```c
char *SDRead(int fno, char *id, int *err);
```

<small><b>FreeBASIC:</b></small>

```freebasic
declare function SDRead(byval fno as long, byval id as zstring ptr, _
    byref err as long) as zstring ptr
```


<u><b>SDReadl</b></u>

<small><b>C:</b></small>

```c
char *SDReadl(int fno, char *id, int wait, int *err);
```

<small><b>FreeBASIC:</b></small>

```freebasic
declare function SDReadl(byval fno as long, byval id as zstring ptr, _
    byval wait_ as long, byref err as long) as zstring ptr
```


<u><b>SDReadu</b></u>

<small><b>C:</b></small>

```c
char *SDReadu(int fno, char *id, int wait, int *err);
```

<small><b>FreeBASIC:</b></small>

```freebasic
declare function SDReadu(byval fno as long, byval id as zstring ptr, _
    byval wait_ as long, byref err as long) as zstring ptr
```


<u><b>SDWrite</b></u>

<small><b>C:</b></small>

```c
void SDWrite(int fno, char *id, char *data);
```

<small><b>FreeBASIC:</b></small>

```freebasic
declare sub SDWrite(byval fno as long, byval id as zstring ptr, _
    byval data_ as zstring ptr)
```


<u><b>SDWriteu</b></u>

<small><b>C:</b></small>

```c
void SDWriteu(int fno, char *id, char *data);
```

<small><b>FreeBASIC:</b></small>

```freebasic
declare sub SDWriteu(byval fno as long, byval id as zstring ptr, _
    byval data_ as zstring ptr)
```


<u><b>SDDelete</b></u>

<small><b>C:</b></small>

```c
void SDDelete(int fno, char *id);
```

<small><b>FreeBASIC:</b></small>

```freebasic
declare sub SDDelete(byval fno as long, byval id as zstring ptr)
```


<u><b>SDDeleteu</b></u>

<small><b>C:</b></small>

```c
void SDDeleteu(int fno, char *id);
```

<small><b>FreeBASIC:</b></small>

```freebasic
declare sub SDDeleteu(byval fno as long, byval id as zstring ptr)
```


<u><b>SDRecordlock</b></u>

<small><b>C:</b></small>

```c
void SDRecordlock(int fno, char *id, int update_lock, int wait);
```

<small><b>FreeBASIC:</b></small>

```freebasic
declare sub SDRecordlock(byval fno as long, byval id as zstring ptr, _
    byval update_lock as long, byval wait_ as long)
```


<u><b>SDRelease</b></u>

<small><b>C:</b></small>

```c
void SDRelease(int fno, char *id);
```

<small><b>FreeBASIC:</b></small>

```freebasic
declare sub SDRelease(byval fno as long, byval id as zstring ptr)
```

### Select lists and indexes


<u><b>SDSelect</b></u>

<small><b>C:</b></small>

```c
void SDSelect(int fno, int listno);
```

<small><b>FreeBASIC:</b></small>

```freebasic
declare sub SDSelect(byval fno as long, byval listno as long)
```


<u><b>SDClearSelect</b></u>

<small><b>C:</b></small>

```c
void SDClearSelect(int listno);
```

<small><b>FreeBASIC:</b></small>

```freebasic
declare sub SDClearSelect(byval listno as long)
```


<u><b>SDReadList</b></u>

<small><b>C:</b></small>

```c
char *SDReadList(int listno);
```

<small><b>FreeBASIC:</b></small>

```freebasic
declare function SDReadList(byval listno as long) as zstring ptr
```


<u><b>SDReadNext</b></u>

<small><b>C:</b></small>

```c
char *SDReadNext(int16_t listno);
```

<small><b>FreeBASIC:</b></small>

```freebasic
declare function SDReadNext(byval listno as short) as zstring ptr
```


<u><b>SDSelectIndex</b></u>

<small><b>C:</b></small>

```c
void SDSelectIndex(int16_t fno, char *index_name, char *index_value,
                   int16_t listno);
```

<small><b>FreeBASIC:</b></small>

```freebasic
declare sub SDSelectIndex(byval fno as short, _
    byval index_name as zstring ptr, byval index_value as zstring ptr, _
    byval listno as short)
```


<u><b>SDSelectLeft</b></u>

<small><b>C:</b></small>

```c
char *SDSelectLeft(int16_t fno, char *index_name, int16_t listno);
```

<small><b>FreeBASIC:</b></small>

```freebasic
declare function SDSelectLeft(byval fno as short, _
    byval index_name as zstring ptr, byval listno as short) as zstring ptr
```


<u><b>SDSelectRight</b></u>

<small><b>C:</b></small>

```c
char *SDSelectRight(int16_t fno, char *index_name, int16_t listno);
```

<small><b>FreeBASIC:</b></small>

```freebasic
declare function SDSelectRight(byval fno as short, _
    byval index_name as zstring ptr, byval listno as short) as zstring ptr
```


<u><b>SDSetLeft</b></u>

<small><b>C:</b></small>

```c
void SDSetLeft(int16_t fno, char *index_name);
```

<small><b>FreeBASIC:</b></small>

```freebasic
declare sub SDSetLeft(byval fno as short, byval index_name as zstring ptr)
```


<u><b>SDSetRight</b></u>

<small><b>C:</b></small>

```c
void SDSetRight(int16_t fno, char *index_name);
```

<small><b>FreeBASIC:</b></small>

```freebasic
declare sub SDSetRight(byval fno as short, byval index_name as zstring ptr)
```

### Dynamic arrays


<u><b>SDExtract</b></u>

<small><b>C:</b></small>

```c
char *SDExtract(char *src, int fno, int vno, int svno);
```

<small><b>FreeBASIC:</b></small>

```freebasic
declare function SDExtract(byval src as zstring ptr, byval fno as long, _
    byval vno as long, byval svno as long) as zstring ptr
```


<u><b>SDReplace</b></u>

<small><b>C:</b></small>

```c
char *SDReplace(char *src, int fno, int vno, int svno, char *new_string);
```

<small><b>FreeBASIC:</b></small>

```freebasic
declare function SDReplace(byval src as zstring ptr, byval fno as long, _
    byval vno as long, byval svno as long, _
    byval new_string as zstring ptr) as zstring ptr
```


<u><b>SDIns</b></u>

<small><b>C:</b></small>

```c
char *SDIns(char *src, int fno, int vno, int svno, char *new_string);
```

<small><b>FreeBASIC:</b></small>

```freebasic
declare function SDIns(byval src as zstring ptr, byval fno as long, _
    byval vno as long, byval svno as long, _
    byval new_string as zstring ptr) as zstring ptr
```


<u><b>SDDel</b></u>

<small><b>C:</b></small>

```c
char *SDDel(char *src, int fno, int vno, int svno);
```

<small><b>FreeBASIC:</b></small>

```freebasic
declare function SDDel(byval src as zstring ptr, byval fno as long, _
    byval vno as long, byval svno as long) as zstring ptr
```


<u><b>SDLocate</b></u>

<small><b>C:</b></small>

```c
int SDLocate(char *item, char *src, int fno, int vno, int svno,
             int *pos, char *order);
```

<small><b>FreeBASIC:</b></small>

```freebasic
declare function SDLocate(byval item as zstring ptr, _
    byval src as zstring ptr, byval fno as long, byval vno as long, _
    byval svno as long, byref pos as long, _
    byval order_ as zstring ptr) as long
```


<u><b>SDMarkMapping</b></u>

<small><b>C:</b></small>

```c
void SDMarkMapping(int16_t fno, int16_t state);
```

<small><b>FreeBASIC:</b></small>

```freebasic
declare sub SDMarkMapping(byval fno as short, byval state as short)
```

### String operations


<u><b>SDChange</b></u>

<small><b>C:</b></small>

```c
char *SDChange(char *src, char *old_string, char *new_string,
               int occurrences, int start);
```

<small><b>FreeBASIC:</b></small>

```freebasic
declare function SDChange(byval src as zstring ptr, _
    byval old_string as zstring ptr, byval new_string as zstring ptr, _
    byval occurrences as long, byval start as long) as zstring ptr
```


<u><b>SDDcount</b></u>

<small><b>C:</b></small>

```c
int SDDcount(char *src, char *delim);
```

<small><b>FreeBASIC:</b></small>

```freebasic
declare function SDDcount(byval src as zstring ptr, _
    byval delim as zstring ptr) as long
```


<u><b>SDField</b></u>

<small><b>C:</b></small>

```c
char *SDField(char *src, char *delim, int first, int occurrences);
```

<small><b>FreeBASIC:</b></small>

```freebasic
declare function SDField(byval src as zstring ptr, _
    byval delim as zstring ptr, byval first as long, _
    byval occurrences as long) as zstring ptr
```


<u><b>SDMatch</b></u>

<small><b>C:</b></small>

```c
int SDMatch(char *str, char *pattern);
```

<small><b>FreeBASIC:</b></small>

```freebasic
declare function SDMatch(byval str_ as zstring ptr, _
    byval pattern as zstring ptr) as long
```


<u><b>SDMatchfield</b></u>

<small><b>C:</b></small>

```c
char *SDMatchfield(char *str, char *pattern, int component);
```

<small><b>FreeBASIC:</b></small>

```freebasic
declare function SDMatchfield(byval str_ as zstring ptr, _
    byval pattern as zstring ptr, byval component as long) as zstring ptr
```

### Command execution


<u><b>SDExecute</b></u>

<small><b>C:</b></small>

```c
char *SDExecute(char *command, int *err);
```

<small><b>FreeBASIC:</b></small>

```freebasic
declare function SDExecute(byval command as zstring ptr, _
    byref err as long) as zstring ptr
```


<u><b>SDRespond</b></u>

<small><b>C:</b></small>

```c
char *SDRespond(char *response, int *err);
```

<small><b>FreeBASIC:</b></small>

```freebasic
declare function SDRespond(byval response as zstring ptr, _
    byref err as long) as zstring ptr
```


<u><b>SDEndCommand</b></u>

<small><b>C:</b></small>

```c
void SDEndCommand(void);
```

<small><b>FreeBASIC:</b></small>

```freebasic
declare sub SDEndCommand()
```

### Catalogued subroutines


<u><b>SDCall</b></u>

<small><b>C:</b></small>

```c
void SDCall(char *subrname, int16_t argc, ...);
```

<small><b>FreeBASIC:</b></small>

```freebasic
declare sub SDCall cdecl(byval subrname as zstring ptr, _
    byval argc as short, ...)
```


<u><b>SDCallx</b></u>

<small><b>C:</b></small>

```c
void SDCallx(char *subrname, int16_t argc, ...);
```

<small><b>FreeBASIC:</b></small>

```freebasic
declare sub SDCallx cdecl(byval subrname as zstring ptr, _
    byval argc as short, ...)
```


<u><b>SDGetArg</b></u>

<small><b>C:</b></small>

```c
char *SDGetArg(int arg_number);
```

<small><b>FreeBASIC:</b></small>

```freebasic
declare function SDGetArg(byval arg_number as long) as zstring ptr
```

Both variadic functions use the C calling convention. Returned `SDCall`
arguments are written into caller-supplied buffers. `SDCallx` retains returned
arguments for retrieval with `SDGetArg`.

### Packages, status, memory, and diagnostics


<u><b>SDEnterPackage</b></u>

<small><b>C:</b></small>

```c
int16_t SDEnterPackage(char *name);
```

<small><b>FreeBASIC:</b></small>

```freebasic
declare function SDEnterPackage(byval name_ as zstring ptr) as short
```


<u><b>SDExitPackage</b></u>

<small><b>C:</b></small>

```c
int16_t SDExitPackage(char *name);
```

<small><b>FreeBASIC:</b></small>

```freebasic
declare function SDExitPackage(byval name_ as zstring ptr) as short
```


<u><b>SDError</b></u>

<small><b>C:</b></small>

```c
char *SDError(void);
```

<small><b>FreeBASIC:</b></small>

```freebasic
declare function SDError() as zstring ptr
```

Do not pass this pointer to `SDFree`.


<u><b>SDStatus</b></u>

<small><b>C:</b></small>

```c
int SDStatus(void);
```

<small><b>FreeBASIC:</b></small>

```freebasic
declare function SDStatus() as long
```


<u><b>SDFree</b></u>

<small><b>C:</b></small>

```c
void SDFree(void *p);
```

<small><b>FreeBASIC:</b></small>

```freebasic
declare sub SDFree(byval p as any ptr)
```


<u><b>SDDebug</b></u>

<small><b>C:</b></small>

```c
void SDDebug(int16_t mode);
```

<small><b>FreeBASIC:</b></small>

```freebasic
declare sub SDDebug(byval mode as short)
```

## 18. API summary

The authoritative function declarations and parameter types are in
`sdclilib.h`.

| Area | Functions |
|---|---|
| Connections | `SDConnect`, `SDConnected`, `SDDisconnect`, `SDDisconnectAll`, `SDLogto` |
| Sessions | `SDGetSession`, `SDSetSession` |
| Files and records | `SDOpen`, `SDClose`, `SDRead`, `SDReadl`, `SDReadu`, `SDWrite`, `SDWriteu`, `SDDelete`, `SDDeleteu`, `SDRecordlock`, `SDRelease` |
| Select lists | `SDSelect`, `SDClearSelect`, `SDReadList`, `SDReadNext` |
| Indexes | `SDSelectIndex`, `SDSelectLeft`, `SDSelectRight`, `SDSetLeft`, `SDSetRight` |
| Dynamic arrays | `SDExtract`, `SDReplace`, `SDIns`, `SDDel`, `SDLocate`, `SDMarkMapping` |
| Strings | `SDChange`, `SDDcount`, `SDField`, `SDMatch`, `SDMatchfield` |
| Commands | `SDExecute`, `SDRespond`, `SDEndCommand` |
| Subroutines | `SDCall`, `SDCallx`, `SDGetArg` |
| Packages | `SDEnterPackage`, `SDExitPackage` |
| Errors and status | `SDError`, `SDStatus` |
| Memory and diagnostics | `SDFree`, `SDDebug` |
