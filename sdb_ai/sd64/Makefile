# SD Makefile
#
#   You are allowed to modify this file, so long as the derived file can
#   be distributed under the same license as this file.  You are allowed to copy
#   and distribute verbatim copies of this document so long as you follow
#   the licensing agreements contained within this document.
#
#   This program is free software; you can redistribute it and/or modify it
#   under the terms of the GNU General Public License as published by the Free
#   Software Foundation; either version 3 of the License, or (at your option)
#   any later version.
#   This program is distributed in the hope that it will be useful, but WITHOUT
#   ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
#   FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for
#   more details.
#   You should have received a copy of the GNU General Public License along with
#   this program; if not, write to the Free Software Foundation, Inc.,
#   59 Temple Place, Suite 330, Boston, MA 02111-1307 USA
#
# Note - for some reason this makefile had the entire text of the GPLv3 license
#        attached at the end. I've removed it as part of doing updates to this
#        Makefile.  The GPL v3 License can be found here:
#        https://www.gnu.org/licenses/gpl-3.0.txt
#
# rev 0.9-1 Mar 25 mab add  -std=gnu17 to compile flags for  gcc-15
# rev 0.9.0 Jan 25 mab add embedded python 
#
# MAIN     := ./
MAIN     := $(shell pwd)/
GPLSRC   := $(MAIN)gplsrc/
GPLDOTSRC := $(MAIN)gpl.src
GPLOBJ   := $(MAIN)gplobj/
GPLBIN   := $(MAIN)bin/
TERMINFO := $(MAIN)terminfo/
VPATH    := $(GPLOBJ):$(GPLBIN):$(GPLSRC)

# rev 0.9.0 libsodium headers
# 13 Aug 26 Windows port - PY_HDRS and PY_LDFLAGS removed with embedded Python
#           (PROJECT_STATUS.md 5.15).  Dropping them also removes the
#           python-devel and gettext-devel build dependencies: gettext was only
#           needed because "python3-config --ldflags --embed" emits -lintl.

# 13 Aug 26 Windows port - libsodium is not packaged for the MSYS2 runtime and
#           is built from source into /usr/local.
SODIUM   := /usr/local/include
LIBSODIUM := /usr/local/lib

COMP     := gcc
# rev 0.9.0 python
# 13 Aug 26 Windows port - dropped -Wl,--no-as-needed, which is ELF only and
#           is rejected by the PE/COFF linker.
# 16 Aug 26 - -ladvapi32 is for sdsem.c, the one server file that includes
# windows.h (its header says why).  LookupAccountName, ConvertSidToStringSid
# and ConvertStringSecurityDescriptorToSecurityDescriptor all live there; the
# semaphore calls themselves are in kernel32, which mingw links by default.
# 23 Aug 26 Windows port - -lsecur32 is for win32s4u.c: LsaRegisterLogonProcess,
# LsaLogonUser and LsaDeregisterLogonProcess live there, not in advapi32.
L_FLAGS    := -lm -lcrypt -ldl -lbsd -L$(LIBSODIUM) -lsodium -ladvapi32 -lsecur32

RM       := rm

