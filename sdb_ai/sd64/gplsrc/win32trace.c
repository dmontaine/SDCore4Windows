/* WIN32TRACE.C
 * The socket trace log, made owner-only (SET.SOCKET.MODE SKT$INFO.TRACE).
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
 * 17 Nov 26 Windows port - written, four-version audit round 1 (owner's answer 5a of 17 Nov: "carry it WITH the protection
 *           Linux gives the trace file").  Linux 400500c opens the log with open(..., O_CREAT | O_TRUNC | O_NOFOLLOW, 0600).
 *           Here a mode does nothing: MSYS2 mounts the drives noacl, so a file the POSIX runtime makes takes its folder's
 *           inherited DACL whatever the mode says.  So the log is made through Win32 with its DACL in place before a byte
 *           is written.
 * END-HISTORY
 *
 * START-DESCRIPTION:
 *
 * This file includes windows.h and NO SD header, as win32audit.c does and for the same reason.
 *
 * win32_trace_open(path) - the Windows form of Linux's 0600 and O_NOFOLLOW:
 *   - THE DACL IS PROTECTED (inheritance off) and names three: this process's own Windows user (the token's user SID,
 *     not OWNER RIGHTS - an elevated administrator's new files are owned by the Administrators group), SYSTEM and the
 *     Administrators group, each with full control.  Linux's 0600 is the owner alone; root reads it anyway, and SYSTEM
 *     and Administrators are Windows' root.  Nobody else can open it.
 *   - A NEW FILE IS CREATED WITH THAT DACL (CreateFile's security attributes), so there is no moment when it has the
 *     folder's.  AN EXISTING FILE IS GIVEN IT before it is truncated - tighter than Linux, whose O_CREAT mode does not
 *     touch a file that is already there.  If the DACL cannot be set (a file this user may not re-permission) nothing is
 *     traced: the log is refused rather than written loose.
 *   - THE LAST NAME IS NOT FOLLOWED (FILE_FLAG_OPEN_REPARSE_POINT; Linux O_NOFOLLOW): a symbolic link, a junction or any
 *     other reparse point there is refused (ELOOP), and so is a directory (EISDIR); nothing is truncated first, because
 *     the file is opened with OPEN_ALWAYS and emptied only once it has passed.
 * The handle becomes a POSIX descriptor (cygwin_attach_handle_to_fd), so op_skt.c writes and closes it as Linux does.
 *
 * END-DESCRIPTION
 *
 * START-CODE
 */

#include <windows.h>
#include <aclapi.h>
#include <sddl.h>
#include <sys/cygwin.h>
#include <fcntl.h>
#include <errno.h>
#include <stdio.h>

#include "win32trace.h"

#define TRACE_WIN_PATH 1024

/* The SDDL of the log's DACL, for this process's own user.  Returns 0, or -1 with errno set. */

static int trace_sddl(char* sddl, size_t sddl_len) {
  HANDLE tok = NULL;
  BYTE buf[sizeof(TOKEN_USER) + SECURITY_MAX_SID_SIZE];
  DWORD got = 0;
  char* sid_text = NULL;
  int n;

  if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &tok)) {
    errno = EACCES;
    return -1;
  }
  if (!GetTokenInformation(tok, TokenUser, buf, sizeof(buf), &got)) {
    CloseHandle(tok);
    errno = EACCES;
    return -1;
  }
  CloseHandle(tok);
  if (!ConvertSidToStringSidA(((TOKEN_USER*)buf)->User.Sid, &sid_text)) {
    errno = EACCES;
    return -1;
  }
  n = snprintf(sddl, sddl_len, "D:P(A;;FA;;;%s)(A;;FA;;;SY)(A;;FA;;;BA)", sid_text);
  LocalFree(sid_text);
  if ((n < 0) || ((size_t)n >= sddl_len)) {
    errno = ENAMETOOLONG;
    return -1;
  }
  return 0;
}

/* ====================================================================== */

int win32_trace_open(const char* path) {
  char win[TRACE_WIN_PATH];
  char sddl[256];
  PSECURITY_DESCRIPTOR psd = NULL;
  PACL dacl = NULL;
  BOOL dacl_present = FALSE;
  BOOL dacl_defaulted = FALSE;
  SECURITY_ATTRIBUTES sa;
  BY_HANDLE_FILE_INFORMATION info;
  HANDLE h;
  DWORD created_err;
  int fd;

  if ((path == NULL) || (path[0] == '\0')) {
    errno = ENOENT;
    return -1;
  }
  if (cygwin_conv_path(CCP_POSIX_TO_WIN_A | CCP_ABSOLUTE, path, win, sizeof(win)) != 0)
    return -1; /* errno is set */
  if (trace_sddl(sddl, sizeof(sddl)) != 0)
    return -1;
  if (!ConvertStringSecurityDescriptorToSecurityDescriptorA(sddl, SDDL_REVISION_1, &psd, NULL)) {
    errno = EACCES;
    return -1;
  }
  if (!GetSecurityDescriptorDacl(psd, &dacl_present, &dacl, &dacl_defaulted) || !dacl_present || (dacl == NULL)) {
    LocalFree(psd);
    errno = EACCES;
    return -1;
  }

  sa.nLength = sizeof(sa);
  sa.lpSecurityDescriptor = psd;
  sa.bInheritHandle = FALSE;

  h = CreateFileA(win, GENERIC_WRITE | WRITE_DAC | READ_CONTROL, FILE_SHARE_READ, &sa, OPEN_ALWAYS,
                  FILE_ATTRIBUTE_NORMAL | FILE_FLAG_OPEN_REPARSE_POINT, NULL);
  created_err = GetLastError(); /* ERROR_ALREADY_EXISTS when OPEN_ALWAYS opened a file that was there */
  if (h == INVALID_HANDLE_VALUE) {
    LocalFree(psd);
    errno = (created_err == ERROR_ACCESS_DENIED) ? EACCES : ENOENT;
    return -1;
  }

  if (!GetFileInformationByHandle(h, &info)) {
    CloseHandle(h);
    LocalFree(psd);
    errno = EIO;
    return -1;
  }
  if (info.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT) {
    CloseHandle(h);
    LocalFree(psd);
    errno = ELOOP;
    return -1;
  }
  if (info.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) {
    CloseHandle(h);
    LocalFree(psd);
    errno = EISDIR;
    return -1;
  }

  /* A file that was there keeps its old DACL through CreateFile; give it the log's before anything is written. */
  if (created_err == ERROR_ALREADY_EXISTS) {
    if (SetSecurityInfo(h, SE_FILE_OBJECT, DACL_SECURITY_INFORMATION | PROTECTED_DACL_SECURITY_INFORMATION, NULL, NULL,
                        dacl, NULL) != ERROR_SUCCESS) {
      CloseHandle(h);
      LocalFree(psd);
      errno = EACCES;
      return -1;
    }
  }
  LocalFree(psd);

  /* Linux's O_TRUNC, once the file has passed. */
  if ((SetFilePointer(h, 0, NULL, FILE_BEGIN) == INVALID_SET_FILE_POINTER) || !SetEndOfFile(h)) {
    CloseHandle(h);
    errno = EIO;
    return -1;
  }

  fd = cygwin_attach_handle_to_fd((char*)path, -1, h, O_BINARY, GENERIC_WRITE);
  if (fd < 0) {
    CloseHandle(h);
    if (errno == 0)
      errno = EMFILE;
    return -1;
  }
  return fd;
}

/* END-CODE */
