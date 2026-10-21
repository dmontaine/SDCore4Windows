/* SD_ENCRYPT_SODIUM.C
 * Encypt / Decrypt using libsodium  - integration for SD
 * Copyright (c)2024 The SD Developers, All Rights Reserved
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
 * 
 * START-HISTORY:
 * 18 Oct 26 dm  Encryption layer 2: SDSALT(), SDKEY(passphrase, salt) and SDRANDKEY() for every program (sd_xf_salt, sd_xf_key,
 *               sd_xf_randkey, called from op_xfun()).  sd_derive_key() is the one place the key is made: argon2id with the limits
 *               written out (2 passes, 64 MiB), a salt that must decode to exactly 16 bytes (a short one used to leave the rest of
 *               the buffer as it was), the binary key and salt wiped.  sd_KeyFromPW() calls it, so SDEXT SD_KEYFROMPW gives the same
 *               key as before for a good salt.  sd_decrypt: the plaintext buffer allocated before sdme_decrypt() was lost when it
 *               was replaced (a leak per call), now freed; the decoded key is wiped.
 * 30 Jul 2024 MAB add SD_ENCRYPT_SODIUM.C
 * START-DESCRIPTION:
 * 
 *  Encryption, Decryptoin and encoding using libsodium package
 *  https://doc.libsodium.org/
 *  This routine is based on information (code) found here:
 *  https://doc.libsodium.org/secret-key_cryptography/secretbox
 *  https://github.com/jedisct1/libsodium/blob/master/test/default/secretbox_easy2.c
 *  https://doc.libsodium.org/password_hashing/default_phf
 * 
 *  we encrypt using crypto_secretbox_easy
 * 
 *  int crypto_secretbox_easy(unsigned char *c, const unsigned char *m,
 *                         unsigned long long mlen, const unsigned char *n,
 *                         const unsigned char *k)
 * 
 *  The crypto_secretbox_easy() function encrypts a message m whose length is mlen bytes, with a key k and a nonce n. 
 *   k should be crypto_secretbox_KEYBYTES bytes (currently defined as 32 bytes / 256 bits) and n should be crypto_secretbox_NONCEBYTES bytes.
 *   c should be at least crypto_secretbox_MACBYTES + mlen bytes long.
 *   This function writes the authentication tag, whose length is crypto_secretbox_MACBYTES bytes,
 *    in c, immediately followed by the encrypted message, whose length is the same as the plaintext: mlen.
 *  Functions returning an int return 0 on success and -1 to indicate an error.
 * 
 *  REM:
 *   An 256-bit key can be expressed as a hexadecimal string with 64 characters. It will require 44 characters in base64.
 * 
 *  Note we return the encrtption output with the nonce appended to the end
 *  Rem to encode either base64 or hex before returning to ScarletDME!
 * 
 * we decrypt using crypto_secretbox_open_easy
 * 
 *  int crypto_secretbox_open_easy(unsigned char *m, const unsigned char *c,
 *                              unsigned long long clen, const unsigned char *n,
 *                              const unsigned char *k);
 * 
 *  c is a pointer to an authentication tag + encrypted message combination,
 *    as produced by crypto_secretbox_easy().
 *  clen is the length of this authentication tag + encrypted message combination.
 *  Put differently, clen is the number of bytes written by crypto_secretbox_easy(),
 *    which is crypto_secretbox_MACBYTES + the length of the message.
 *  The nonce n and the key k have to match those used to encrypt and authenticate the message.
 *  The function returns -1 if the verification fails, and 0 on success. 
 *  On success, the decrypted message is stored into m.
 * 
 *  If the user wishes to use a password for encryption / decryption we need to generate a key for it.
 *  The project recommends using crypto_pwhash to convert a password to a key, but to be reproducible the routine requires:
 *    the salt to be know along with some other parameter constants
 *    https://doc.libsodium.org/key_derivation and https://doc.libsodium.org/password_hashing/default_phf
 * 
 * To do this we probably will use function:
 * 
 *  int crypto_pwhash(unsigned char * const out,
 *                  unsigned long long outlen,
 *                  const char * const passwd,
 *                  unsigned long long passwdlen,
 *                 const unsigned char * const salt,
 *                 unsigned long long opslimit,
 *                  size_t memlimit, int alg);
 *  The crypto_pwhash() function derives an outlen bytes long key from a password passwd whose length is passwdlen
 *  and a salt salt whose fixed length is crypto_pwhash_SALTBYTES bytes. 
 *  passwdlen should be at least crypto_pwhash_PASSWD_MIN and crypto_pwhash_PASSWD_MAX.
 *  outlen should be  at least crypto_pwhash_BYTES_MIN = 16 (128 bits) and at most crypto_pwhash_BYTES_MAX. 
 *
 *  The salt should be unpredictable. randombytes_buf() is the easiest way to fill the crypto_pwhash_SALTBYTES bytes of the salt.
 * 
 *  Keep in mind that to produce the same key from the same password, the same algorithm,
 *  the same salt, and the same values for opslimit and memlimit must be used.
 *  Therefore, these parameters must be stored for each user. 
 * 
 * 
 * 
 * END-DESCRIPTION
 *
 * START-CODE
 */

#include "sd.h"
#include <stdlib.h>
#include <stdio.h>
#include <sodium.h>

#include "keys.h"