# 21 Aug 26 Windows port - THIS WAS EMPTY, AND IT COST A CYCLE.
#
# It was "$(wildcard *.h)".  make runs from sdb_ai/sd64, where there is not one
# .h file - they are all in gplsrc/ - so SDHDRS expanded to NOTHING, and it was
# then used nowhere either, so nothing complained.  VPATH does not help: it
# tells make where to LOOK for a prerequisite, and $(wildcard) does not consult
# it.
#
# WHAT THAT MEANT: the .c.o suffix rule at the bottom of this file gives an
# object exactly one prerequisite, its own .c.  A change to a HEADER therefore
# rebuilt only the twelve objects with explicit rules below - and every other
# object kept whatever struct layout it was compiled against.
#
# MEASURED 21 Aug 2026, after a cycle failed at "sd -i did not create voc".
# struct SYSSEG had gained a field; "make sd" reported success; and gplobj held
# 69 objects from 18 August beside 15 from that morning.  ONE BINARY WITH TWO
# DIFFERENT IDEAS OF WHERE sysseg->netfiles LIVES.  It linked without a
# warning, started, and then did nothing - which is the worst way for this to
# fail, because every visible signal said the build was fine.
#
# The dependency below is deliberately blunt: ANY header change rebuilds
# EVERYTHING.  A full build is a couple of minutes and this codebase has no
# header hygiene to lean on; -MMD dependency files would be more precise and
# would also be a thing to get wrong.  Correctness first.
SDHDRS   := $(wildcard $(GPLSRC)*.h)
SDSRCS   := $(shell cat $(GPLDOTSRC))
SDTEMP   := $(addsuffix .o,$(SDSRCS))
SDOBJS   := $(SDTEMP)
SDOBJSD  := $(addprefix $(GPLOBJ),$(SDTEMP))
# 21 Aug 26 Windows port - THE SAME EMPTY-WILDCARD BUG AS SDHDRS ABOVE, found
# the same day and one fix later.  This was "$(wildcard *.c)", evaluated from
# sdb_ai/sd64, where there is not one .c file - so SRCS, OBJS and DIROBJS all
# expanded to NOTHING.  All three were dead, which is why nothing complained.
#
# IT MATTERED THE MOMENT SDHDRS WAS FIXED, because "$(OBJS): $(SDHDRS)" below
# was then a dependency on an EMPTY list of targets - it read as if every
# object depended on every header and covered nothing that $(SDOBJS) did not
# already cover.  MEASURED: after fixing SDHDRS, a change to sd.h rebuilt 91
# of 94 objects, and the three left behind were sdwind.o, sdtic.o and
# win32peer.o - none of which is in gpl.src and none of which has an explicit
# rule listing sd.h.
#
# sdwind.o IS THE ONE THAT MATTERS.  sdwind.c includes sd.h and reads sysseg->
# in eight places, including api_port, so a struct SYSSEG change would leave
# THE API LISTENER compiled against the old layout while everything else moved
# - the same fault that cost a cycle earlier today, in the one process that
# would be hardest to suspect.
#
# $(notdir ...) BECAUSE THE RULE TARGETS ARE BARE NAMES.  The .c.o suffix rule
# and every explicit rule below name "foo.o", not "$(GPLSRC)foo.o", so the
# dependency has to be stated against the bare name or it attaches to a target
# that does not exist.
TEMPSRCS := $(notdir $(wildcard $(GPLSRC)*.c))
# 20 Aug 26 - was $(TEMPSRCS:sdclient.c=).  gplsrc/sdclient.c is deleted, so
# the wildcard no longer finds it and the strip had nothing left to strip.
# gplsrc/sdclient.h STAYS and is not the same question - op_tio.c takes
# SV_PROMPT, SrvrRespond and SrvrEndCommand from it.  PROJECT_STATUS.md 7.
SRCS     := $(TEMPSRCS)
OBJS     := $(SRCS:.c=.o)
DIROBJS  := $(addprefix $(GPLOBJ),$(OBJS))
	
sd: ARCH :=
sd: BITSIZE := 64
# rev 0.9.0 python
# 13 Aug 26 Windows port - dropped -DLINUX (never tested for in the source) and
#           -fPIE (position independent code is the default and the flag is
#           ignored with a warning on this target).  Added the libsodium
#           include path now that it lives under /usr/local.
sd: C_FLAGS  :=  -std=gnu17 -Wall -Wformat=2 -Wno-format-nonliteral -D_FILE_OFFSET_BITS=64 -I$(GPLSRC) -I$(SODIUM) -DGPL -g $(ARCH)
sd: $(SDOBJS) sdclilib sdsvc sdtic sdfix sdconv sdidx sdwind terminfo
	@echo Linking $@
	@cd $(GPLOBJ)
# 13 Aug 26 Windows port - libraries must follow the objects that reference
#           them.  The PE/COFF linker resolves strictly left to right, so the
#           original order left every libpython and libsodium symbol undefined.
#           On ELF this was masked by -Wl,--no-as-needed.
	@$(COMP) $(ARCH) $(SDOBJSD) $(L_FLAGS) -o $(GPLBIN)sd

