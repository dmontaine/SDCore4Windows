/* sd_pin.c - first-use pinning of the server's TLS certificate.  See sd_pin.h
 * for the rules and for why they match the Linux client's.
 *
 * START-HISTORY:
 * 30 Sep 26 SD Core Solo - written, SOLO 24.
 * 14 Nov 26 SD Core for Windows - carried unchanged, RELEASE_1.1 297 (Linux S.236 brought Core to what Solo has).
 * END-HISTORY */

#include "sd_pin.h"

#include <direct.h>
#include <errno.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void say(char* errmsg, size_t errlen, const char* fmt, ...) {
  va_list ap;

  if (errmsg == NULL || errlen == 0)
    return;
  va_start(ap, fmt);
  vsnprintf(errmsg, errlen, fmt, ap);
  va_end(ap);
  errmsg[errlen - 1] = '\0';
}

static int is_hex64(const char* s) {
  size_t i;

  if (s == NULL || strlen(s) != SD_PIN_HEX_LEN)
    return 0;
  for (i = 0; i < SD_PIN_HEX_LEN; i++)
    if (!((s[i] >= '0' && s[i] <= '9') || (s[i] >= 'a' && s[i] <= 'f')))
      return 0;
  return 1;
}

/* $SD_KNOWN_SERVERS, else %USERPROFILE%\.sdcore\known_servers.  *own_dir is
   set to the directory this program may have to create (the default one only;
   a path the caller named is theirs to prepare). */
static int store_path(char* path, size_t n, char* dir, size_t dn, int* own_dir,
                      char* errmsg, size_t errlen) {
  const char* env = getenv("SD_KNOWN_SERVERS");
  const char* prof;

  *own_dir = 0;
  if (env != NULL && env[0] != '\0') {
    if (strlen(env) >= n) {
      say(errmsg, errlen, "cannot pin the server: the known-servers path is too long");
      return 0;
    }
    strcpy(path, env);
    return 1;
  }
  prof = getenv("USERPROFILE");
  if (prof == NULL || prof[0] == '\0') {
    say(errmsg, errlen,
        "cannot pin the server: no user profile folder to keep the known-servers file in");
    return 0;
  }
  if (strlen(prof) + 32 >= n || strlen(prof) + 16 >= dn) {
    say(errmsg, errlen, "cannot pin the server: the known-servers path is too long");
    return 0;
  }
  sprintf(dir, "%s\\.sdcore", prof);
  snprintf(path, n, "%.1000s\\known_servers", dir);   /* 14 Nov 26: bounded - the compiler (-Wformat-truncation) wanted it; strlen(dir) is under 1100 by the check above */
  *own_dir = 1;
  return 1;
}

int sd_pin_check(const char* host, int port, const char* hex64, char* errmsg,
                 size_t errlen) {
  char key[300];
  char path[1100];
  char dir[1100];
  char line[512];
  int own_dir = 0;
  int last_was_newline = 1;
  size_t i;
  FILE* f;

  if (host == NULL || host[0] == '\0' || strlen(host) > 200 || !is_hex64(hex64)) {
    say(errmsg, errlen, "cannot pin the server: no usable host name or certificate");
    return 0;
  }
  for (i = 0; host[i] != '\0'; i++)
    key[i] = (host[i] >= 'A' && host[i] <= 'Z') ? (char)(host[i] + 32) : host[i];
  sprintf(key + i, ":%d", port);

  if (!store_path(path, sizeof(path), dir, sizeof(dir), &own_dir, errmsg, errlen))
    return 0;

  f = fopen(path, "rb");
  if (f == NULL && errno != ENOENT) {
    say(errmsg, errlen, "cannot pin the server: cannot open %s: %s", path, strerror(errno));
    return 0;
  }
  if (f != NULL) {
    while (fgets(line, sizeof(line), f) != NULL) {
      size_t len = strlen(line);
      char* sp;

      last_was_newline = (len > 0 && line[len - 1] == '\n');
      while (len > 0 && (line[len - 1] == '\n' || line[len - 1] == '\r'))
        line[--len] = '\0';
      if (line[0] == '\0' || line[0] == '#')
        continue;
      sp = strchr(line, ' ');
      if (sp == NULL)
        continue;
      *sp++ = '\0';
      if (strcmp(line, key) != 0)
        continue;
      if (strcmp(sp, hex64) == 0) {
        fclose(f);
        return 1;
      }
      say(errmsg, errlen,
          "THE SERVER'S CERTIFICATE HAS CHANGED since this client first connected to %s "
          "(pinned %s, now %s). The connection was refused before any password was sent. "
          "If the server was reinstalled, remove the line for %s from %s and connect again",
          key, sp, hex64, key, path);
      fclose(f);
      return 0;
    }
    if (ferror(f)) {
      say(errmsg, errlen, "cannot pin the server: cannot read %s", path);
      fclose(f);
      return 0;
    }
    fclose(f);
  }

  /* First connection to this host:port: record it.  A store that cannot be
     written refuses - an unpinned connection is never the fallback. */
  if (own_dir && _mkdir(dir) != 0 && errno != EEXIST) {
    say(errmsg, errlen, "cannot pin the server: cannot open %s: %s", path, strerror(errno));
    return 0;
  }
  f = fopen(path, "ab");
  if (f == NULL) {
    say(errmsg, errlen, "cannot pin the server: cannot open %s: %s", path, strerror(errno));
    return 0;
  }
  if (!last_was_newline)
    fputc('\n', f);
  if (fprintf(f, "%s %s\n", key, hex64) < 0 || fflush(f) != 0) {
    say(errmsg, errlen, "cannot pin the server: cannot write %s: %s", path, strerror(errno));
    fclose(f);
    return 0;
  }
  fclose(f);
  return 1;
}
