/* WIN32SDSYSASK.C
 * "ssh -t <user>@localhost sd-sdsys", sd.exe's half: the asker's end of the SD service's pipe (RELEASE_1.1 339).
 * Copyright (c) Donald Montaine
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 3, or (at your option)
 * any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * START-HISTORY:
 * 18 Nov 26 Windows port - written for RELEASE_1.1 339; win32sdsysask.h has the design and the wire.  NOT RUN: compiled and linked
 *           only.
 * END-HISTORY
 *
 * START-DESCRIPTION:
 *
 * windows.h and NO SD header, the rule every win32*.c file follows; the terminal is sd_sdsysask.c's.  As win32runin.c: the pipe's
 * OWNER must be LocalSystem (a non-administrator cannot make an object owned by SYSTEM, and the name is open to anybody while the
 * service is down), and the asker offers only SECURITY_IDENTIFICATION, so the service can learn who asks and cannot act as them.
 * The pipe is not overlapped; reads are asked with PeekNamedPipe first, so the relay never waits on the service.
 *
 * END-DESCRIPTION
 *
 * START-CODE
 */

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <aclapi.h>
#include <stdio.h>
#include <string.h>

#include "win32localsdsys.h"
#include "win32sdsysask.h"

#define SDASK_PIPE_ACCESS (FILE_READ_DATA | FILE_WRITE_DATA | READ_CONTROL | SYNCHRONIZE)
#define SDASK_ANSWER_MS 60000 /* the service asks every question, logs SDSYS on and starts it before it answers */

static HANDLE sdask_pipe = INVALID_HANDLE_VALUE;

static void say(char* why, int whylen, const char* text) {
  if ((why != NULL) && (whylen > 0))
    snprintf(why, (size_t)whylen, "%s", text);
}

static BOOL sdask_owner_is_system(HANDLE h) {
  PSID owner = NULL;
  PSECURITY_DESCRIPTOR sd = NULL;
  BOOL is_system = FALSE;

  if (GetSecurityInfo(h, SE_KERNEL_OBJECT, OWNER_SECURITY_INFORMATION, &owner, NULL, NULL, NULL, &sd) == ERROR_SUCCESS)
    is_system = (owner != NULL) && IsWellKnownSid(owner, WinLocalSystemSid);
  if (sd != NULL)
    LocalFree(sd);
  return is_system;
}

static int sdask_write_all(const char* buf, DWORD len) {
  DWORD n;

  while (len > 0) {
    n = 0;
    if (!WriteFile(sdask_pipe, buf, len, &n, NULL) || (n == 0))
      return -1;
    buf += n;
    len -= n;
  }
  return 0;
}

