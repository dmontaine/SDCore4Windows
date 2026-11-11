/* win32jobmark.c
 * The Windows half of the scheduled-job mark (S.102 stage 3): the process token, and the administrator-only test of a definition.
 * Copyright (c) 2026 The SD Developers, All Rights Reserved
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
 * 10 Nov 26 Windows port - written for Linux 5162a5d1 (S.102 stage 3), carry area 14.
 * END-HISTORY
 *
 * START-DESCRIPTION:
 *
 * WHAT STANDS IN FOR LINUX'S CGROUP.  On Linux a job is a process systemd put into the cgroup sdcore-job-<name>.service, which only root can
 * enter.  Windows has no such place; what Task Scheduler gives a task it runs "whether the user is logged on or not" is a LOGON: the task's
 * principal, logged on as a batch logon (the token carries the BATCH group, S-1-5-3), elevated when the task asks for the highest run level.
 * win32_job_token_ok() answers 1 only for a token that is:
 *   - the LOCAL Windows account SDSYS (by SID, looked up as <this computer>\SDSYS, so a domain account of the same name is not it);
 *   - a batch logon (BATCH enabled) and neither a network logon (NETWORK) nor an interactive one (INTERACTIVE);
 *   - elevated (BUILTIN\Administrators enabled - present but deny-only in a filtered token).
 * WHO CAN MAKE SUCH A TOKEN: Task Scheduler running a task registered by an administrator, or anyone who holds SDSYS's password or the
 * machine's administrator rights.  An ordinary SD user can make none of it.  WHAT IT DOES NOT PROVE: that Task Scheduler, rather than another
 * administrator's batch logon of SDSYS, started the process - a Windows administrator is already above SD, as root is on Linux.
 *
 * win32_job_admin_path() is the DACL reading of Linux's "owned by root, not writable by group or others, not a link": not a reparse point, of
 * the right kind, OWNED by SYSTEM or BUILTIN\Administrators, and a DACL that allows nobody else anything (a NULL DACL is everyone, so it fails).
 * The model is win32_private_to_user() in win32tls.c, with the running user taken OUT of the allowed set: the definitions are the
 * administrators' record and not SDSYS's own file.  Every failure answers 0.
 *
 * Includes no SD header, as the other win32 units (the prototypes are repeated below).
 *
 * END-DESCRIPTION
 */

#include <windows.h>
#include <aclapi.h>
#include <sddl.h>
#include <userenv.h>
#include <stdio.h>
#include <string.h>

/* Declared in sd_jobmark.h; repeated here so this file includes no SD header. */
int win32_job_token_ok(char *why, size_t whylen);
int win32_job_admin_path(const char *path, int want_dir);
int win32_job_dir(char *out, size_t outlen);

/* WHERE THE DEFINITIONS ARE: <the machine's ProgramData folder>\SD\sd-jobs, the installer's {commonappdata}\SD.  Named from the profile list in
   the registry (GetAllUsersProfileDirectory), NOT from sd.conf's place: GetConfigPath() follows SD_CONFIG and %ProgramData%, which whoever
   starts the process sets.  sd-jobs.ps1 names it the same way ([Environment]::GetFolderPath('CommonApplicationData')). */
int win32_job_dir(char *out, size_t outlen)
{
    char base[MAX_PATH];
    DWORD blen = sizeof(base);
    int k;
    size_t i;

    if (!GetAllUsersProfileDirectoryA(base, &blen) || base[0] == '\0') return 0;
    k = snprintf(out, outlen, "%s/SD/sd-jobs", base);
    if (k <= 0 || (size_t)k >= outlen) return 0;
    for (i = 0; out[i] != '\0'; i++)
        if (out[i] == '\\') out[i] = '/';
    return 1;
}

static int member(WELL_KNOWN_SID_TYPE type, int *answer)
{
    BYTE buf[SECURITY_MAX_SID_SIZE];
    DWORD len = sizeof(buf);
    BOOL is = FALSE;

    if (!CreateWellKnownSid(type, NULL, buf, &len)) return 0;
    if (!CheckTokenMembership(NULL, buf, &is)) return 0;   /* NULL: this thread's token, or a copy of the process's primary token */
    *answer = is ? 1 : 0;
    return 1;
}