# 13 Aug 26 Windows port - the client library is now the native Win32 DLL in
#           gplsrc/sdclilib, which has its own makefile and is compiled with
#           the UCRT64 toolchain rather than the MSYS2 runtime one used for
#           the server.  It talks to the server over a socket or a named pipe,
#           so the two never share an address space and the differing runtimes
#           do not meet.  Override UCRT_CC to build it with another compiler.
UCRT_CC  ?= /c/msys64/ucrt64/bin/gcc.exe
CLILIBDIR := $(GPLSRC)sdclilib

# 14 Aug 26 - the UCRT64 compiler's own directory MUST be on PATH, even though
# it is invoked by absolute path.  gcc.exe finds its DLLs beside itself, but
# the subprograms it spawns - cc1.exe, in ucrt64/lib/gcc/... - do not, and
# resolve their UCRT64 DLLs through PATH.  Without it gcc exits 1 with
# COMPLETELY EMPTY stdout and stderr, on a one-line program, so it reads as
# "the compiler is broken" rather than as a search-path problem.  Derived from
# UCRT_CC so that overriding the compiler moves this with it.
UCRT_BIN := $(dir $(UCRT_CC))

# Neither target names a file that make should test for.  Without this, VPATH
# finds the gplsrc/sdclilib directory (and the generated terminfo directory)
# and decides the target is already satisfied.
.PHONY: sdclilib sdsvc terminfo check-local check-remote check-api-admin

# 04 Sep 26 - ALL FOUR CLIENT DLLs, NOT ONE.  PRE_RELEASE_FIXES 161, the
# owner's ruling: "let's get rid of the client installers all together and just
# have sd build all four, the 32 bit ones stored in sd64\bin\client32 directory
# and the 64 bit ones stored in sd64\bin\client64".
#
# WHAT IT REPLACED, AND WHY THE OLD SHAPE COULD NOT HOLD.  One source produces
# five DLLs.  Until today this target built ONE of them and the other four were
# hand-built in two sibling trees; they were FIFTEEN DAYS STALE when it was
# measured, and the older copy won on PATH.  A build that cannot diverge beats
# a check that reports divergence.
#
# WHERE EACH PAIR LANDS, AND THE 64-BIT ONE LANDS TWICE ON PURPOSE.  Owner,
# 4 Sep 2026, in two steps:
#
#   "the 64 bit dlls should be in the usr\bin directory and only the 32 bit
#    dlls should be in client32 - they are never needed on the server as it is
#    64 bit, they are only provided for older utility programs that are 32 bit."
#
#   "it might be convenient for users if the 64 bit dlls were in both usr\bin
#    and a client64 directory ... a new directory usr\clients is created that
#    has client64 and client32 underneath it - that way users are not trying to
#    copy anything out of the usr\bin directory."
#
# So bin\ FLAT is the server's pair, which stage.py's PROGRAM_FILES_BIN copies
# into usr\bin beside sd.exe.  That copy is load-bearing rather than tidy:
# sdclilib.dll resolves sd.exe BESIDE ITSELF, so a copy anywhere else can do
# everything except connect locally.  bin\client64 and bin\client32 are the
# USER's copies and become usr\clients\ in the install - a directory nobody has
# to go rummaging in usr\bin to find.
sdclilib:
	@echo Building the four client DLLs
	@PATH="$(UCRT_BIN):$$PATH" $(MAKE) --no-print-directory -C $(CLILIBDIR) CC=$(UCRT_CC)
	@cp $(CLILIBDIR)/sdclilib.dll $(CLILIBDIR)/sdclient.dll $(GPLBIN)
	@cp $(CLILIBDIR)/libsdclilib.dll.a $(CLILIBDIR)/libsdclient.dll.a $(GPLBIN)
