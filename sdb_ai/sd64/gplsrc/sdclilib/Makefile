# 17 Aug 26 - "CC ?= gcc" DID NOTHING, and that is a GNU make trap rather than a
# typo.  "?=" is "set this if the variable is UNDEFINED", and make has a
# built-in CC whose origin is "default" - which is defined - so the assignment
# never fired and CC stayed "cc".  Nobody noticed because the top-level Makefile
# passes CC= explicitly for the DLL; it surfaced on "make check-local", which
# built a native test with the MSYS2 compiler and failed to run.
ifeq ($(origin CC),default)
CC := gcc
endif
CFLAGS ?= -O2 -std=c11 -Wall -Wextra -Wpedantic -Wno-unknown-pragmas
CPPFLAGS += -DBUILDING_SDCLILIB
# 19 Aug 26 - bcrypt for the SCRAM login (docs/SCRAM_AUTH.md phase 4):
# BCryptDeriveKeyPBKDF2, BCryptGenRandom and HMAC-SHA256.  It is a WINDOWS
# system DLL, so the client stays a single file that can be copied next to an
# application - the property the 32-bit qmclilib build exists to preserve, and
# the reason the primitives came from here rather than from a library that
# would have had to travel with it.
LDLIBS += -lws2_32 -lbcrypt

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

# ===========================================================================
# THE 32-BIT COMPILER.  PRE_RELEASE_FIXES 161.
#
# 04 Sep 26 - THIS DIRECTORY NOW BUILDS ALL FOUR CLIENT DLLs, and two of them
# are i686.  Before today the 32-bit pair was hand-built in ../sdclilib32
# against this tree's source, and the four DLLs nothing here built were
# FIFTEEN DAYS STALE when it was measured - with the older copy winning on
# PATH.  A build that cannot diverge beats a check that reports divergence.
#
# NAMED IN POSIX FORM, like UCRT_CC in the top-level Makefile, and that is not
# cosmetic.  ../sdclilib32 defaults it to "C:/msys64/..." because build.cmd
# reaches it from a Windows prompt; under MSYS2 make PATH is POSIX and joined
# with colons, so prepending a drive-letter path splits at the colon into the
# two nonexistent entries "C" and "/msys64/mingw32/bin".  PATH then LOOKS
# modified, the directory is still not on it, and the compile fails with the
# empty exit 1 described above from a makefile that appears to have guarded
# against exactly that.
CC32 ?= /c/msys64/mingw32/bin/gcc.exe

# The 32-bit compile gets its own PATH with mingw32/bin FIRST.  PATH already
# has ucrt64/bin on the front from the block above, and cc1.exe resolves its
# DLLs through PATH in order - so without this the i686 cc1 would find the
# x86_64 runtime DLLs first.  Same reasoning as the 64-bit block; only the
# directory differs.
ifneq ($(notdir $(CC32)),$(CC32))
CC32PATH := $(patsubst %/,%,$(dir $(CC32))):$(PATH)
else
CC32PATH := $(PATH)
endif

# -static-libgcc, which the 64-bit build does not need and this one does.  The
# i686 build pulls in the DWARF-2 unwinder and so links libgcc_s_dw2-1.dll,
# which lives in C:\msys64\mingw32\bin and nowhere else on a machine without
# MSYS2.  A DLL that loads on the build machine and fails on every other one is
# the worst way to find that out, and the failure names the missing libgcc
# rather than anything to do with this library.  Linked in statically, the only
# remaining dependencies are kernel32, msvcrt and ws2_32, all of which are part
# of Windows - so the DLL can simply be copied next to the application, which
# is the whole route PRE_RELEASE 161 documents.
LDFLAGS32 += -static-libgcc