/* Modified by Composer AI - 2026/06/10.
   k_error() longjmps and never returns; redeclare noreturn for analyzer. */
void k_error(char msg[], ...) __attribute__((noreturn));
/* -------------------- */

char* sd_KeyFromPW(char* mypassword, char* mysalt);
int sd_derive_key(const char* pw, size_t pwlen, const char* mysalt, size_t saltlen, char* keyb64);
int sd_randkey(char* keyb64);
void sd_xf_salt(void);
void sd_xf_key(void);
void sd_xf_randkey(void);

void sd_encrypt(int encode_type, char *key, char *data);
void sd_decrypt(int encode_type, char *key, char *data);


int sdme_encrypt(unsigned char *plaintext, int plaintext_len, unsigned char *key, unsigned char **cipher_out, size_t *cipher_out_len);
int sdme_decrypt(unsigned char *cipher_in, int cipher_in_len, unsigned char *key, unsigned char **plantext_out);

Private void sdme_err_rsp(int errnbr);

#ifdef dumphex
void dump_hex_buff(unsigned char buf[], unsigned int len)
{
    int i;
    for (i=0; i<len; i++) printf("%02X ", buf[i]);
    printf("\r\n");
}
#endif

/* ====================================================================== */

/* Create unique salt and return base64 encoded  (caller mustr free!!!)   */
char* sd_salt(){

  unsigned char salt[crypto_pwhash_SALTBYTES];
  char* saltb64;    /* returned salt buffer */

  /* 18 Oct 26 dm - SDSALT() reaches this without SDEXT, so libsodium is started here as well */
  if (sodium_init() == -1) {
    process.status = SD_SodInit_Err;
    return NULL;
  }

  /* random bytes provides us a random salt */
  randombytes_buf(salt, sizeof salt);

  /* create buffer for returned salt */
  saltb64 = malloc(sodium_base64_ENCODED_LEN(sizeof salt, sodium_base64_VARIANT_ORIGINAL)); /* encoded salt buffer */

  if (saltb64 == NULL){
    process.status = SD_Mem_Err;
    return NULL;
  }

  sodium_bin2base64(saltb64, sodium_base64_ENCODED_LEN(sizeof salt, sodium_base64_VARIANT_ORIGINAL), salt, sizeof salt,sodium_base64_VARIANT_ORIGINAL);
  return saltb64;
}

/* ====================================================================== */



/* 18 Oct 26 dm - encryption layer 2.  The argon2id limits are part of the format of every key SDKEY() has made: change
   either number and a passphrase and salt that gave one key give another, and everything encrypted under the first is
   lost.  They are written out here, and not left to libsodium's INTERACTIVE macros, so that a libsodium that moved its
   macros could not move them; the asserts say so at build time.  The docs give both numbers. */
#define SD_PWHASH_OPSLIMIT 2ULL         /* argon2id passes */
#define SD_PWHASH_MEMLIMIT 67108864ULL  /* 64 MiB */
#define SD_PASSPHRASE_MAX  65536        /* a longer passphrase is refused (SD_Pass_Err) */
_Static_assert(SD_PWHASH_OPSLIMIT == crypto_pwhash_OPSLIMIT_INTERACTIVE, "argon2id passes changed");
_Static_assert(SD_PWHASH_MEMLIMIT == crypto_pwhash_MEMLIMIT_INTERACTIVE, "argon2id memory changed");
_Static_assert(crypto_pwhash_SALTBYTES == 16, "the salt is 16 bytes");

#define KEY_LEN crypto_secretbox_KEYBYTES
#define KEY_B64_SZ (((KEY_LEN + 2) / 3) * 4 + 1)   /* base64 characters of a key and the terminator: 45 */

/* Derive a key from a passphrase of pwlen bytes and a base64 salt of saltlen characters.  keyb64 must hold KEY_B64_SZ
   bytes.  Returns 0 and the key as base64, or an SD_ error number and an empty keyb64.  The binary key is wiped here;
   the caller wipes keyb64 and its copy of the passphrase.  NOT a BASIC-visible routine: SDKEY() and SD_KEYFROMPW call it. */
int sd_derive_key(const char* pw, size_t pwlen, const char* mysalt, size_t saltlen, char* keyb64) {
  unsigned char salt[crypto_pwhash_SALTBYTES];
  unsigned char key[KEY_LEN];
  size_t bin_len = 0;
  int rc = 0;

  keyb64[0] = '\0';
  if (pwlen == 0 || pwlen > SD_PASSPHRASE_MAX)
    return SD_Pass_Err;
  if (sodium_init() == -1)
    return SD_SodInit_Err;

  /* the salt must be base64 for exactly the salt length: a short one used to leave the rest of the buffer as it was, which
     made the key depend on whatever was on the stack */
  if (sodium_base642bin(salt, sizeof salt, mysalt, saltlen, NULL, &bin_len, NULL, sodium_base64_VARIANT_ORIGINAL) != 0 ||
      bin_len != sizeof salt)
    return SD_Salt_Err;

  if (crypto_pwhash(key, sizeof key, pw, pwlen, salt, SD_PWHASH_OPSLIMIT, SD_PWHASH_MEMLIMIT, crypto_pwhash_ALG_ARGON2ID13) != 0) {
    rc = SD_Mem_Err;   /* the only failure crypto_pwhash has for good arguments is no memory for its 64 MiB */
  } else {
    sodium_bin2base64(keyb64, KEY_B64_SZ, key, KEY_LEN, sodium_base64_VARIANT_ORIGINAL);
  }
  sodium_memzero(key, sizeof key);
  sodium_memzero(salt, sizeof salt);
  return rc;
}