# 05 Sep 26 - THE 32-BIT PAIR GOES BESIDE sd.exe TOO.  Owner's ruling, 5 Sep
# 2026: "we need both the 32 bit and 64 bit dlls sitting next to the sd.exe
# file.  Some utilities that the admin may run are 32 bit apps."  This reverses
# the "THE 32-BIT PAIR HAS NO usr\bin COPY" note in stage.py, which reasoned
# from the SERVER never loading it - true, and not the question: usr\bin is on
# PATH, so it is where a 32-bit utility finds its client.  The names do not
# collide - qmclilib/qmclient against sdclilib/sdclient - so both live there.
	@cp $(CLILIBDIR)/qmclilib.dll $(CLILIBDIR)/qmclient.dll $(GPLBIN)
	@mkdir -p $(GPLBIN)client64 $(GPLBIN)client32
	@cp $(CLILIBDIR)/sdclilib.dll $(CLILIBDIR)/sdclient.dll $(GPLBIN)client64/
	@cp $(CLILIBDIR)/qmclilib.dll $(CLILIBDIR)/qmclient.dll $(GPLBIN)client32/
# 05 Sep 26 - AND THE IMPORT LIBRARIES GO WITH THE CLIENT COPIES, NOT INTO
# usr\bin.  PRE_RELEASE_FIXES 171.  An implib is a LINKER INPUT and is never
# loaded at runtime, so it has no business in the directory that goes on PATH;
# the one audience that needs it is somebody BUILDING a client, and the ruling
# above sends them to usr\clients.  They were in usr\bin and absent here, which
# is exactly backwards, and it read as a broken install.
	@cp $(CLILIBDIR)/libsdclilib.dll.a $(CLILIBDIR)/libsdclient.dll.a $(GPLBIN)client64/
	@cp $(CLILIBDIR)/libqmclilib.dll.a $(CLILIBDIR)/libqmclient.dll.a $(GPLBIN)client32/
# 04 Sep 26 - AND THE DIAGNOSTIC CLIENT, BESIDE THE DLL IT LOADS.  It is NOT
# shipped: stage.py's CLIENT_DIRS names the two DLLs explicitly, so an extra
# file here reaches no install.  verify-tierapi.ps1 and verify-doors.ps1 drive
# it, and it lives beside qmclilib.dll because Windows searches an executable's
# own directory first and nothing is on PATH any more.
	@cp $(CLILIBDIR)/sd-connect.exe $(GPLBIN)client32/
# Print what was produced rather than only that it succeeded - CLAUDE.md's
# instrument rule.  "file" names the architecture, which is the one property a
# 32-bit DLL under the right name can silently get wrong, and the failure it
# produces names nothing: "%1 is not a valid Win32 application".
	@echo "  bin (64-bit, the server's own, beside sd.exe):"
	@file $(GPLBIN)sdclilib.dll $(GPLBIN)sdclient.dll | sed 's|^.*/|    |'
	@echo "  bin/client64 (64-bit, the user's copy):"
	@file $(GPLBIN)client64/*.dll | sed 's|^.*/|    |'
	@echo "  bin/client32 (32-bit, for older utility programs):"
	@file $(GPLBIN)client32/*.dll | sed 's|^.*/|    |'

# 17 Aug 26 - REACHABLE FROM HERE, because reaching it the other way built the
# wrong thing.  "cd gplsrc/sdclilib && make check-local" was what this file's
# section 7 step 11 told people to run, and it compiles a NATIVE test with
# whatever CC that directory defaults to - which is the MSYS2 "cc", not the
# UCRT64 compiler the DLL is built with.  It failed to run and read as a broken
# transport.  Going through here passes CC the same way the sdclilib target
# does, so the test and the library are built by the same compiler.
#
# It measures the INSTALLED tree, so it is not part of "check" and it is subject
# to the test-cycle rule: run gplbld/assert-current.ps1 first, and UNELEVATED.
check-local:
	@PATH="$(UCRT_BIN):$$PATH" $(MAKE) --no-print-directory -C $(CLILIBDIR) CC=$(UCRT_CC) check-local

# 17 Aug 26 - APIHOST IS DEFAULTED HERE TOO, and it has to be.  The sub-make
# has its own "APIHOST ?= 127.0.0.1", but passing APIHOST="" on the command
# line OVERRIDES a "?=" default rather than leaving it alone - so without this
# the test was handed an empty host and answered "Invalid host name", which
# reads as a broken listener.  Measured 17 Aug 2026.
APIHOST ?= 127.0.0.1

