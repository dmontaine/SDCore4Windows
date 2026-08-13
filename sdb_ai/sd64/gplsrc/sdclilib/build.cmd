@echo off
setlocal
cd /d "%~dp0"
set "GCC=C:\msys64\ucrt64\bin\gcc.exe"
if not exist "%GCC%" set "GCC=gcc"

"%GCC%" -O2 -std=c11 -Wall -Wextra -Wpedantic ^
  -Wno-unknown-pragmas -DBUILDING_SDCLILIB ^
  -shared -o sdclilib.dll sdclilib.c -lws2_32 ^
  -Wl,--out-implib,libsdclilib.dll.a
if errorlevel 1 exit /b 1

"%GCC%" -std=c11 -Wall -Wextra -Wpedantic -o smoke-test.exe ^
  tests\smoke_test.c -I. -L. -lsdclilib
if errorlevel 1 exit /b 1

smoke-test.exe
if errorlevel 1 exit /b 1

"%GCC%" -std=c11 -Wall -Wextra -Wpedantic -Wno-unknown-pragmas ^
  -o internal-state-test.exe tests\internal_state_test.c -lws2_32
if errorlevel 1 exit /b 1

internal-state-test.exe
if errorlevel 1 exit /b 1

echo Built sdclilib.dll and libsdclilib.dll.a