int win32_job_token_ok(char *why, size_t whylen)
{
    HANDLE tok = NULL;
    BYTE ubuf[256];
    DWORD got = 0;
    PSID user = NULL;
    char comp[MAX_COMPUTERNAME_LENGTH + 1];
    DWORD clen = sizeof(comp);
    char acct[MAX_COMPUTERNAME_LENGTH + 16];
    BYTE sbuf[SECURITY_MAX_SID_SIZE];
    DWORD slen = sizeof(sbuf);
    char dom[256];
    DWORD dlen = sizeof(dom);
    SID_NAME_USE use;
    int batch = 0, net = 0, inter = 0, admins = 0;

    if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &tok)) {
        snprintf(why, whylen, "cannot read the process token (error %lu)", (unsigned long)GetLastError());
        return 0;
    }
    if (GetTokenInformation(tok, TokenUser, ubuf, sizeof(ubuf), &got))
        user = ((TOKEN_USER *)ubuf)->User.Sid;
    CloseHandle(tok);
    if (user == NULL) {
        snprintf(why, whylen, "cannot read the process user");
        return 0;
    }

    if (!GetComputerNameA(comp, &clen)) {
        snprintf(why, whylen, "cannot read the computer name (error %lu)", (unsigned long)GetLastError());
        return 0;
    }
    snprintf(acct, sizeof(acct), "%s\\SDSYS", comp);
    if (!LookupAccountNameA(NULL, acct, sbuf, &slen, dom, &dlen, &use) || use != SidTypeUser) {
        snprintf(why, whylen, "there is no local account %s", acct);
        return 0;
    }
    if (!EqualSid(user, (PSID)sbuf)) {
        snprintf(why, whylen, "the process is not the local account SDSYS");
        return 0;
    }

    if (!member(WinBatchSid, &batch) || !member(WinNetworkSid, &net) || !member(WinInteractiveSid, &inter)
        || !member(WinBuiltinAdministratorsSid, &admins)) {
        snprintf(why, whylen, "cannot test the token's groups (error %lu)", (unsigned long)GetLastError());
        return 0;
    }
    if (!batch || net || inter) {
        snprintf(why, whylen, "the process is not a batch logon (batch %d, network %d, interactive %d)", batch, net, inter);
        return 0;
    }
    if (!admins) {
        snprintf(why, whylen, "the process is not elevated");
        return 0;
    }
    return 1;
}

int win32_job_admin_path(const char *path, int want_dir)
{
    char native[1024];
    size_t n, i;
    DWORD attr, rc;
    PSID owner = NULL;
    PACL dacl = NULL;
    PSECURITY_DESCRIPTOR sd = NULL;
    WORD a;
    int ok;

    if (path == NULL || path[0] == '\0') return 0;
    n = strlen(path);
    if (n >= sizeof(native)) return 0;
    for (i = 0; i <= n; i++)
        native[i] = (path[i] == '/') ? '\\' : path[i];

    attr = GetFileAttributesA(native);
    if (attr == INVALID_FILE_ATTRIBUTES) return 0;
    if (attr & FILE_ATTRIBUTE_REPARSE_POINT) return 0;                /* a link or a junction */
    if (want_dir && !(attr & FILE_ATTRIBUTE_DIRECTORY)) return 0;
    if (!want_dir && (attr & FILE_ATTRIBUTE_DIRECTORY)) return 0;

    rc = GetNamedSecurityInfoA(native, SE_FILE_OBJECT, OWNER_SECURITY_INFORMATION | DACL_SECURITY_INFORMATION, &owner, NULL, &dacl, NULL, &sd);
    if (rc != ERROR_SUCCESS) return 0;
    if (owner == NULL || !(IsWellKnownSid(owner, WinLocalSystemSid) || IsWellKnownSid(owner, WinBuiltinAdministratorsSid))) {
        LocalFree(sd);
        return 0;
    }
    if (dacl == NULL) {                                              /* everyone, full control */
        LocalFree(sd);
        return 0;
    }
    ok = 1;
    for (a = 0; a < dacl->AceCount; a++) {
        ACE_HEADER *hdr;
        PSID sid;

        if (!GetAce(dacl, a, (LPVOID *)&hdr)) { ok = 0; break; }
        if (hdr->AceType == ACCESS_DENIED_ACE_TYPE) continue;       /* a deny only narrows access */
        if (hdr->AceFlags & INHERIT_ONLY_ACE) continue;              /* for what is made below; a file made there is tested itself */
        if (hdr->AceType != ACCESS_ALLOWED_ACE_TYPE) { ok = 0; break; }
        sid = (PSID)&((ACCESS_ALLOWED_ACE *)hdr)->SidStart;
        if (IsWellKnownSid(sid, WinLocalSystemSid) || IsWellKnownSid(sid, WinBuiltinAdministratorsSid)) continue;
        ok = 0;
        break;
    }
    LocalFree(sd);
    return ok;
}