/* Create key from password and base64 encoded salt */
/* returns b64 encoded (must be freed by caller!!!) */
char* sd_KeyFromPW(char* mypassword, char* mysalt) {

  char* keyb64;    /* returned key buffer */
  int rc;

  process.status = 0;

  /* all important libsodium initialization */
  if (sodium_init() == -1) {
    process.status = SD_SodInit_Err;
    return NULL;
  }

  /* create buffer for returned key */
  keyb64 = sodium_malloc(KEY_B64_SZ);     /* encoded key buffer */
  if (keyb64 == NULL){
    process.status = SD_Mem_Err;
    return NULL;
  }

  /* 18 Oct 26 dm - the work is sd_derive_key(), shared with SDKEY(); a failure is now an empty string AND a status for every
     cause (a failed crypto_pwhash used to return the empty string with the status still 0) */
  rc = sd_derive_key(mypassword, strlen(mypassword), mysalt, strlen(mysalt), keyb64);
  if (rc != 0)
    process.status = rc;
  return keyb64;
}

/* 18 Oct 26 dm - a random 256 bit key as base64 (SDRANDKEY()); the caller wipes keyb64 (KEY_B64_SZ bytes) */
int sd_randkey(char* keyb64) {
  unsigned char key[KEY_LEN];

  keyb64[0] = '\0';
  if (sodium_init() == -1)
    return SD_SodInit_Err;
  randombytes_buf(key, sizeof key);
  sodium_bin2base64(keyb64, KEY_B64_SZ, key, KEY_LEN, sodium_base64_VARIANT_ORIGINAL);
  sodium_memzero(key, sizeof key);
  return 0;
}

/* ====================================================================== */
/* 18 Oct 26 dm - the three public BASIC functions, run from op_xfun() with the function number already taken off the stack.
   Each leaves one string on the stack: the result, or the null string with STATUS() set.  Nothing here writes a key, a
   passphrase or a salt anywhere but the stack: no audit line, no errlog, no $COMO. */

Private void xf_put_status(int rc) {
  sdme_err_rsp(rc);   /* a null string, and process.status = rc */
}

/* SDSALT(): a fresh random salt, base64 for 16 bytes (24 characters) */
void sd_xf_salt(void) {
  char* s;

  process.status = 0;
  s = sd_salt();
  if (s == NULL) {
    xf_put_status(process.status != 0 ? process.status : SD_Mem_Err);
    return;
  }
  k_put_c_string(s, e_stack);
  e_stack++;
  free(s);
}

/* SDKEY(passphrase, salt): a 44 character base64 key.  Stack: passphrase, salt (top). */
void sd_xf_key(void) {
  DESCRIPTOR* salt_d = e_stack - 1;
  DESCRIPTOR* pw_d = e_stack - 2;
  char salt[96];
  char* pw = NULL;
  char keyb64[KEY_B64_SZ];
  int32_t pwlen, saltlen;
  int rc;

  process.status = 0;
  keyb64[0] = '\0';

  /* sodium_malloc() asserts (and kills the process) if libsodium has not been started: its page size and canary are set by
     sodium_init().  SDKEY() as the FIRST libsodium call of a process used to do exactly that; the suite's rows ran after a
     SDSALT() in the same session and so never saw it. */
  if (sodium_init() == -1) {
    k_dismiss();
    k_dismiss();
    xf_put_status(SD_SodInit_Err);
    return;
  }

  k_get_string(pw_d);
  k_get_string(salt_d);
  pwlen = (pw_d->data.str.saddr == NULL) ? 0 : pw_d->data.str.saddr->string_len;
  saltlen = (salt_d->data.str.saddr == NULL) ? 0 : salt_d->data.str.saddr->string_len;

  if (pwlen < 1 || pwlen > SD_PASSPHRASE_MAX) {
    rc = SD_Pass_Err;
  } else if (saltlen < 1 || saltlen >= (int32_t)sizeof salt) {
    rc = SD_Salt_Err;
  } else if ((pw = sodium_malloc((size_t)pwlen + 1)) == NULL) {
    rc = SD_Mem_Err;
  } else {
    (void)k_get_c_string(salt_d, salt, saltlen);
    (void)k_get_c_string(pw_d, pw, pwlen);
    rc = sd_derive_key(pw, (size_t)pwlen, salt, (size_t)saltlen, keyb64);
  }

  if (pw != NULL)
    sodium_free(pw);   /* zeroes before it frees */
  k_dismiss();         /* the salt */
  k_dismiss();         /* the passphrase */
  if (rc != 0) {
    xf_put_status(rc);
  } else {
    k_put_c_string(keyb64, e_stack);
    e_stack++;
  }
  sodium_memzero(keyb64, sizeof keyb64);
}

/* SDRANDKEY(): a random 256 bit key as 44 base64 characters */
void sd_xf_randkey(void) {
  char keyb64[KEY_B64_SZ];
  int rc;

  process.status = 0;
  rc = sd_randkey(keyb64);
  if (rc != 0) {
    xf_put_status(rc);
  } else {
    k_put_c_string(keyb64, e_stack);
    e_stack++;
  }
  sodium_memzero(keyb64, sizeof keyb64);
}