# 17 Aug 26 - AND THE REMOTE ONE, for the same reason and by the same route.
# It needs arguments, which pass straight through; gplbld/verify-apiport.ps1
# is the one command that sets the system up and supplies them.
check-remote:
	@PATH="$(UCRT_BIN):$$PATH" $(MAKE) --no-print-directory -C $(CLILIBDIR) CC=$(UCRT_CC) \
	  APIHOST="$(APIHOST)" APIPORT="$(APIPORT)" APIUSER="$(APIUSER)" \
	  APIPASS="$(APIPASS)" APIACCT="$(APIACCT)" check-remote

# 20 Aug 26 - reachable from here for the same reason check-remote is: the sub-
# make must be handed the UCRT64 compiler, or the probe is built by the MSYS2
# "cc" and does not match the DLL it links against.  APICMD carries the command
# the API session is asked to run; gplbld/verify-apiadmin.ps1 supplies it.
check-api-admin:
	@PATH="$(UCRT_BIN):$$PATH" $(MAKE) --no-print-directory -C $(CLILIBDIR) CC=$(UCRT_CC) \
	  APIHOST="$(APIHOST)" APIPORT="$(APIPORT)" APIUSER="$(APIUSER)" \
	  APIPASS="$(APIPASS)" APIACCT="$(APIACCT)" APICMD="$(APICMD)" check-api-admin

# 15 Aug 26 - THE SERVICE IS NATIVE, AND ON PURPOSE.  A Windows service has to
# call StartServiceCtrlDispatcher, and sd.exe is built against the MSYS2 POSIX
# runtime where linuxlb.c records the decision to keep windows.h out.  So the
# service wrapper is built with the UCRT64 compiler like the client DLL, and
# never sees the POSIX runtime.  See gplsrc/sdsvc/sdsvc.c and 5.3.
#
# It lives in its own directory because SRCS is $(wildcard *.c) over gplsrc,
# which would otherwise compile this with the POSIX flags and fail.
SVCDIR   := $(GPLSRC)sdsvc

sdsvc:
	@echo Building native service wrapper
	@PATH="$(UCRT_BIN):$$PATH" $(UCRT_CC) -std=gnu17 -Wall -Wformat=2 -O2 \
	    $(SVCDIR)/sdsvc.c -ladvapi32 -o $(GPLBIN)sdsvc.exe

sdtic: sdtic.o inipath.o
	@echo Linking $@
	@$(COMP) $(C_FLAGS) -lc $(GPLOBJ)sdtic.o $(GPLOBJ)inipath.o -o $(GPLBIN)sdtic

sdfix: sdfix.o ctype.o linuxlb.o dh_hash.o inipath.o
	@echo Linking $@
	@$(COMP) $(C_FLAGS) -lc $(GPLOBJ)sdfix.o $(GPLOBJ)ctype.o $(GPLOBJ)linuxlb.o $(GPLOBJ)dh_hash.o $(GPLOBJ)inipath.o -o $(GPLBIN)sdfix

sdconv: sdconv.o ctype.o linuxlb.o dh_hash.o
	@echo Linking $@
	@$(COMP) $(C_FLAGS) -lc $(GPLOBJ)sdconv.o $(GPLOBJ)ctype.o $(GPLOBJ)linuxlb.o $(GPLOBJ)dh_hash.o -o $(GPLBIN)sdconv

sdidx: sdidx.o
	@echo Linking $@
	@$(COMP) $(C_FLAGS) -lc $(GPLOBJ)sdidx.o -o $(GPLBIN)sdidx

# 14 Aug 26 Windows port - renamed from sdlnxd, and exepath.o added: the daemon
#           launches "sd -cleanup" and has to find it beside itself rather than
#           under <sysdir>/bin, which holds no executables.
# 20 Aug 26 - win32peer.o and -liphlpapi: the daemon identifies the process at
#           the other end of an API connection.  GetExtendedTcpTable lives in
#           iphlpapi, which mingw does not link by default; the OpenProcess and
#           LookupAccountSid half of that file is covered by the -ladvapi32
#           already here for win32sem.o.
sdwind: sdwind.o sdsem.o win32sem.o win32peer.o exepath.o
	@echo Linking $@
	@$(COMP) $(C_FLAGS) -lc $(GPLOBJ)sdwind.o $(GPLOBJ)sdsem.o $(GPLOBJ)win32sem.o $(GPLOBJ)win32peer.o $(GPLOBJ)exepath.o -ladvapi32 -liphlpapi -o $(GPLBIN)sdwind

