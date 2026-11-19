# gplsrc/sdclilib/Makefile - the API client PROBES the verifiers use.  It builds NO client library.
#
# 19 Nov 26 Windows port - RELEASE_1.1 351 (Linux S.262, c89f3864).  The owner, 17 Nov 2026: "since we now ship our clean
#   room versions of the clients, there is probably no need for the versions compiled during the build"; 19 Nov: "do it".
#   The GPL client library that this directory built (sdclilib.c, sd_tls.c, sd_pin.c, qmcompat.c and their headers, the
#   four DLLs, sd-connect.exe) is gone.  What every SD Core ships is the clean-room library, written without that source so
#   that a commercial program may link to it; its binaries live outside every repository (P:\git-private\
#   sdclientlib-binaries\<commit>-<date>), and gplbld\stage-clients.ps1 puts them beside the installer.
#   The probes below are this project's own test programs; they are compiled against the SHIPPED header
#   (sdsys/syscom/sdclilib.h, the one a customer builds with) and linked against the clean-room import library, so a probe
#   tests exactly what a customer's program would.  Measured 19 Nov: all five compile and link with no warning.
#   The history of the GPL build (17 Aug 26 - 14 Nov 26) is in git log for this file.
#
# CLIENTLIB is the clean-room set's win64 folder (libsdclilib.dll.a); by default the newest set on P:.  A machine without
# one builds no probe and says so; the verifiers then refuse (no probe binary) rather than pass.
ifeq ($(origin CC),default)
CC := gcc
endif
# The newest set by its COMMIT.txt's time, not by name: a set's name starts with its commit hash, which does not sort by date.
CLIENTLIB ?= $(patsubst %/COMMIT.txt,%/win64,$(firstword $(shell ls -t /p/git-private/sdclientlib-binaries/*/COMMIT.txt 2>/dev/null)))
CLIENTHDR := ../../sdsys/syscom
PROBEFLAGS = -std=c11 -Wall -Wextra -Wpedantic -I$(CLIENTHDR)
PROBELIBS  = -L"$(CLIENTLIB)" -lsdclilib -lws2_32

ifneq ($(notdir $(CC)),$(CC))
export PATH := $(dir $(CC)):$(PATH)
endif

LOCALTEST = localtest/local-connect-test.exe
SDSYSPROBE = localtest/local-sdsys-probe.exe

.PHONY: all clean clientlib build-api-identity check-api-identity check-local check-remote check-api-admin \
        check-select-probe check-sock-probe check-peer-probe

# The probes a cycle's suite needs, built by "make sd" through the top-level clientprobes target.
all: clientlib $(LOCALTEST) $(SDSYSPROBE) localtest/remote-connect-test.exe

clientlib:
	@if [ -z "$(CLIENTLIB)" ] || [ ! -f "$(CLIENTLIB)/libsdclilib.dll.a" ]; then \
	  echo "  no clean-room client library (CLIENTLIB='$(CLIENTLIB)'): the API probes are not built"; \
	  echo "  set CLIENTLIB to a set's win64 folder (P:\\git-private\\sdclientlib-binaries\\<set>\\win64)"; \
	  exit 3; fi
	@echo "  API probes against the clean-room library in $(CLIENTLIB) and $(CLIENTHDR)/sdclilib.h"

# THE PROBES ARE BUILT INTO localtest/ AND RUN FROM INSIDE IT, AND THAT IS LOAD-BEARING (17 Aug 26).  Windows searches an
# executable's own directory and then the current directory for DLLs before PATH.  localtest/ holds no client DLL, so the
# loader falls through to PATH, which the run puts C:\Program Files\SD\usr\bin at the front of: the INSTALLED sdclilib.dll
# and sd.exe, as a pair - SDConnectLocal starts the sd.exe beside the DLL.  That is the pair a probe means to test.  The
# run also needs System32 on PATH: an MSYS2 login shell drops it, and a native probe then fails on an api-ms-win-crt DLL.
# Override SDBIN if SD is installed somewhere else.
SDBIN   ?= /c/Program Files/SD/usr/bin
WINSYS  ?= /c/WINDOWS/System32

$(LOCALTEST): tests/local_connect_test.c $(CLIENTHDR)/sdclilib.h
	mkdir -p localtest
	$(CC) $(PROBEFLAGS) -o $@ tests/local_connect_test.c $(PROBELIBS)

$(SDSYSPROBE): tests/local_sdsys_probe.c $(CLIENTHDR)/sdclilib.h
	mkdir -p localtest
	$(CC) $(PROBEFLAGS) -o $@ tests/local_sdsys_probe.c $(PROBELIBS)

# check-local: SDConnectLocal as the caller, no password (gplbld/verify-localconnect.ps1 derives LOCALACCT and runs it
# UNELEVATED - the identity is the process owner).
LOCALACCT ?=
check-local: $(LOCALTEST)
	@if [ -z "$(LOCALACCT)" ]; then \
	  echo "check-local needs LOCALACCT=<account> - an SD account the CALLER is"; \
	  echo "granted, normally their own.  SDConnectLocal sends no password; the"; \
	  echo "identity comes from the process owner, so run it UNELEVATED."; \
	  echo "gplbld/verify-localconnect.ps1 derives it and passes it in."; \
	  exit 4; fi
	cd localtest && PATH="$(SDBIN):$(WINSYS):$$PATH" ./local-connect-test.exe "$(LOCALACCT)"

APIHOST ?= 127.0.0.1
APIPORT ?=
APIUSER ?=
APIPASS ?=
APIACCT ?=

# The remote probe on its own (gplbld/verify-apiname.ps1 builds it by this name).
localtest/remote-connect-test.exe: clientlib tests/remote_connect_test.c $(CLIENTHDR)/sdclilib.h
	mkdir -p localtest
	$(CC) $(PROBEFLAGS) -o $@ tests/remote_connect_test.c $(PROBELIBS)

check-remote: localtest/remote-connect-test.exe
	@if [ -z "$(APIPORT)" ] || [ -z "$(APIUSER)" ] || [ -z "$(APIACCT)" ]; then \
	  echo "check-remote needs APIPORT, APIUSER, APIPASS and APIACCT - run"; \
	  echo "gplbld/verify-apiport.ps1, which sets all of it up and passes them in."; exit 2; fi
	cd localtest && PATH="$(SDBIN):$(WINSYS):$$PATH" ./remote-connect-test.exe \
	  "$(APIHOST)" "$(APIPORT)" "$(APIUSER)" "$(APIPASS)" "$(APIACCT)"

APICMD  ?=
check-api-admin: clientlib
	@if [ -z "$(APIPORT)" ] || [ -z "$(APIUSER)" ] || [ -z "$(APIACCT)" ] \
	   || [ -z "$(APICMD)" ]; then \
	  echo "check-api-admin needs APIPORT, APIUSER, APIPASS, APIACCT and"; \
	  echo "APICMD - run gplbld/verify-apiadmin.ps1, which sets all of it up."; \
	  exit 2; fi
	mkdir -p localtest
	$(CC) $(PROBEFLAGS) -o localtest/api-admin-probe.exe tests/api_admin_probe.c $(PROBELIBS)
	cd localtest && PATH="$(SDBIN):$(WINSYS):$$PATH" ./api-admin-probe.exe \
	  "$(APIHOST)" "$(APIPORT)" "$(APIUSER)" "$(APIPASS)" "$(APIACCT)" "$(APICMD)"

APIFILE ?=
build-api-identity: clientlib
	mkdir -p localtest
	$(CC) $(PROBEFLAGS) -o localtest/api-identity-probe.exe tests/api_identity_probe.c $(PROBELIBS)

check-api-identity: build-api-identity
	@if [ -z "$(APIPORT)" ] || [ -z "$(APIUSER)" ] || [ -z "$(APIACCT)" ] \
	   || [ -z "$(APIFILE)" ]; then \
	  echo "check-api-identity needs APIPORT, APIUSER, APIPASS, APIACCT and"; \
	  echo "APIFILE - the fixture VOC pointer name to try opening."; \
	  exit 2; fi
	cd localtest && PATH="$(SDBIN):$(WINSYS):$$PATH" ./api-identity-probe.exe \
	  "$(APIHOST)" "$(APIPORT)" "$(APIUSER)" "$(APIPASS)" "$(APIACCT)" \
	  --open "$(APIFILE)"

# The three below are measurements of the SERVER's runtime (MSYS2 select, sockets, the peer lookup), not of the client
# library; they never linked it and are unchanged.
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
	$(RM) -r localtest