/* ====================================================================== */

void op_encrypt() {
/*    encrypted_text = SDENCRYPT(Data,KeyToUse,Encoding) 
      Stack:
        +=============================++=============================+
        +       STACK On Entry        ++       STACK On Exit         +
        +=============================++=============================+
estack> +    next available descr     ++    next available descr     +
        +=============================++=============================+
        +  descriptor w/ integer      ++  Addr to descr for RTNVAL   +
        +      Encoding               ++                             +
        +=============================++=============================+
        + Addr to descriptor for Arg  ++   
        +      KeyToUse               ++
        +=============================++
        + Addr to descriptor for Arg  ++
        +      Data                   ++           
        +=============================++
*/       

  int32_t key_len;
  int32_t keybf_sz;
  char* key_buffer;                       /* buffer for passed key string  */
  int32_t data_len;
  int32_t databf_sz;
  char* data_buffer;                       /* buffer for passed key string  */
  STRING_CHUNK* str;
  int16_t encodeType;

  DESCRIPTOR* descr;
  
  /* set the process.status flag to  "successful"      */
  /* User can retrieve this status with the BASIC function STATUS()*/
    process.status = 0;
    
  /* Get Encoding  */
  descr = e_stack - 1;   /* e_stack - 1 points to key descriptor */
  GetInt(descr);
  encodeType = (int16_t)(descr->data.value);
  k_pop(1);   /* after pop() e_stack - 1 points to descr which holds KeyToUse  */   

  /* Get Key string */
  descr = e_stack - 1;
  k_get_string(descr);
  str = descr->data.str.saddr;
  /* is there something there? */
  if (str == NULL){
    key_len = 0;  
    keybf_sz = 1;              /* room for string terminator */
  }else{
	 key_len =  str->string_len;
     keybf_sz  =  key_len+1;  /* room for string terminator */
  }
  
  /* allocate space for val string */
  key_buffer = malloc(keybf_sz * sizeof(char));
  if (key_buffer == NULL){
  /* so here is a question, what to do if we cannot allocate memory?
     Looking thru the code SD sometimes checks and other times does not.
	 We will end execution of program and attempt to report error  */
     k_error(sysmsg(10005));   /* Insufficient memory for buffer allocation */
	 /* We never come back from k_error */
  }

  /* move the passed argument string to our buffer */
  if (key_len == 0){
	  key_buffer[0] = '\0';
  } else {
   /* rem string length returned by k_get_c_string excludes terminator in count!*/ 
      key_len = k_get_c_string(descr, key_buffer, key_len);
  }
  
  k_dismiss();   /* done with passed arg  descriptor */
                 /* Things to note                   */  
                 /* we use dismiss() instead of pop() because this is a string */ 
                 /* which may be made up of a linked list of string blocks     */
                 /* Using pop would not free the string blocks                 */
                 /* After dismiss() e_stack  points to descr which will receive RTNVAL */
                 
/* Get data string */
  descr = e_stack - 1;
  k_get_string(descr);
  str = descr->data.str.saddr;
  /* is there something there? */
  if (str == NULL){
    data_len = 0;  
    databf_sz = 1;              /* room for string terminator */
  }else{
	 data_len =  str->string_len;
     databf_sz  =  data_len+1;  /* room for string terminator */
  }
  
  /* allocate space for val string */
  data_buffer = malloc(databf_sz * sizeof(char));
  if (data_buffer == NULL){
  /* so here is a question, what to do if we cannot allocate memory?
     Looking thru the code SD sometimes checks and other times does not.
	 We will end execution of program and attempt to report error  */
     k_error(sysmsg(10005));   /* Insufficient memory for buffer allocation */
	 /* We never come back from k_error */
  }

  /* move the passed argument string to our buffer */
  if (data_len == 0){
	  data_buffer[0] = '\0';
  } else {
   /* rem string length returned by k_get_c_string excludes terminator in count!*/ 
      data_len = k_get_c_string(descr, data_buffer, data_len);
  }
  
  k_dismiss();   /* done with passed arg  descriptor */

/* encrypt the data */

  sd_encrypt(encodeType,key_buffer,data_buffer);

/* release buffers */

  if (key_buffer != NULL){
    free(key_buffer);    
  }
  
  if (data_buffer != NULL){
    free(data_buffer);    
  }

return;

}

/* ====================================================================== */

