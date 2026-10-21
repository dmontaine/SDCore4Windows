/* SD_KEYRING.C
 * The process-held key ring and the XE conversion (encryption layer 3)
 * Copyright (c) 2026 SD Core for Linux
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
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software Foundation,
 * Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
 *
 * START-HISTORY:
 * 18 Oct 26 dm  Written: encryption layer 3 (.claude/plan-encryption-layers.md).
 * END-HISTORY
 *
 * START-DESCRIPTION:
 *
 * A dictionary item (or any program) names a key in its conversion, XE or XE;name, and never holds one.  The keys live here, in
 * this process only:
 *
 *   kr_set(name, key)    put a 256 bit key (base64, as SDKEY() and SDRANDKEY() make it) in the ring under a name; the newest key
 *                        of a name is the one new values are encrypted with, older ones of the same name stay for reading
 *                        (a key can be changed without losing the values written under the old one)
 *   kr_clear(name)       take the keys of a name out, or all of them ("*")
 *   kr_wipe()            take them all out and give the memory back (LOGTO, a change of account, the end of the process)
 *   xe_oconv(p)          OCONV code XE{;name}: the stored value is decrypted
 *   xe_iconv(p)          ICONV code XE{;name}: the value is encrypted
 *
 * THE RING.  One block from sodium_malloc(): guard pages round it, it is locked into memory (never swapped), left out of a core
 * dump, and PROTECTED AGAINST ALL ACCESS between uses (sodium_mprotect_noaccess), so that a stray read of this process's memory
 * by its own code finds a fault and not a key.  It is zeroed when it is released.  It belongs to the process: a phantom is a new
 * process (fork then exec) and starts with an empty ring, and nothing writes a key to a file, the audit trail, the errlog or
 * $COMO.  The caller's own variables, and the SD strings that carried a key to us, are the caller's; what this file holds it wipes.
 *
 * THE VALUE.  Encrypted, a value is a printable string with no mark character in it: base64 of
 *
 *    version (1 byte, 1) | key id (4 bytes: the first four of SHA-256 of the key) | nonce (24 bytes) | secretbox (16 byte tag, then
 *    the encrypted bytes)
 *
 * crypto_secretbox_easy with a fresh random nonce each time, so the same plaintext never gives the same value twice.  The key id
 * is not secret and is not authenticated: it picks the key, and a changed id gives "wrong key", never a wrong decryption, because
 * the tag is checked.  A null string is not encrypted: it stays null in both directions, so that an empty field is still empty
 * (and so tells an observer that it is).
 *
 * STATUS, left in process.status by the conversions (STATUS() shows it without the sign):
 *    0       done
 *    10208   no key of that name in the ring: OCONV leaves the stored value as it is, ICONV answers the null string (plaintext
 *            is never the answer of an encrypting conversion)
 *    10209   the name has keys but none of them made this value: the stored value is left as it is
 *    10210   the value is not an encrypted value of this format: left as it is
 *    10212   the tag does not check: the value has been changed or damaged: left as it is
 *    10200   the value is too long to encrypt (ICONV)
 *    2       the conversion code is not XE or XE;name with a valid name (the usual "bad conversion" of OCONV / ICONV)
 *
 * END-DESCRIPTION
 *
 * START-CODE
 */

#include "sd.h"
#include <stdlib.h>
#include <stdio.h>
#include <ctype.h>
#include <string.h>
#include <sodium.h>

#include "keys.h"

#define KR_MAX 16                                  /* keys in the ring */
#define KR_NAME_MAX 31                             /* characters of a key name */
#define KR_KEYBYTES crypto_secretbox_KEYBYTES      /* 32 */
#define KR_NONCEBYTES crypto_secretbox_NONCEBYTES  /* 24 */
#define KR_MACBYTES crypto_secretbox_MACBYTES      /* 16 */
#define KR_VERSION 1
#define KR_IDBYTES 4
#define KR_HDRBYTES (1 + KR_IDBYTES + KR_NONCEBYTES)   /* before the secretbox: 29 */
#define KR_DEFAULT_NAME "default"
#define KR_KEY_B64_CHARS 44                        /* a 32 byte key as base64 */