# ===========================================================================
# THE ARCHITECTURE CHECK, AT RECIPE TIME RATHER THAN PARSE TIME
#
# ../sdclilib32 does this with $(error), which it can afford because 32-bit is
# all it builds.  Here a parse-time error would stop the SERVER building on a
# machine with no i686 toolchain, so the check moved into the recipe.
#
# IT PRINTS WHAT IT MEASURED, not just its conclusion - CLAUDE.md's instrument
# rule.  The failure it exists to stop is silent: a bare "gcc" on this machine
# is the UCRT64 x86_64 one, and it would cheerfully produce a 64-bit DLL named
# qmclilib.dll, which loads in nothing and says only "%1 is not a valid Win32
# application" when it fails.  AND IT REFUSES THE NULL CASE: a compiler that
# cannot run at all answers the empty string, which must not read as a pass.
# ===========================================================================
define check_cc32
	@arch=`PATH="$(CC32PATH)" "$(CC32)" -dumpmachine 2>/dev/null`; \
	echo "  32-bit compiler $(CC32) -dumpmachine = $${arch:-<could not run>}"; \
	case "$$arch" in \
	  *i686*) ;; \
	  '') echo "" >&2; \
	      echo "Cannot run $(CC32).  Install the 32-bit toolchain with" >&2; \
	      echo '  pacman -S mingw-w64-i686-gcc' >&2; \
	      echo "in an MSYS2 shell, or set CC32 to a 32-bit compiler." >&2; \
	      exit 2 ;; \
	  *)  echo "" >&2; \
	      echo "$(CC32) targets $$arch, not i686.  These two DLLs are the" >&2; \
	      echo "32-bit pair; a 64-bit build under those names loads in" >&2; \
	      echo "nothing.  Set CC32 to a 32-bit compiler." >&2; \
	      exit 2 ;; \
	esac
endef

# ===========================================================================
# THE FOUR DLLs.  ONE SOURCE, FOUR NAMES, AND NONE OF THEM IS A COPY
#
# WHY A SECOND LINK AND NOT A COPY OF THE FILE.  An import library records the
# DLL name its symbols come from, so a renamed copy hands out an implib that
# still points at the first DLL.  On the 32-bit side it is worse: the .def
# carries a LIBRARY statement, which is what sets that name, so the second DLL
# needs a .def of its own or its implib points at the first no matter what -o
# says.
#
# <x>clilib.dll is the name existing applications already ask for and does not
# move; <x>client.dll is the name to use from now on.  They are not
# alternatives to choose between - an application asks for one by name.
# ===========================================================================
DLL = sdclilib.dll
IMPLIB = libsdclilib.dll.a
DLL2 = sdclient.dll
IMPLIB2 = libsdclient.dll.a

QMDLL = qmclilib.dll
QMIMPLIB = libqmclilib.dll.a
QMDEF = qmclilib.def
QMDLL2 = qmclient.dll
QMIMPLIB2 = libqmclient.dll.a
QMDEF2 = qmclient.def

# The library's own headers, and the two files that are 32-bit-only: qmcompat.c
# implements QMConnectLocal, which is the one QM entry point with no sdclilib
# counterpart and so the only one that cannot be aliased in the .def.
HDRS = sdclilib.h sdclient.h err.h revstamp.h
QMSRCS = sdclilib.c qmcompat.c

# ===========================================================================
# THE 32-BIT DIAGNOSTIC CLIENT, AND IT IS BUILT BY "all" ON PURPOSE
#
# 04 Sep 26 - PRE_RELEASE_FIXES 161.  ../sdclilib32 built sd-connect.exe ON
# DEMAND, and TWO verifiers in the standing suite pointed at it there.  When
# that tree was deleted the suite said so in two different voices:
#
#   verify-tierapi  exit 2, COULD NOT RUN      - loud, and correct
#   verify-doors    SKIPPED its API door in BOTH phases and STILL EXITED 0
#
# The second is the one that matters.  A binary the suite needs, built by hand,
# in a tree outside this one, is the same defect 161 exists to remove - so it
# is built here, every time, by the same command that builds the DLL it loads.
#
# IT LINKS AGAINST qmclilib.dll AND MUST SIT BESIDE IT.  Windows searches an
# executable's own directory first, and nothing is on PATH any more, so the
# top-level Makefile copies this into bin\client32 where that DLL lands.
SDCONNECT = sd-connect.exe

.PHONY: all clean check

all: $(DLL) $(DLL2) $(QMDLL) $(QMDLL2) $(SDCONNECT)

$(DLL): sdclilib.c $(HDRS)
	$(CC) $(CPPFLAGS) $(CFLAGS) -shared -o $@ sdclilib.c \
	  $(LDLIBS) -Wl,--out-implib,$(IMPLIB)

$(DLL2): sdclilib.c $(HDRS)
	$(CC) $(CPPFLAGS) $(CFLAGS) -shared -o $@ sdclilib.c \
	  $(LDLIBS) -Wl,--out-implib,$(IMPLIB2)

