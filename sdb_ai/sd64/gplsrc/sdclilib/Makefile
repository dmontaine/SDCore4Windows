CC ?= gcc
CFLAGS ?= -O2 -std=c11 -Wall -Wextra -Wpedantic -Wno-unknown-pragmas
CPPFLAGS += -DBUILDING_SDCLILIB
LDLIBS += -lws2_32

# 15 Aug 26 - THE COMPILER'S OWN DIRECTORY MUST BE ON PATH, even when CC is
# already an absolute path.  gcc.exe finds its DLLs beside itself, but the
# subprograms it spawns - cc1.exe, down in ucrt64/lib/gcc/... - do not, and
# resolve their UCRT64 DLLs through PATH.  Without it gcc exits 1 with
# COMPLETELY EMPTY stdout and stderr, even on a one-line program, so it reads
# as "the compiler is broken" rather than as a search-path problem.
#
# It does not bite in an MSYS2 UCRT64 shell, which is what the README tells you
# to use, because that shell already has the directory on PATH.  It bites in
# every other shell, including a plain MSYS2 one - which is where this was
# found, building from the SD for Windows tree.
#
# Only when CC names a path: a bare "gcc" was already found on PATH, and
# $(dir gcc) would prepend "./" to it.  A colon separator is right because this
# makefile is driven by a POSIX shell; build.cmd is the route from a Windows
# prompt and does the same job with a semicolon.
ifneq ($(notdir $(CC)),$(CC))
export PATH := $(dir $(CC)):$(PATH)
endif

DLL = sdclilib.dll
IMPLIB = libsdclilib.dll.a

.PHONY: all clean check

all: $(DLL)

$(DLL): sdclilib.c sdclilib.h sdclient.h err.h revstamp.h
	$(CC) $(CPPFLAGS) $(CFLAGS) -shared -o $@ sdclilib.c \
	  $(LDLIBS) -Wl,--out-implib,$(IMPLIB)

check: $(DLL)
	$(CC) -std=c11 -Wall -Wextra -Wpedantic -o smoke-test.exe \
	  tests/smoke_test.c -I. -L. -lsdclilib
	./smoke-test.exe
	$(CC) -std=c11 -Wall -Wextra -Wpedantic -Wno-unknown-pragmas \
	  -o internal-state-test.exe tests/internal_state_test.c -lws2_32
	./internal-state-test.exe

clean:
	$(RM) $(DLL) $(IMPLIB) smoke-test.exe internal-state-test.exe
