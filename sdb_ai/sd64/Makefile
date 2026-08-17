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
L_FLAGS    := -lm -lcrypt -ldl -lbsd -L$(LIBSODIUM) -lsodium -ladvapi32

RM       := rm

SDHDRS   := $(wildcard *.h)
SDSRCS   := $(shell cat $(GPLDOTSRC))
SDTEMP   := $(addsuffix .o,$(SDSRCS))
SDOBJS   := $(SDTEMP)
SDOBJSD  := $(addprefix $(GPLOBJ),$(SDTEMP))
TEMPSRCS := $(wildcard *.c)
SRCS     := $(TEMPSRCS:sdclient.c=)
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
.PHONY: sdclilib sdsvc terminfo check-local check-remote

sdclilib:
	@echo Building native client DLL
	@PATH="$(UCRT_BIN):$$PATH" $(MAKE) --no-print-directory -C $(CLILIBDIR) CC=$(UCRT_CC)
	@cp $(CLILIBDIR)/sdclilib.dll $(GPLBIN)
	@cp $(CLILIBDIR)/libsdclilib.dll.a $(GPLBIN)

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
sdwind: sdwind.o sdsem.o win32sem.o exepath.o
	@echo Linking $@
	@$(COMP) $(C_FLAGS) -lc $(GPLOBJ)sdwind.o $(GPLOBJ)sdsem.o $(GPLOBJ)win32sem.o $(GPLOBJ)exepath.o -ladvapi32 -o $(GPLBIN)sdwind

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
	
sdclient.o: sdclient.c sddefs.h revstamp.h sdclient.h err.h
	@$(COMP) $(C_FLAGS) -c $< -o $(GPLOBJ)sdclient.o

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

.c.o:
	@echo Compiling $@, $(BITSIZE) bit target.
	@$(COMP) $(C_FLAGS) -c $< -o $(GPLOBJ)$@
	