int sdask_open(const char* request, char* answer, int alen) {
  HANDLE h;
  DWORD mode = PIPE_READMODE_BYTE;
  DWORD n = 0;
  DWORD waited = 0;
  DWORD avail;
  int len;
  int got = 0;
  char line[SDASK_ANSWER_MAX];
  char c;

  say(answer, alen, "");
  if (sdask_pipe != INVALID_HANDLE_VALUE) {
    say(answer, alen, "a session is already open");
    return -1;
  }
  len = (request == NULL) ? 0 : (int)strlen(request);
  if ((len == 0) || (len >= SDASK_LINE_MAX) || (request[len - 1] != '\n')) {
    say(answer, alen, "the request is not one line");
    return -1;
  }

  h = CreateFileA(SDL_PIPE, SDASK_PIPE_ACCESS, 0, NULL, OPEN_EXISTING, SECURITY_SQOS_PRESENT | SECURITY_IDENTIFICATION, NULL);
  if (h == INVALID_HANDLE_VALUE) {
    if (GetLastError() == ERROR_PIPE_BUSY)
      say(answer, alen, "the SD service is serving as many sd-sdsys sessions as it takes; try again when one ends");
    else if (GetLastError() == ERROR_ACCESS_DENIED)
      say(answer, alen, "the SD service's sd-sdsys door refused this login (only SD users may ask)");
    else
      snprintf(answer, (size_t)alen, "the SD service's sd-sdsys door cannot be opened (error %lu): is the service running?",
               (unsigned long)GetLastError());
    return -1;
  }
  if (!sdask_owner_is_system(h)) {
    CloseHandle(h);
    say(answer, alen, "the sd-sdsys pipe is not the SD service's (its owner is not LocalSystem); nothing was sent");
    return -1;
  }
  (void)SetNamedPipeHandleState(h, &mode, NULL, NULL);
  sdask_pipe = h;

  if (sdask_write_all(request, (DWORD)len) != 0) {
    sdask_close();
    say(answer, alen, "the request could not be sent to the SD service");
    return -1;
  }

  /* The answer line, a byte at a time so that nothing of the session's screen after it is taken. */
  for (;;) {
    avail = 0;
    if (!PeekNamedPipe(h, NULL, 0, NULL, &avail, NULL)) {
      line[got] = '\0';
      sdask_close();
      /* A refusal whose newline did not arrive is still a refusal: the service closes the pipe right after it. */
      if (strncmp(line, SDASK_REFUSED, strlen(SDASK_REFUSED)) == 0) {
        say(answer, alen, line + strlen(SDASK_REFUSED));
        return 1;
      }
      say(answer, alen, "the SD service ended the session before it answered");
      return -1;
    }
    if (avail == 0) {
      if (waited >= SDASK_ANSWER_MS) {
        sdask_close();
        say(answer, alen, "the SD service did not answer");
        return -1;
      }
      SleepEx(20, FALSE); /* not Sleep(): linuxlb.c defines SD's own Sleep(), and kernel32's stub would clash at link (13 Nov 26) */
      waited += 20;
      continue;
    }
    if (!ReadFile(h, &c, 1, &n, NULL) || (n != 1)) {
      sdask_close();
      say(answer, alen, "the SD service's answer could not be read");
      return -1;
    }
    if (c == '\n')
      break;
    if ((unsigned char)c < 32 || (unsigned char)c >= 127)
      continue; /* the answer is printable ASCII; anything else is dropped, never printed */
    if (got + 1 >= (int)sizeof(line)) {
      sdask_close();
      say(answer, alen, "the SD service's answer is too long");
      return -1;
    }
    line[got++] = c;
  }
  line[got] = '\0';

  /* Anchored on the success wording, and refused on anything else. */
  if (strncmp(line, SDASK_STARTED, strlen(SDASK_STARTED)) == 0) {
    say(answer, alen, line + strlen(SDASK_STARTED));
    return 0;
  }
  sdask_close();
  if (strncmp(line, SDASK_REFUSED, strlen(SDASK_REFUSED)) == 0) {
    say(answer, alen, line + strlen(SDASK_REFUSED));
    return 1;
  }
  say(answer, alen, (line[0] == '\0') ? "the SD service gave an empty answer" : "the SD service gave an answer this sd.exe does not know");
  return -1;
}

int sdask_read(char* buf, int len) {
  DWORD avail = 0;
  DWORD n = 0;

  if (sdask_pipe == INVALID_HANDLE_VALUE)
    return -1;
  if (!PeekNamedPipe(sdask_pipe, NULL, 0, NULL, &avail, NULL))
    return -1; /* broken: the SDSYS process has ended and the service has closed the session */
  if (avail == 0)
    return 0;
  if (avail > (DWORD)len)
    avail = (DWORD)len;
  if (!ReadFile(sdask_pipe, buf, avail, &n, NULL))
    return -1;
  return (int)n;
}

int sdask_keys(const char* buf, int len) {
  char frame[3 + SDASK_KEYS_MAX];
  int chunk;

  if (sdask_pipe == INVALID_HANDLE_VALUE)
    return -1;
  while (len > 0) {
    chunk = (len > SDASK_KEYS_MAX) ? SDASK_KEYS_MAX : len;
    frame[0] = SDASK_FRAME_KEYS;
    frame[1] = (char)((chunk >> 8) & 0xFF);
    frame[2] = (char)(chunk & 0xFF);
    memcpy(frame + 3, buf, (size_t)chunk);
    if (sdask_write_all(frame, (DWORD)(3 + chunk)) != 0)
      return -1;
    buf += chunk;
    len -= chunk;
  }
  return 0;
}

int sdask_resize(int cols, int rows) {
  char frame[5];

  if (sdask_pipe == INVALID_HANDLE_VALUE)
    return -1;
  cols = sdask_clamp(cols, SDASK_MIN_COLS);
  rows = sdask_clamp(rows, SDASK_MIN_ROWS);
  frame[0] = SDASK_FRAME_SIZE;
  frame[1] = (char)((cols >> 8) & 0xFF);
  frame[2] = (char)(cols & 0xFF);
  frame[3] = (char)((rows >> 8) & 0xFF);
  frame[4] = (char)(rows & 0xFF);
  return sdask_write_all(frame, 5);
}

void sdask_close(void) {
  if (sdask_pipe != INVALID_HANDLE_VALUE)
    CloseHandle(sdask_pipe);
  sdask_pipe = INVALID_HANDLE_VALUE;
}

/* END-CODE */