void op_decrypt() {
/*    decrypted_text = SDDECRYPT(Data,KeyToUse,Encoding) 
      Stack:
        +=============================++=============================+
        +       STACK On Entry        ++       STACK On Exit         +
        +=============================++=============================+
estack> +    next available descr     ++    next available descr     +
        +=============================++=============================+
        +  descriptor w/ integer      ++  Addr to descr for RTNVAL   +
        +      Encoding               ++                             +
        +=============================++=============================+
        + Addr to descriptor for Arg  ++   
        +      KeyToUse               ++
        +=============================++
        + Addr to descriptor for Arg  ++
        +      Data                   ++           
        +=============================++
*/       

  int32_t key_len;
  int32_t keybf_sz;
  char* key_buffer;                       /* buffer for passed key string  */
  int32_t data_len;
  int32_t databf_sz;
  char* data_buffer;                       /* buffer for passed key string  */
  STRING_CHUNK* str;
  int16_t encodeType;

  DESCRIPTOR* descr;
  
  /* set the process.status flag to  "successful"      */
  /* User can retrieve this status with the BASIC function STATUS()*/
    process.status = 0;
    
  /* Get Encoding  */
  descr = e_stack - 1;   /* e_stack - 1 points to key descriptor */
  GetInt(descr);
  encodeType = (int16_t)(descr->data.value);
  k_pop(1);   /* after pop() e_stack - 1 points to descr which holds KeyToUse  */   

  /* Get Key string */
  descr = e_stack - 1;
  k_get_string(descr);
  str = descr->data.str.saddr;
  /* is there something there? */
  if (str == NULL){
    key_len = 0;  
    keybf_sz = 1;              /* room for string terminator */
  }else{
	 key_len =  str->string_len;
     keybf_sz  =  key_len+1;  /* room for string terminator */
  }
  
  /* allocate space for val string */
  key_buffer = malloc(keybf_sz * sizeof(char));
  if (key_buffer == NULL){
  /* so here is a question, what to do if we cannot allocate memory?
     Looking thru the code SD sometimes checks and other times does not.
	 We will end execution of program and attempt to report error  */
     k_error(sysmsg(10005));   /* Insufficient memory for buffer allocation */
	 /* We never come back from k_error */
  }

  /* move the passed argument string to our buffer */
  if (key_len == 0){
	  key_buffer[0] = '\0';
  } else {
   /* rem string length returned by k_get_c_string excludes terminator in count!*/ 
      key_len = k_get_c_string(descr, key_buffer, key_len);
  }
  
  k_dismiss();   /* done with passed arg  descriptor */
                 
/* Get data string */
  descr = e_stack - 1;
  k_get_string(descr);
  str = descr->data.str.saddr;
  /* is there something there? */
  if (str == NULL){
    data_len = 0;  
    databf_sz = 1;              /* room for string terminator */
  }else{
	 data_len =  str->string_len;
     databf_sz  =  data_len+1;  /* room for string terminator */
  }
  
  /* allocate space for val string */
  data_buffer = malloc(databf_sz * sizeof(char));
  if (data_buffer == NULL){
  /* so here is a question, what to do if we cannot allocate memory?
     Looking thru the code SD sometimes checks and other times does not.
	 We will end execution of program and attempt to report error  */
     k_error(sysmsg(10005));   /* Insufficient memory for buffer allocation */
	 /* We never come back from k_error */
  }

  /* move the passed argument string to our buffer */
  if (data_len == 0){
	  data_buffer[0] = '\0';
  } else {
   /* rem string length returned by k_get_c_string excludes terminator in count!*/ 
      data_len = k_get_c_string(descr, data_buffer, data_len);
  }
  
  k_dismiss();   /* done with passed arg  descriptor */

/* decrypt the data */

  sd_decrypt(encodeType,key_buffer,data_buffer);

/* release buffers */

  if (key_buffer != NULL){
    free(key_buffer);    
  }
  
  if (data_buffer != NULL){
    free(data_buffer);    
  }

return;

}

/* ====================================================================== */

