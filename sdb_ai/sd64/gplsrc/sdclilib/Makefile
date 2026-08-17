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

# 17 Aug 26 - SEPARATE FROM "check" ON PURPOSE.  Everything under "check" runs
# without a server, so it can run on any machine at any time.  This one spawns
# sd.exe through the library and therefore measures the INSTALLED system, which
# makes it subject to the test-cycle rule in CLAUDE.md: run gplbld/
# assert-current.ps1 first, and run it UNELEVATED, because the identity the
# grant check tests is the process owner's.
#
# IT IS BUILT INTO localtest/ AND NOT HERE, AND THAT IS LOAD-BEARING.  Windows
# searches an executable's OWN directory for DLLs first, and this directory
# holds a freshly built sdclilib.dll with no sd.exe beside it - so a test run
# from here would load the BUILD library, which would then look for sd.exe next
# to itself and not find one.  From a directory containing neither, the loader
# falls through to PATH and picks up C:\Program Files\SD\usr\bin, where the
# installed DLL and sd.exe sit together.  That is the pair we mean to test.
# AND IT IS RUN FROM INSIDE localtest, WHICH IS THE OTHER HALF.  Building it
# there is not enough: the Windows DLL search looks in the CURRENT WORKING
# DIRECTORY before it reaches PATH, so running it as ./localtest/x.exe from
# here still loads this directory's sdclilib.dll.  Measured 17 Aug 2026 - the
# symptom is "Failed to create child process. Error 2", because the library
# then looks for sd.exe beside the BUILD dll, where there is none.
check-local: $(DLL)
	mkdir -p localtest
	$(CC) -std=c11 -Wall -Wextra -Wpedantic -o localtest/local-connect-test.exe \
	  tests/local_connect_test.c -I. -L. -lsdclilib
	cd localtest && ./local-connect-test.exe

# 17 Aug 26 - THE SELECT PROBE, PROJECT_STATUS.md 7 step 11.  It needs no
# server, no install and no SD at all: it is two throwaway binaries that answer
# one question about the Cygwin runtime, which is why it is not under "check"
# either - "check" is for things that must keep passing, and this is an
# experiment that has already given its answer.
#
# IT NEEDS BOTH TOOLCHAINS IN ONE TARGET, which nothing else here does.  The
# parent is NATIVE UCRT64 and the child is MSYS2/Cygwin, because that is the
# arrangement sdclilib.dll and sd.exe are in (5.3) and the whole question is
# what the Cygwin side sees.  Building either with the other's compiler answers
# a question nobody asked.
#
# UCRT_BIN GOES ON PATH, and leaving it off costs a confusing half hour: the
# UCRT64 gcc driver finds its own cc1.exe by a relative path but cc1 then fails
# to load its DLLs from /ucrt64/bin, and gcc exits 1 having printed NOTHING.
MSYS_CC  := /usr/bin/gcc
UCRT_BIN := /ucrt64/bin
UCRT_CC  := $(UCRT_BIN)/gcc

check-select-probe:
	mkdir -p localtest
	$(MSYS_CC) -std=gnu11 -Wall -Wextra -o localtest/select-probe-child.exe \
	  tests/select_probe_child.c
	PATH="$(UCRT_BIN):$$PATH" $(UCRT_CC) -std=gnu11 -Wall -Wextra \
	  -o localtest/select-probe-parent.exe tests/select_probe_parent.c
	cd localtest && ./select-probe-parent.exe ./select-probe-child.exe ./probe-result.txt
	@echo '--- child results ---'
	@cat localtest/probe-result.txt

clean:
	$(RM) $(DLL) $(IMPLIB) smoke-test.exe internal-state-test.exe
	$(RM) -r localtest