# The .def supplies the export table.  Without it the QM names do not exist:
# __declspec(dllexport) in sdclilib.c only ever produces SD ones.
$(QMDLL): $(QMSRCS) $(HDRS) qmclilib.h $(QMDEF)
	$(call check_cc32)
	PATH="$(CC32PATH)" $(CC32) $(CPPFLAGS) $(CFLAGS) $(LDFLAGS32) \
	  -shared -o $@ $(QMSRCS) $(QMDEF) \
	  $(LDLIBS) -Wl,--out-implib,$(QMIMPLIB)

# GENERATED, NOT MAINTAINED, AND DELIBERATELY NOT TRACKED.  The export list is
# 99 names and two hand-kept copies of it would diverge - most likely by one
# name, in the direction that fails only at run time and only for whoever used
# that call.  So the second .def is the first with its LIBRARY line rewritten,
# and nothing else.
$(QMDEF2): $(QMDEF)
	sed 's/^LIBRARY .*/LIBRARY $(QMDLL2)/' $< > $@

$(QMDLL2): $(QMSRCS) $(HDRS) qmclilib.h $(QMDEF2)
	$(call check_cc32)
	PATH="$(CC32PATH)" $(CC32) $(CPPFLAGS) $(CFLAGS) $(LDFLAGS32) \
	  -shared -o $@ $(QMSRCS) $(QMDEF2) \
	  $(LDLIBS) -Wl,--out-implib,$(QMIMPLIB2)

# 32-BIT, like the DLL it drives, and that is the whole point of it: it proves
# a claim about the library mvDeveloper actually loads rather than about the
# protocol in the abstract.  Built from this tree since 4 Sep 2026 - see the
# note at SDCONNECT above for what its absence cost.
$(SDCONNECT): tools/sd_connect.c qmclilib.h $(QMDLL)
	$(call check_cc32)
	PATH="$(CC32PATH)" $(CC32) -std=c11 -Wall -Wextra -Wpedantic \
	  -o $@ tools/sd_connect.c -I. -L. -lqmclilib -lws2_32

check: $(DLL) $(DLL2) $(QMDLL) $(QMDLL2)
	$(CC) -std=c11 -Wall -Wextra -Wpedantic -o smoke-test.exe \
	  tests/smoke_test.c -I. -L. -lsdclilib
	./smoke-test.exe
	$(CC) -std=c11 -Wall -Wextra -Wpedantic -Wno-unknown-pragmas \
	  -o internal-state-test.exe tests/internal_state_test.c -lws2_32 -lbcrypt
	./internal-state-test.exe
# 04 Sep 26 - THE SAME TEST THROUGH THE SECOND 64-BIT NAME, and it is the only
# thing here that would catch an implib pointing at the wrong DLL.  Carried
# over from ../winsdclilib/build.cmd when this directory took over the build.
	$(CC) -std=c11 -Wall -Wextra -Wpedantic -o smoke-test-sdclient.exe \
	  tests/smoke_test.c -I. -L. -lsdclient
	./smoke-test-sdclient.exe
# 04 Sep 26 - THE 32-BIT PAIR, and the alias test is the right one to repeat
# rather than the smoke one.  It resolves QM export names, so it fails if the
# .def lost the export list, AND it loads the DLL by name, so it fails if the
# generated LIBRARY line left the implib pointing at qmclilib.dll.  Those are
# the only two ways the second name can be wrong.  Carried over from
# ../sdclilib32/Makefile with the build.
	$(call check_cc32)
	PATH="$(CC32PATH)" $(CC32) -std=c11 -Wall -Wextra -Wpedantic \
	  -o qm-alias-test.exe tests/qm_alias_test.c -I. -L. -lqmclilib
	./qm-alias-test.exe
	PATH="$(CC32PATH)" $(CC32) -std=c11 -Wall -Wextra -Wpedantic \
	  -o qm-alias-test-qmclient.exe tests/qm_alias_test.c -I. -L. -lqmclient
	./qm-alias-test-qmclient.exe

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
# 17 Aug 26 - THE RUN NEEDS A PATH, and without it this target reported
# "Error 127" and looked exactly like a broken transport.  Two things are
# missing from a plain MSYS2 login shell:
#
#   * the INSTALLED bin, which is the whole point - the loader is meant to fall
#     through to PATH and pick up the installed sdclilib.dll and sd.exe as a
#     pair.  With nothing there it finds no library at all.
#   * the Windows system directory.  This test is a NATIVE UCRT64 binary and
#     resolves api-ms-win-crt-*.dll through the OS; an MSYS2 login shell rebuilds
#     PATH without System32, and the failure names an api-ms-win-crt DLL, which
#     reads as a broken toolchain rather than a missing search path.
#
# Override SDBIN if SD is installed somewhere else.
SDBIN   ?= /c/Program Files/SD/usr/bin
WINSYS  ?= /c/WINDOWS/System32