/*  function encrypts data using key (which is encoded, based on encode_type) 
and encodes encrypted data based on encode_type */
void sd_encrypt(int encode_type, char *key, char *data) {
  unsigned char dckey[crypto_secretbox_KEYBYTES];  /* decoded key buffer  */
  unsigned char *cipher_buf;
  char *encode_out;

  size_t key_len;
  size_t bin_len;
  size_t cipher_buf_len;
  size_t encode_sz;
  size_t plaintext_sz;

  encode_out = NULL;
  cipher_buf = NULL;

  /* set the process.status flag to  "successful"      */
  /* User can retrieve this status with the BASIC function STATUS()*/
  process.status = 0;

  /* all important libsodium initialization */
  if (sodium_init() == -1) {
    sdme_err_rsp(SD_SodInit_Err);  /* initialization error */
    return ;
  }

  /*Evaluate Encode Type */

  switch (encode_type) {
	  
    case SD_EncodeHX: /* Encrypt Data text with encoded Key Key returning encrypted text in hex encoded string format */

      plaintext_sz = strlen(data); /* size of text to encrypt */
      if (plaintext_sz == 0){
        sdme_err_rsp(SD_Encrypt_Err);   /* nothing to encrypt */
        break;
      }


      key_len = strlen(key);  /* encoded key length */
      /* valid key lenght (rem encoded in hex so 2X the expected sixe)*/
      if (key_len != crypto_secretbox_KEYBYTES *2){
        sdme_err_rsp(SD_KeyLen_Err);    /* bad key */
        break;
      }

      /* convert key from hex encodeing to bytes */
      if (sodium_hex2bin(dckey, crypto_secretbox_KEYBYTES, key, key_len, NULL, &bin_len, NULL) != 0) {
        sdme_err_rsp(SD_Decode_Err);
        break;
      }

      /* encrypt the text*/
      cipher_buf_len = 0;    /* get rid of 'cipher_buf_len’ may be used uninitialized warning????*/
      /* rem sdme_encrypt allocates mem for cipher_buf */
      if (sdme_encrypt((unsigned char *)data, plaintext_sz, dckey, &cipher_buf, &cipher_buf_len) != 0) {
        sdme_err_rsp(SD_Encrypt_Err);   /* encrypt failed */
        break;
      }

      /* will the encode operation exceed max string?? */
      if ((cipher_buf_len * 2) > MAX_STRING_SIZE){
		    free(key);
		    free(data); 
        sodium_free(cipher_buf);		  
        k_error(sysmsg(10004));   /* Operation exceeds MAX_STRING_SIZE */
      }

      /* allocate our encode buffer*/
      encode_sz = (cipher_buf_len * 2) + 1;
      encode_out = sodium_malloc(encode_sz);
      if (encode_out == NULL){
        sodium_free(cipher_buf);
        cipher_buf = NULL;
        sdme_err_rsp(SD_Mem_Err);
        break;  
      }

      /* encode cipher text */
      sodium_bin2hex(encode_out, encode_sz, cipher_buf, cipher_buf_len);

      /* we made it, pass encrypted and encoded text back to caller */
      k_put_c_string(encode_out, e_stack); /* sets descr as type string and encrypted and encoded text it */
      e_stack++;
      /* and free up our buffers */
      sodium_free(encode_out);
      sodium_free(cipher_buf);
      encode_out = NULL;
      cipher_buf = NULL;
      break;


    case SD_Encode64: /* Encrypt Data text with encoded Key Key returning encrypted text in B64 encoded string format */

      plaintext_sz = strlen(data); /* size of text to encrypt */
      if (plaintext_sz == 0){
        sdme_err_rsp(SD_Encrypt_Err);   /* nothing to encrypt */
        break;
      }


      key_len = strlen(key);  /* encoded key length */
      /* valid key lenght (rem encoded in B64, need to calculate the encoded size expected)*/
      if (key_len != sodium_base64_ENCODED_LEN(crypto_secretbox_KEYBYTES, sodium_base64_VARIANT_ORIGINAL) - 1){
        sdme_err_rsp(SD_KeyLen_Err);    /* bad key */
        break;
      }

      /* convert key from B64 encodeing to bytes */
      if (sodium_base642bin(dckey, crypto_secretbox_KEYBYTES, key, key_len, NULL, &bin_len, NULL,sodium_base64_VARIANT_ORIGINAL) != 0) {
        sdme_err_rsp(SD_Decode_Err);
        break;
      }

      /* encrypt the text*/
      cipher_buf_len = 0;    /* get rid of 'cipher_buf_len’ may be used uninitialized warning????*/
      /* rem sdme_encrypt allocates mem for cipher_buf */
      if (sdme_encrypt((unsigned char *)data, plaintext_sz, dckey, &cipher_buf, &cipher_buf_len) != 0) {
        sdme_err_rsp(SD_Encrypt_Err);   /* encrypt failed */
        break;
      }

      /* will the encode operation exceed max string?? */
      /* rem sodium_base64_ENCODED_LEN includes a spot for the trailing /0 */
      encode_sz = sodium_base64_ENCODED_LEN(cipher_buf_len, sodium_base64_VARIANT_ORIGINAL);
      if ( encode_sz > MAX_STRING_SIZE) { 
		    free(key);
		    free(data); 
        sodium_free(cipher_buf);		  
        k_error(sysmsg(10004));   /* Operation exceeds MAX_STRING_SIZE */
      }

      /* allocate our encode buffer*/
      encode_out = sodium_malloc(encode_sz);
      if (encode_out == NULL){
        sodium_free(cipher_buf);
        cipher_buf = NULL;
        sdme_err_rsp(SD_Mem_Err);
        break;  
      }

      /* encode cipher text */
      sodium_bin2base64(encode_out, encode_sz, cipher_buf, cipher_buf_len,sodium_base64_VARIANT_ORIGINAL);

      /* we made it, pass encrypted and encoded text back to caller */
      k_put_c_string(encode_out, e_stack); /* sets descr as type string and encrypted and encoded text it */
      e_stack++;
      /* and free up our buffers */
      sodium_free(encode_out);
      sodium_free(cipher_buf);
      encode_out = NULL;
      cipher_buf = NULL;
      break;

      
    default:
      /* unknown encode type */
      sdme_err_rsp(SD_EDType_Err);

  }
  sodium_memzero(dckey, sizeof dckey);   /* 18 Oct 26 dm */
  return;
}

/* ====================================================================== */

/*  function performs decryption of data using key key 
    data and key are encoded, based on encode_type */
