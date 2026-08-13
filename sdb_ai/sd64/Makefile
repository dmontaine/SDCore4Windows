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

# rev 0.9.0 python header and libsodium headers 
# using python3-config to hopefully make building python version independent

PY_HDRS   := $(shell python3-config --includes)
PY_LDFLAGS := $(shell python3-config --ldflags --embed)

# 13 Aug 26 Windows port - libsodium is not packaged for the MSYS2 runtime and
#           is built from source into /usr/local.
SODIUM   := /usr/local/include
LIBSODIUM := /usr/local/lib

COMP     := gcc
# rev 0.9.0 python
# 13 Aug 26 Windows port - dropped -Wl,--no-as-needed, which is ELF only and
#           is rejected by the PE/COFF linker.
L_FLAGS    := -lm -lcrypt -ldl -lbsd -L$(LIBSODIUM) -lsodium $(PY_LDFLAGS)

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
sd: C_FLAGS  :=  -std=gnu17 -Wall -Wformat=2 -Wno-format-nonliteral -D_FILE_OFFSET_BITS=64 -I$(GPLSRC) -I$(SODIUM) $(PY_HDRS) -DEMBED_PYTHON -DGPL -g $(ARCH)
sd: $(SDOBJS) sdclilib.so sdtic sdfix sdconv sdidx sdlnxd terminfo
	@echo Linking $@
	@cd $(GPLOBJ)
# 13 Aug 26 Windows port - libraries must follow the objects that reference
#           them.  The PE/COFF linker resolves strictly left to right, so the
#           original order left every libpython and libsodium symbol undefined.
#           On ELF this was masked by -Wl,--no-as-needed.
	@$(COMP) $(ARCH) $(SDOBJSD) $(L_FLAGS) -o $(GPLBIN)sd

# 13 Aug 26 Windows port - -soname is an ELF concept with no PE/COFF
#           equivalent; the import library takes its place.
sdclilib.so: sdclilib.o
	@echo Linking $@
	@$(COMP) -shared $(ARCH) $(GPLOBJ)sdclilib.o $(GPLOBJ)linuxlb.o -o $(GPLBIN)sdclilib.so -Wl,--out-implib,$(GPLBIN)libsdclilib.dll.a
	@$(COMP) -shared $(ARCH) $(GPLOBJ)sdclilib.o $(GPLOBJ)linuxlb.o -o $(GPLBIN)libsdcli.so -Wl,--out-implib,$(GPLBIN)libsdcli.dll.a

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

sdlnxd: sdlnxd.o sdsem.o
	@echo Linking $@
	@$(COMP) $(C_FLAGS) -lc $(GPLOBJ)sdlnxd.o $(GPLOBJ)sdsem.o -o $(GPLBIN)sdlnxd	

terminfo:
	@echo Compiling terminfo library
	@rm -Rf $(TERMINFO)
	@mkdir $(TERMINFO)
	@$(GPLBIN)sdtic -pterminfo $(MAIN)terminfo.src

sdclilib.o: sdclilib.c revstamp.h
	@echo Compiling $@ with -fPIC
	@$(COMP) $(C_FLAGS) -fPIC -c $(GPLSRC)sdclilib.c -o $(GPLOBJ)sdclilib.o

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
	
