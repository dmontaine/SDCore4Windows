CC ?= gcc
CFLAGS ?= -O2 -std=c11 -Wall -Wextra -Wpedantic -Wno-unknown-pragmas
CPPFLAGS += -DBUILDING_SDCLILIB
LDLIBS += -lws2_32

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