void sd_decrypt(int encode_type, char *key, char *data) {
  unsigned char dckey[crypto_secretbox_KEYBYTES];
  unsigned char *cipher_buf;
  unsigned char *plaintext_buf;

  size_t key_len;
  size_t bin_len_max;
  size_t bin_len;
  size_t encrypted_sz;
  
  cipher_buf = NULL;

  /* set the process.status flag to  "successful"      */
  /* User can retrieve this status with the BASIC function STATUS()*/
  process.status = 0;

  /* all important libsodium initialization */
  if (sodium_init() == -1) {
    sdme_err_rsp(SD_SodInit_Err);  /* initialization error */
    return ;
  }

  /*Evaluate Function KEY */

  switch (encode_type) {

    case SD_EncodeHX: /* Decrypt Hex encoded data text with encoded Key key returning decrypted text  */

      encrypted_sz = strlen(data);    /* size of the encoded encrypted string passed*/
      /* rem this encryption method has appended to the end of the string: 
         1) the authentication tag of size  crypto_secretbox_MACBYTES
         2) the nonce of size crypto_secretbox_NONCEBYTES 
         All hex encoded.
         If the string to decode then decrypt is smaller than (crypto_secretbox_MACBYTES + crypto_secretbox_NONCEBYTES) *2)
        Something is not right, error out*/
      if (encrypted_sz < (crypto_secretbox_MACBYTES + crypto_secretbox_NONCEBYTES) *2){
        sdme_err_rsp(SD_Decrypt_Err);
        break;
      }

      key_len = strlen(key);  /* encoded key length */
      /* valid key lenght (rem encoded in hex so 2X the expected sixe)*/
      if (key_len != crypto_secretbox_KEYBYTES *2){
        sdme_err_rsp(SD_KeyLen_Err);
        break;
      }


      /* convert key from hex encodeing to bytes */
      if (sodium_hex2bin(dckey, crypto_secretbox_KEYBYTES, key, key_len, NULL, &bin_len, NULL) != 0) {
        sdme_err_rsp(SD_Decode_Err);
        break;
      }
  
      /* need a buffer to hold decoded, encrypted bytes, which SHOULD be 1/2 the size of the Hex Encoded Encrypted Text */
      bin_len = (encrypted_sz / 2) + 1;
      cipher_buf = sodium_malloc(bin_len);
      if (cipher_buf == NULL){
        sdme_err_rsp(SD_Mem_Err);
        break;  
      }
      
      /* decode the encoded encrypted text */
      if (sodium_hex2bin(cipher_buf, encrypted_sz / 2, data, encrypted_sz, NULL, &bin_len, NULL) != 0) {
        sodium_free(cipher_buf);
        cipher_buf = NULL;
        sdme_err_rsp(SD_Decode_Err);
        break;
      }

      /* 18 Oct 26 dm - sdme_decrypt() allocates the plaintext buffer; the one allocated here was replaced by it and lost */
      plaintext_buf = NULL;

      /* decrypt the encrypted byte buffer */

      if (sdme_decrypt(cipher_buf, bin_len, dckey, &plaintext_buf) != 0) {
        sodium_free(cipher_buf);
        cipher_buf = NULL;
        sodium_free(plaintext_buf);
        plaintext_buf = NULL;
        sdme_err_rsp(SD_Decrypt_Err);
        break; 
      }
 
     /* we made it, text back to caller */
      k_put_c_string((char *)plaintext_buf, e_stack); /* sets descr as type string and encrypted and encoded text it */
      e_stack++;
      /* and free up our buffers */
      sodium_free(cipher_buf);
      cipher_buf = NULL;
      sodium_free(plaintext_buf);
      plaintext_buf = NULL;
      break;

    case SD_Encode64: /* Decrypt B64 encoded data text with encoded Key key returning decrypted text  */

      encrypted_sz = strlen(data);    /* size of the encoded encrypted string passed*/
      /* rem this encryption method has appended to the end of the string: 
         1) the authentication tag of size  crypto_secretbox_MACBYTES
         2) the nonce of size crypto_secretbox_NONCEBYTES 
         All B64 encoded.
         If the string to decode then decrypt is smaller than (crypto_secretbox_MACBYTES + crypto_secretbox_NONCEBYTES) *2)
        Something is not right, error out*/
      if (encrypted_sz < sodium_base64_ENCODED_LEN(crypto_secretbox_MACBYTES + crypto_secretbox_NONCEBYTES, sodium_base64_VARIANT_ORIGINAL) -1){
        sdme_err_rsp(SD_Decrypt_Err);
        break;
      }

      key_len = strlen(key);  /* encoded key length */
      /* valid key lenght (rem encoded in B64, need to calculate the encoded size expected)*/
      if (key_len != sodium_base64_ENCODED_LEN(crypto_secretbox_KEYBYTES, sodium_base64_VARIANT_ORIGINAL) - 1){
        sdme_err_rsp(SD_KeyLen_Err);    /* bad key */
        break;
      }


      /* convert key from B64 encodeing to bytes */
      if (sodium_base642bin(dckey, crypto_secretbox_KEYBYTES, key, key_len, NULL, &bin_len, NULL,sodium_base64_VARIANT_ORIGINAL) != 0) {
        sdme_err_rsp(SD_Decode_Err);
        break;
      }
  
      /* need a buffer to hold decoded, encrypted bytes, 
         Base64 encodes 3 bytes as 4 characters, so the result of decoding a b64_len string will always be at most b64_len / 4 * 3 bytes long. */
      bin_len_max = ((encrypted_sz / 4) * 3) + 1;
      cipher_buf = sodium_malloc(bin_len_max);
      if (cipher_buf == NULL){
        sdme_err_rsp(SD_Mem_Err);
        break;  
      }
      
      /* decode the encoded encrypted text */
      /* rem bin_len_max is the max size the decoded b64 string can be */
      /*     bin_len is the actual size of the decoded string          */
      if (sodium_base642bin(cipher_buf, bin_len_max, data, encrypted_sz, NULL, &bin_len, NULL,sodium_base64_VARIANT_ORIGINAL) != 0) {
        sodium_free(cipher_buf);
        cipher_buf = NULL;
        sdme_err_rsp(SD_Decode_Err);
        break;
      }

      /* 18 Oct 26 dm - sdme_decrypt() allocates the plaintext buffer; the one allocated here was replaced by it and lost */
      plaintext_buf = NULL;

      /* decrypt the encrypted byte buffer */

      if (sdme_decrypt(cipher_buf, bin_len, dckey, &plaintext_buf) != 0) {
        sodium_free(cipher_buf);
        cipher_buf = NULL;
        sodium_free(plaintext_buf);
        plaintext_buf = NULL;
        sdme_err_rsp(SD_Decrypt_Err);
        break; 
      }
 
     /* we made it, text back to caller */
      k_put_c_string((char *)plaintext_buf, e_stack); /* sets descr as type string and encrypted and encoded text it */
      e_stack++;
      /* and free up our buffers */
      sodium_free(cipher_buf);
      cipher_buf = NULL;
      sodium_free(plaintext_buf);
      plaintext_buf = NULL;
      break;


    default:
      /* unknown encode type */
      sdme_err_rsp(SD_EDType_Err);

  }
  sodium_memzero(dckey, sizeof dckey);   /* 18 Oct 26 dm */
  return;
}

