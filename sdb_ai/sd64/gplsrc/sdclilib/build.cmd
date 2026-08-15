@echo off
setlocal
cd /d "%~dp0"
set "GCC=C:\msys64\ucrt64\bin\gcc.exe"
if not exist "%GCC%" set "GCC=gcc"

rem 15 Aug 26 - the compiler's own directory must be on PATH even though it is
rem invoked by full path.  gcc.exe finds its DLLs beside itself; the cc1.exe it
rem spawns does not, and resolves its UCRT64 DLLs through PATH.  Without this
rem the compile below fails with NO OUTPUT AT ALL, and the script stops at the
rem errorlevel check having printed nothing to explain itself.
for %%I in ("%GCC%") do set "GCCDIR=%%~dpI"
if exist "%GCC%" set "PATH=%GCCDIR%;%PATH%"

"%GCC%" -O2 -std=c11 -Wall -Wextra -Wpedantic ^
  -Wno-unknown-pragmas -DBUILDING_SDCLILIB ^
  -shared -o sdclilib.dll sdclilib.c -lws2_32 ^
  -Wl,--out-implib,libsdclilib.dll.a
if errorlevel 1 exit /b 1

"%GCC%" -std=c11 -Wall -Wextra -Wpedantic -o smoke-test.exe ^
  tests\smoke_test.c -I. -L. -lsdclilib
if errorlevel 1 exit /b 1

rem Run through an explicit path: cmd does not search the current directory
rem when NoDefaultCurrentDirectoryInExePath is set, which it is on some
rem hardened systems - the test then "is not recognized" despite being here.
.\smoke-test.exe
if errorlevel 1 exit /b 1

"%GCC%" -std=c11 -Wall -Wextra -Wpedantic -Wno-unknown-pragmas ^
  -o internal-state-test.exe tests\internal_state_test.c -lws2_32
if errorlevel 1 exit /b 1

.\internal-state-test.exe
if errorlevel 1 exit /b 1

echo Built sdclilib.dll and libsdclilib.dll.a