check-local: $(DLL)
	mkdir -p localtest
	$(CC) -std=c11 -Wall -Wextra -Wpedantic -o localtest/local-connect-test.exe \
	  tests/local_connect_test.c -I. -L. -lsdclilib
	cd localtest && PATH="$(SDBIN):$(WINSYS):$$PATH" ./local-connect-test.exe

# 17 Aug 26 - THE REMOTE TEST, PROJECT_STATUS.md 7 step 6.  Same rule as
# check-local: it measures the INSTALLED tree, so it is not under "check".
#
# IT TAKES ARGUMENTS AND HAS NO DEFAULTS ON PURPOSE.  APIPORT is off on a fresh
# install and the account it uses must have a password set, so there is no
# combination this could usefully guess; gplbld/verify-apiport.ps1 sets the
# whole thing up and passes them in.  Run by hand:
#
#   make check-remote APIHOST=127.0.0.1 APIPORT=4243 \
#        APIUSER=<user> APIPASS=<password> APIACCT=<ACCOUNT>
APIHOST ?= 127.0.0.1
APIPORT ?=
APIUSER ?=
APIPASS ?=
APIACCT ?=

check-remote: $(DLL)
	@if [ -z "$(APIPORT)" ] || [ -z "$(APIUSER)" ] || [ -z "$(APIACCT)" ]; then \
	  echo "check-remote needs APIPORT, APIUSER, APIPASS and APIACCT - see the"; \
	  echo "comment above this target, or run gplbld/verify-apiport.ps1 which"; \
	  echo "sets all of it up and passes them in."; exit 2; fi
	mkdir -p localtest
	$(CC) -std=c11 -Wall -Wextra -Wpedantic -o localtest/remote-connect-test.exe \
	  tests/remote_connect_test.c -I. -L. -lsdclilib
	cd localtest && PATH="$(SDBIN):$(WINSYS):$$PATH" ./remote-connect-test.exe \
	  "$(APIHOST)" "$(APIPORT)" "$(APIUSER)" "$(APIPASS)" "$(APIACCT)"

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

# 17 Aug 26 - THE SOCKET PROBE, which settled the remote transport (section 7
# step 6).  It answers whether a NATIVE listener can hand an accepted socket to
# an MSYS2 child as its standard input: it cannot, and the four cells below are
# why.  The pipe rows are the control - same descriptor number, same spawn
# path - and without them the socket rows would prove nothing.
#
# Expected, and it is a FAILURE that is being recorded rather than a pass:
#   pipe empty  select=0        pipe data  select=1, read OK    <- control
#   sock empty  select=0        sock data  select=0, EAGAIN     <- the finding
check-sock-probe:
	mkdir -p localtest
	$(MSYS_CC) -std=gnu11 -Wall -Wextra -o localtest/sock-probe-child.exe \
	  tests/sock_probe_child.c
	PATH="$(UCRT_BIN):$$PATH" $(UCRT_CC) -std=gnu11 -Wall -Wextra \
	  -o localtest/sock-probe-parent.exe tests/sock_probe_parent.c -lws2_32
	@cd localtest && for kind in pipe sock; do \
	  for mode in empty data; do \
	    ./sock-probe-parent.exe ./sock-probe-child.exe $$kind $$mode; \
	  done; \
	done