typedef struct {
  char name[KR_NAME_MAX + 1];
  unsigned char id[KR_IDBYTES];
  unsigned char key[KR_KEYBYTES];
  unsigned int seq;                                /* the larger, the newer */
  unsigned char used;
} KR_ENTRY;

typedef struct {
  KR_ENTRY e[KR_MAX];
  unsigned int next_seq;
} KR_RING;

Private KR_RING* ring = NULL;
Private bool exit_hook_set = FALSE;

int kr_set(const char* name, const char* keyb64, char* idhex);
int kr_clear(const char* name, int* removed);
void kr_wipe(void);
int kr_list(char* out, size_t out_sz);
int32_t xe_oconv(char* p);
int32_t xe_iconv(char* p);

Private int kr_name(const char* in, char* out);
Private KR_RING* ring_open(bool create);
Private void ring_close(void);
Private void key_id(const unsigned char* key, unsigned char* id);
Private int source_copy(DESCRIPTOR* d, unsigned char** buf, size_t* len, bool secret);

/* ======================================================================
   kr_name()  -  a key name, folded to lower case.  1 to 31 of a-z 0-9 . - _
   Returns 0 and the name in out (KR_NAME_MAX + 1 bytes), or SD_KeyName_Err.   */

Private int kr_name(const char* in, char* out) {
  size_t n = 0;

  if (in == NULL || in[0] == '\0')
    in = KR_DEFAULT_NAME;
  for (; in[n] != '\0'; n++) {
    unsigned char c = (unsigned char)in[n];

    if (n >= KR_NAME_MAX)
      return SD_KeyName_Err;
    if (c >= 'A' && c <= 'Z')
      c = (unsigned char)(c - 'A' + 'a');
    if (!((c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '.' || c == '-' || c == '_'))
      return SD_KeyName_Err;
    out[n] = (char)c;
  }
  out[n] = '\0';
  return 0;
}

/* ======================================================================
   ring_open() / ring_close()  -  the ring is unreadable except between these two  */

Private KR_RING* ring_open(bool create) {
  if (ring == NULL) {
    if (!create)
      return NULL;
    if (sodium_init() == -1)
      return NULL;
    ring = (KR_RING*)sodium_malloc(sizeof(KR_RING));
    if (ring == NULL)
      return NULL;
    sodium_memzero(ring, sizeof(KR_RING));   /* sodium_malloc() fills with a pattern, not zeros */
    if (!exit_hook_set) {
      atexit(kr_wipe);
      exit_hook_set = TRUE;
    }
    return ring;
  }
  sodium_mprotect_readwrite(ring);
  return ring;
}

Private void ring_close(void) {
  if (ring != NULL)
    sodium_mprotect_noaccess(ring);
}

/* ======================================================================
   key_id()  -  the first four bytes of the SHA-256 of the key                    */

Private void key_id(const unsigned char* key, unsigned char* id) {
  unsigned char h[crypto_hash_sha256_BYTES];

  crypto_hash_sha256(h, key, KR_KEYBYTES);
  memcpy(id, h, KR_IDBYTES);
  sodium_memzero(h, sizeof h);
}

/* ======================================================================
   kr_set()  -  put a key in the ring.  idhex (9 bytes) gets its key id as 8 hex digits.
   Returns 0, or SD_KeyName_Err, SD_KeyLen_Err (not 44 base64 characters for 32 bytes), SD_Decode_Err, SD_Ring_Err (full), SD_Mem_Err. */

int kr_set(const char* name_in, const char* keyb64, char* idhex) {
  char name[KR_NAME_MAX + 1];
  unsigned char key[KR_KEYBYTES];
  unsigned char id[KR_IDBYTES];
  size_t bin_len = 0;
  KR_RING* r;
  int i;
  int slot = -1;
  int rc;

  idhex[0] = '\0';
  if ((rc = kr_name(name_in, name)) != 0)
    return rc;
  if (keyb64 == NULL || strlen(keyb64) != KR_KEY_B64_CHARS)
    return SD_KeyLen_Err;
  if (sodium_init() == -1)
    return SD_SodInit_Err;
  if (sodium_base642bin(key, sizeof key, keyb64, KR_KEY_B64_CHARS, NULL, &bin_len, NULL, sodium_base64_VARIANT_ORIGINAL) != 0 ||
      bin_len != KR_KEYBYTES) {
    sodium_memzero(key, sizeof key);
    return SD_Decode_Err;
  }
  key_id(key, id);

  if ((r = ring_open(TRUE)) == NULL) {
    sodium_memzero(key, sizeof key);
    return SD_Mem_Err;
  }
  /* the same key under the same name again only makes it the newest */
  for (i = 0; i < KR_MAX; i++) {
    if (r->e[i].used && strcmp(r->e[i].name, name) == 0 && memcmp(r->e[i].id, id, KR_IDBYTES) == 0 &&
        sodium_memcmp(r->e[i].key, key, KR_KEYBYTES) == 0) {
      slot = i;
      break;
    }
  }
  if (slot < 0) {
    for (i = 0; i < KR_MAX; i++) {
      if (!r->e[i].used) {
        slot = i;
        break;
      }
    }
    if (slot < 0) {
      ring_close();
      sodium_memzero(key, sizeof key);
      return SD_Ring_Err;
    }
    r->e[slot].used = 1;
    strcpy(r->e[slot].name, name);
    memcpy(r->e[slot].id, id, KR_IDBYTES);
    memcpy(r->e[slot].key, key, KR_KEYBYTES);
  }
  r->e[slot].seq = ++r->next_seq;
  ring_close();
  sodium_memzero(key, sizeof key);
  sodium_bin2hex(idhex, 2 * KR_IDBYTES + 1, id, KR_IDBYTES);
  return 0;
}

/* ======================================================================
   kr_clear()  -  take the keys of a name out ("*" or NULL: all).  *removed is how many went.  Returns 0 or SD_KeyName_Err.      */

int kr_clear(const char* name_in, int* removed) {
  char name[KR_NAME_MAX + 1];
  KR_RING* r;
  int i;
  bool all = (name_in != NULL && strcmp(name_in, "*") == 0);

  *removed = 0;
  if (!all && kr_name(name_in, name) != 0)
    return SD_KeyName_Err;
  if ((r = ring_open(FALSE)) == NULL)
    return 0;
  for (i = 0; i < KR_MAX; i++) {
    if (r->e[i].used && (all || strcmp(r->e[i].name, name) == 0)) {
      sodium_memzero(&r->e[i], sizeof(KR_ENTRY));
      (*removed)++;
    }
  }
  ring_close();
  return 0;
}

/* ======================================================================
   kr_wipe()  -  everything out, memory given back.  Called at LOGTO and at the end of the process; safe to call twice.        */

void kr_wipe(void) {
  if (ring != NULL) {
    sodium_mprotect_readwrite(ring);
    sodium_memzero(ring, sizeof(KR_RING));
    sodium_free(ring);
    ring = NULL;
  }
}

/* ======================================================================
   kr_list()  -  one field per key into out: name, key id and 1 for the key new values use, value marks between, field marks
   between the keys, oldest first.  Returns the number of keys.  Never shows a key.                                           */

int kr_list(char* out, size_t out_sz) {
  KR_RING* r;
  int i, j, n = 0;
  size_t len = 0;
  unsigned int best_seq;
  int order[KR_MAX];

  out[0] = '\0';
  if ((r = ring_open(FALSE)) == NULL)
    return 0;
  for (i = 0; i < KR_MAX; i++)
    if (r->e[i].used)
      order[n++] = i;
  /* oldest first */
  for (i = 0; i < n; i++)
    for (j = i + 1; j < n; j++)
      if (r->e[order[j]].seq < r->e[order[i]].seq) {
        int t = order[i];
        order[i] = order[j];
        order[j] = t;
      }
  for (i = 0; i < n; i++) {
    KR_ENTRY* e = &r->e[order[i]];
    char idhex[2 * KR_IDBYTES + 1];
    int current = 1;
    int w;

    best_seq = e->seq;
    for (j = 0; j < KR_MAX; j++)
      if (r->e[j].used && strcmp(r->e[j].name, e->name) == 0 && r->e[j].seq > best_seq)
        current = 0;
    sodium_bin2hex(idhex, sizeof idhex, e->id, KR_IDBYTES);
    w = snprintf(out + len, out_sz - len, "%s%s\xFD%s\xFD%d", i ? "\xFE" : "", e->name, idhex, current);
    if (w < 0 || (size_t)w >= out_sz - len)
      break;
    len += (size_t)w;
  }
  ring_close();
  return n;
}

/* ======================================================================
   source_copy()  -  the value on top of the e-stack as one block of bytes.  secret: from sodium_malloc, else malloc.
   Returns 0 or SD_Mem_Err.  The caller frees it (sodium_free / free).                                                       */

Private int source_copy(DESCRIPTOR* d, unsigned char** buf, size_t* len, bool secret) {
  STRING_CHUNK* chunk;
  size_t n = 0;
  unsigned char* b;

  k_get_string(d);
  if (d->data.str.saddr != NULL)
    n = (size_t)d->data.str.saddr->string_len;
  b = secret ? (unsigned char*)sodium_malloc(n + 1) : (unsigned char*)malloc(n + 1);
  if (b == NULL)
    return SD_Mem_Err;
  n = 0;
  for (chunk = d->data.str.saddr; chunk != NULL; chunk = chunk->next) {
    if (chunk->bytes > 0) {
      memcpy(b + n, chunk->data, (size_t)chunk->bytes);
      n += (size_t)chunk->bytes;
    }
  }
  b[n] = '\0';
  *buf = b;
  *len = n;
  return 0;
}

/* ======================================================================
   conversion_name()  -  p is what follows XE in the code: nothing, or ;name.  Returns 0 or 2 (a bad conversion code).        */

Private int32_t conversion_name(const char* p, char* name) {
  if (p == NULL || p[0] == '\0')
    return kr_name(KR_DEFAULT_NAME, name);
  if (p[0] != ';')
    return 2;
  return (kr_name(p + 1, name) == 0) ? 0 : 2;
}

/* ======================================================================
   xe_oconv()  -  OCONV code XE{;name}: decrypt the value on top of the e-stack.  On any failure the value is left as it was.     */

int32_t xe_oconv(char* p) {
  char name[KR_NAME_MAX + 1];
  DESCRIPTOR* d = e_stack - 1;
  unsigned char* text = NULL;
  unsigned char* bin = NULL;
  unsigned char* plain = NULL;
  size_t len = 0, bin_len = 0, plain_len;
  const char* end = NULL;
  KR_RING* r;
  int i;
  int32_t status = 0;
  unsigned char id[KR_IDBYTES];

  if (conversion_name(p, name) != 0)
    return 2;

  if (source_copy(d, &text, &len, FALSE) != 0)
    return SD_Mem_Err;
  if (len == 0) {                       /* a null string stays null */
    free(text);
    return 0;
  }
  if (sodium_init() == -1) {
    free(text);
    return SD_SodInit_Err;
  }

  /* is it one of ours?  Printable base64 of at least a header and a tag, version 1 */
  bin = (unsigned char*)malloc(len + 1);
  if (bin == NULL) {
    free(text);
    return SD_Mem_Err;
  }
  if (sodium_base642bin(bin, len, (const char*)text, len, NULL, &bin_len, &end, sodium_base64_VARIANT_ORIGINAL) != 0 ||
      end != (const char*)text + len || bin_len < (size_t)(KR_HDRBYTES + KR_MACBYTES) || bin[0] != KR_VERSION) {
    status = SD_NotEnc_Err;
    goto done;
  }
  memcpy(id, bin + 1, KR_IDBYTES);

  if ((r = ring_open(FALSE)) == NULL) {
    status = SD_NoKey_Err;
    goto done;
  }
  status = SD_NoKey_Err;
  for (i = 0; i < KR_MAX; i++) {
    if (r->e[i].used && strcmp(r->e[i].name, name) == 0) {
      status = SD_KeyId_Err;       /* the name has a key; unless one of them made this value that is the answer */
      if (memcmp(r->e[i].id, id, KR_IDBYTES) == 0) {
        plain_len = bin_len - KR_HDRBYTES - KR_MACBYTES;
        plain = (unsigned char*)sodium_malloc(plain_len + 1);
        if (plain == NULL) {
          status = SD_Mem_Err;
          break;
        }
        if (crypto_secretbox_open_easy(plain, bin + KR_HDRBYTES, (unsigned long long)(bin_len - KR_HDRBYTES), bin + 1 + KR_IDBYTES,
                                       r->e[i].key) == 0) {
          status = 0;
          ring_close();
          k_dismiss();
          k_put_string((char*)plain, (int)plain_len, e_stack);
          e_stack++;
          sodium_free(plain);
          plain = NULL;
          free(bin);
          free(text);
          return 0;
        }
        sodium_free(plain);
        plain = NULL;
        status = SD_Damaged_Err;
        break;
      }
    }
  }
  ring_close();

done:
  free(bin);
  free(text);
  return status;
}

/* ======================================================================
   xe_iconv()  -  ICONV code XE{;name}: encrypt the value on top of the e-stack with the newest key of that name.
   With no key the answer is the null string and SD_NoKey_Err: the plaintext is never the answer.                              */

int32_t xe_iconv(char* p) {
  char name[KR_NAME_MAX + 1];
  DESCRIPTOR* d = e_stack - 1;
  unsigned char* plain = NULL;
  unsigned char* out = NULL;
  char* b64 = NULL;
  size_t len = 0, out_len, b64_sz;
  KR_RING* r;
  KR_ENTRY* cur = NULL;
  unsigned char nonce[KR_NONCEBYTES];
  unsigned char id[KR_IDBYTES];
  int i;
  int32_t status = 0;

  /* every failure below ends in "refuse": a conversion that is meant to encrypt never leaves the plaintext as its answer, not
     for a typing mistake in the code (XEfoo) and not for an allocation that failed.  sodium_init() comes first: sodium_malloc()
     asserts and kills the process when libsodium has not been started (see sd_xf_key in sd_encrypt_sodium.c). */
  if (sodium_init() == -1) {
    status = SD_SodInit_Err;
    goto refuse;
  }
  if (conversion_name(p, name) != 0) {
    status = 2;
    goto refuse;
  }
  if (source_copy(d, &plain, &len, TRUE) != 0) {
    status = SD_Mem_Err;
    goto refuse;
  }
  if (len == 0) {
    sodium_free(plain);
    return 0;
  }
  out_len = KR_HDRBYTES + KR_MACBYTES + len;
  b64_sz = sodium_base64_ENCODED_LEN(out_len, sodium_base64_VARIANT_ORIGINAL);
  if (b64_sz > MAX_STRING_SIZE) {
    sodium_free(plain);
    status = SD_Encrypt_Err;
    goto refuse;
  }

  if ((r = ring_open(FALSE)) == NULL) {
    sodium_free(plain);
    status = SD_NoKey_Err;
    goto refuse;
  }
  for (i = 0; i < KR_MAX; i++)
    if (r->e[i].used && strcmp(r->e[i].name, name) == 0 && (cur == NULL || r->e[i].seq > cur->seq))
      cur = &r->e[i];
  if (cur == NULL) {
    ring_close();
    sodium_free(plain);
    status = SD_NoKey_Err;
    goto refuse;
  }

  out = (unsigned char*)malloc(out_len);
  b64 = (char*)malloc(b64_sz);
  if (out == NULL || b64 == NULL) {
    ring_close();
    sodium_free(plain);
    free(out);
    free(b64);
    status = SD_Mem_Err;
    goto refuse;
  }
  randombytes_buf(nonce, sizeof nonce);
  memcpy(id, cur->id, KR_IDBYTES);
  out[0] = KR_VERSION;
  memcpy(out + 1, id, KR_IDBYTES);
  memcpy(out + 1 + KR_IDBYTES, nonce, KR_NONCEBYTES);
  if (crypto_secretbox_easy(out + KR_HDRBYTES, plain, (unsigned long long)len, nonce, cur->key) != 0) {
    ring_close();
    sodium_free(plain);
    free(out);
    free(b64);
    status = SD_Encrypt_Err;
    goto refuse;
  }
  ring_close();
  sodium_free(plain);   /* zeroes first */
  sodium_bin2base64(b64, b64_sz, out, out_len, sodium_base64_VARIANT_ORIGINAL);
  k_dismiss();
  k_put_c_string(b64, e_stack);
  e_stack++;
  free(out);
  free(b64);
  return 0;

refuse:
  /* the value is replaced by the null string: whatever the caller does with the answer, it is not the plaintext */
  k_dismiss();
  k_put_c_string("", e_stack);
  e_stack++;
  return status;
}