terminfo:
	@echo Compiling terminfo library
	@rm -Rf $(TERMINFO)
	@mkdir $(TERMINFO)
	@$(GPLBIN)sdtic -pterminfo $(MAIN)terminfo.src


# We need to make sure that anything that includes revstamp.h gets built if revstamp.h
# changes.

config.o: config.c config.h sd.h revstamp.h
	@$(COMP) $(C_FLAGS) -c $< -o $(GPLOBJ)config.o

kernel.o: kernel.c sd.h revstamp.h header.h tio.h debug.h keys.h syscom.h config.h \
	options.h dh_int.h locks.h
	@$(COMP) $(C_FLAGS) -c $< -o $(GPLOBJ)kernel.o


op_kernel.o: op_kernel.c sd.h revstamp.h header.h tio.h debug.h keys.h syscom.h \
	config.h options.h dh_int.h locks.h
	@$(COMP) $(C_FLAGS) -c $< -o $(GPLOBJ)op_kernel.o

op_sys.o: op_sys.c sd.h header.h tio.h syscom.h dh_int.h revstamp.h config.h
	@$(COMP) $(C_FLAGS) -c $< -o $(GPLOBJ)op_sys.o

pdump.o: pdump.c sd.h header.h syscom.h config.h revstamp.h locks.h dh_int.h
	@$(COMP) $(C_FLAGS) -c $< -o $(GPLOBJ)pdump.o

sd.o:	sd.c sd.h revstamp.h header.h debug.h dh_int.h tio.h config.h options.h \
locks.h
	@$(COMP) $(C_FLAGS) -c $< -o $(GPLOBJ)sd.o
	
sdconv.o: sdconv.c sd.h dh_int.h header.h revstamp.h
	@$(COMP) $(C_FLAGS) -c $< -o $(GPLOBJ)sdconv.o

sdfix.o: sdfix.c sd.h dh_int.h revstamp.h
	@$(COMP) $(C_FLAGS) -c $< -o $(GPLOBJ)sdfix.o

sdidx.o: sdidx.c sd.h dh_int.h revstamp.h
	@$(COMP) $(C_FLAGS) -c $< -o $(GPLOBJ)sdidx.o

sdtic.o: sdtic.c ti_names.h revstamp.h
	@$(COMP) $(C_FLAGS) -c $< -o $(GPLOBJ)sdtic.o

sysdump.o: sysdump.c sd.h locks.h revstamp.h config.h
	@$(COMP) $(C_FLAGS) -c $< -o $(GPLOBJ)sysdump.o

sysseg.o: sysseg.c sd.h locks.h config.h revstamp.h
	@$(COMP) $(C_FLAGS) -c $< -o $(GPLOBJ)sysseg.o

# 21 Aug 26 Windows port - EVERY OBJECT DEPENDS ON EVERY HEADER.  See the note
# on SDHDRS at the top: without this, the suffix rule below gives an object its
# own .c and nothing else, and a struct change in a header silently produces a
# binary whose translation units disagree about the layout.
#
# These lines carry NO RECIPE, so they only ADD prerequisites - the twelve
# explicit rules above keep theirs and keep their recipes, and everything else
# still builds through .c.o.  BOTH LISTS ARE NEEDED: SDOBJS is what sd itself
# is made of, and OBJS is every .c in gplsrc, which is where sdwind, sdtic and
# win32peer come from - none of those is in gpl.src.  OBJS was empty until
# 21 Aug 26; see the note on TEMPSRCS.
$(SDOBJS): $(SDHDRS)
$(OBJS): $(SDHDRS)

.c.o:
	@echo Compiling $@, $(BITSIZE) bit target.
	@$(COMP) $(C_FLAGS) -c $< -o $(GPLOBJ)$@
	