/* ====================================================================== */

/* generic error return with null response, setting process.status */
Private void sdme_err_rsp(int errNbr){
  char EmptyResp[1] = {'\0'}; /*  empty return message  */
  k_put_c_string(EmptyResp, e_stack); /* sets descr as type string, empty */
  e_stack++;
  process.status = errNbr;

}

/* ====================================================================== */

/* Encrypt plaintest using key returning cipher_out
   Caller is responsible for freeing cipher_out buffer! */
int sdme_encrypt(unsigned char *plaintext, int plaintext_len, unsigned char *key, unsigned char **cipher_out_buf, size_t * cipher_out_len) {
  unsigned char nonce[crypto_secretbox_NONCEBYTES]; /* buffer for nonce (Initialization Vector IV by any other name)*/
  size_t cipher_len;
  unsigned char *cipher_out;

  /* Using random bytes to create our nonce (used only once) */
  randombytes_buf(nonce, crypto_secretbox_NONCEBYTES);
  #ifdef dumphex
  printf("nonce:\r\n");
  dump_hex_buff(nonce, crypto_secretbox_NONCEBYTES);
  #endif

  /* In our implementation we save the nance at the end of the cybertext, we need to make space for it  in our buffer*/
  cipher_len = crypto_secretbox_MACBYTES + crypto_secretbox_NONCEBYTES + plaintext_len;
  cipher_out = (unsigned char *)sodium_malloc(cipher_len);
  if (cipher_out == NULL) {
    return SD_Mem_Err;
  }

  /* perform the encryption  */
  if (crypto_secretbox_easy(cipher_out, plaintext, (unsigned long long)plaintext_len, nonce, key) != 0) {
    sodium_free(cipher_out);
    cipher_out = NULL;
    return SD_Encrypt_Err;
  }
    #ifdef dumphex
    printf("ciphertext:\r\n");
    dump_hex_buff(cipher_out, cipher_len);
    #endif

  /* now append the nonce to the cipher output */
  /* rem only reason this works is cipher to plain text is a one to one */
  memcpy(cipher_out + plaintext_len + crypto_secretbox_MACBYTES, nonce, crypto_secretbox_NONCEBYTES);
  #ifdef dumphex
  printf("ciphertext+nonce:\r\n");
  dump_hex_buff(cipher_out, cipher_len);
  #endif

  /* caller needs to know the size of cipher output and its location */
  * cipher_out_len = cipher_len;
  * cipher_out_buf = cipher_out;

  return 0;
}

/* ====================================================================== */

/* Decrypt cipher_in using key returning plantext_out
   Caller is responsible for freeing plantext_out buffer! */

int sdme_decrypt(unsigned char *cipher_in, int cipher_in_len, unsigned char *key, unsigned char **plantext_out_ptr) {
  unsigned char nonce[crypto_secretbox_NONCEBYTES]; /* buffer for nonce (Initialization Vector IV by any other name)*/
  unsigned char *plaintext_out;
  unsigned int plaintext_len;
  unsigned int cipher_len;

  /* 18 Oct 26 dm - shorter than a nonce and a tag cannot be a message, and the unsigned subtractions below would wrap */
  if (cipher_in_len < (int)(crypto_secretbox_NONCEBYTES + crypto_secretbox_MACBYTES))
    return SD_Decrypt_Err;

  /* Remeber SDMEE_Encrypt appends the nonce to the end of the cipher output, do not what to add to decrypted output */
  cipher_len = cipher_in_len - crypto_secretbox_NONCEBYTES;

  /* Also remember cipher_len is the length of this authentication tag + encrypted message */
  /* We want the actual message size*/
  plaintext_len = cipher_len - crypto_secretbox_MACBYTES;

  /* allocate space for the plaintext output, add room for string terminator */
  plaintext_out = (unsigned char *)sodium_malloc(plaintext_len+1);
  if (plaintext_out == NULL) {
    return SD_Mem_Err;
  }

  /* pull off the nonce from the end of the cipher */
  memcpy(nonce, cipher_in + cipher_len, crypto_secretbox_NONCEBYTES);

  /* decode our cihper */
  if (crypto_secretbox_open_easy(plaintext_out, cipher_in, (unsigned long long)cipher_len, nonce, key) == 0) {
    /* success, add in string terminator */
    plaintext_out[plaintext_len] = '\0';
    *plantext_out_ptr = plaintext_out;
  } else { 
    /* failed, free memory */ 
    sodium_free(plaintext_out);
    plaintext_out = NULL;
    return SD_Decrypt_Err;
  }

  return 0;
}