# 20 Aug 26 - WHAT PRIVILEGE A REMOTE API SESSION HOLDS.  PROJECT_STATUS.md
# section 8.  APISRVR asserts twice that an API session "cannot have"
# elevation and gates accounts on that basis; sdwind is a LocalSystem service
# and fork()s the session, so the session inherits SYSTEM's token rather than
# the client's.  This runs a command down a real API connection so the same
# command can be run locally and the two compared.
#
# THE COMPARISON IS THE MEASUREMENT and lives in gplbld/verify-apiadmin.ps1,
# which sets up the throwaway account and passes everything in.  Run by hand it
# needs APIPORT, APIUSER, APIPASS, APIACCT and APICMD.
APICMD  ?=

check-api-admin: $(DLL)
	@if [ -z "$(APIPORT)" ] || [ -z "$(APIUSER)" ] || [ -z "$(APIACCT)" ] \
	   || [ -z "$(APICMD)" ]; then \
	  echo "check-api-admin needs APIPORT, APIUSER, APIPASS, APIACCT and"; \
	  echo "APICMD - run gplbld/verify-apiadmin.ps1, which sets all of it up."; \
	  exit 2; fi
	mkdir -p localtest
	$(CC) -std=c11 -Wall -Wextra -Wpedantic -o localtest/api-admin-probe.exe \
	  tests/api_admin_probe.c -I. -L. -lsdclilib
	cd localtest && PATH="$(SDBIN):$(WINSYS):$$PATH" ./api-admin-probe.exe \
	  "$(APIHOST)" "$(APIPORT)" "$(APIUSER)" "$(APIPASS)" "$(APIACCT)" "$(APICMD)"

# 20 Aug 26 - THE PEER PROBE, which settled how the API can identify the
# process at the other end of a connection (section 8, posture B).
#
# SECTION 8 PROPOSED A NAMED PIPE WITH GetNamedPipeClientProcessId, AND THAT
# TRANSPORT IS CLOSED - section 7 step 11 measured it on 17 Aug 2026: a named
# pipe pushed into the Cygwin descriptor table is reported PERMANENTLY READY
# by select(), so sdpoll() spins and sd.exe never answers.  sd.c refuses the
# "-C <pipename>" form for exactly that reason.
#
# GetExtendedTcpTable asks the same question of the socket sdwind ALREADY has,
# and changes no transport at all.  This probe proves it end to end and knows
# the answer independently: it fork()s its own client, so the pid it is looking
# for is one fork() told it rather than one it deduced.
#
# BOTH HALVES ARE MSYS2 - unlike the sock probe above, there is no native
# parent.  The split is a HEADER problem, not a process one: <windows.h> and
# <netinet/in.h> cannot share a translation unit (redefinition of struct
# in6_addr, w32api against cygwin), which is why the Windows half takes plain
# integers and the socket half never sees a Windows header.  Same shape as
# gplsrc/win32sem.c, win32audit.c and win32pipe.c.
#
# Expected:
#   owning pid matches the client's WINDOWS pid   <- cross-checked with
#                                                   cygwin_internal()
#   peer resolves to a DOMAIN and account name
#   control: a non-existent peer returns 0        <- without it, a lookup that
#                                                   returned a constant would pass
# 20 Aug 26 - IT COMPILES THE SHIPPED FILE, not a copy of it.  The Windows
# half was proved here as tests/peer_probe_win32.c and moved to
# gplsrc/win32peer.c when sdwind gained the call; building ../win32peer.c is
# what stops the test and the shipped code drifting apart, which a second copy
# would have guaranteed the first time either was corrected.
check-peer-probe:
	mkdir -p localtest
	$(MSYS_CC) -std=gnu17 -Wall -Wextra -I.. -c ../win32peer.c \
	  -o localtest/win32peer.o
	$(MSYS_CC) -std=gnu17 -Wall -Wextra -I.. -c tests/peer_probe_main.c \
	  -o localtest/peer_probe_main.o
	$(MSYS_CC) localtest/peer_probe_main.o localtest/win32peer.o \
	  -liphlpapi -o localtest/peer-probe.exe
	cd localtest && ./peer-probe.exe

clean:
	$(RM) $(DLL) $(IMPLIB) $(DLL2) $(IMPLIB2) \
	  $(QMDLL) $(QMIMPLIB) $(QMDLL2) $(QMIMPLIB2) $(QMDEF2) $(SDCONNECT) \
	  smoke-test.exe smoke-test-sdclient.exe internal-state-test.exe \
	  qm-alias-test.exe qm-alias-test-qmclient.exe
	$(RM) -r localtest
