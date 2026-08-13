#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/*
 * Include the implementation so this regression test can inspect private
 * session state without adding test-only exports to the production DLL.
 */
#define BUILDING_SDCLILIB
#include "../sdclilib.c"

/* Write a packed ARGDATA record (matches struct ARGDATA: pack(2), LE). */
static void put_arg(char *b, int16_t argno, int32_t arglen,
                    const char *text, int textlen) {
  memcpy(b, &argno, sizeof argno);
  memcpy(b + 2, &arglen, sizeof arglen);
  if (textlen > 0)
    memcpy(b + 6, text, textlen);
}

int main(void) {
  char *big;
  int i;

  initialise_client();

  /* --- Unit tests for the extracted, bounds-checking helpers (no server). --- */
  {
    char rec[32];
    int16_t argno;
    const char *text;
    int32_t len;
    int next;
    int32_t cases[] = {0, 1, BUFF_INCR - 1, BUFF_INCR, BUFF_INCR + 1,
                       2 * BUFF_INCR};
    unsigned c;

    /* valid_packet_length: reject below the header and above the max. */
    if (valid_packet_length(IN_PKT_HDR_BYTES - 1)) return 30;
    if (valid_packet_length(-1)) return 31;
    if (!valid_packet_length(IN_PKT_HDR_BYTES)) return 32;
    if (!valid_packet_length(SD_MAX_PACKET_BYTES)) return 33;
    if (valid_packet_length(SD_MAX_PACKET_BYTES + 1)) return 34;

    /* write_record must enforce the server's maximum string size. */
    if (!valid_record_size(MAX_STRING_SIZE)) return 35;
    if (valid_record_size((size_t)MAX_STRING_SIZE + 1)) return 36;

    /* grow_buffer_size: always a BUFF_INCR multiple strictly greater than the
       request, so read_packet()'s trailing NUL always fits. */
    for (c = 0; c < sizeof(cases) / sizeof(cases[0]); c++) {
      int32_t g = grow_buffer_size(cases[c]);
      if (g <= cases[c]) return 40;
      if (g & (BUFF_INCR - 1)) return 41;
    }

    /* read_arg_record: well-formed, padded record (6 header + "abc" + pad). */
    put_arg(rec, 1, 3, "abc", 3);
    if (!read_arg_record(rec, 10, 0, &argno, &text, &len, &next)) return 50;
    if (argno != 1 || len != 3 || memcmp(text, "abc", 3) != 0) return 51;
    if (next != 10) return 52; /* 6 header + 3 padded up to 4 */

    /* A missing final pad byte is tolerated, but next_offset is clamped so it
       never points past the packet. */
    if (!read_arg_record(rec, 9, 0, &argno, &text, &len, &next)) return 53;
    if (next != 9) return 54;

    /* Truncated header must be rejected. */
    if (read_arg_record(rec, 5, 0, &argno, &text, &len, &next)) return 55;
    /* An offset leaving fewer than header bytes must be rejected. */
    if (read_arg_record(rec, 10, 5, &argno, &text, &len, &next)) return 56;
    /* Text that does not fit must be rejected. */
    put_arg(rec, 1, 3, "abc", 3);
    if (read_arg_record(rec, 8, 0, &argno, &text, &len, &next)) return 57;
    /* Negative length must be rejected. */
    put_arg(rec, 1, -1, NULL, 0);
    if (read_arg_record(rec, 6, 0, &argno, &text, &len, &next)) return 58;
    /* Length running past the packet must be rejected. */
    put_arg(rec, 1, 100, NULL, 0);
    if (read_arg_record(rec, 6, 0, &argno, &text, &len, &next)) return 59;
    /* Length that exactly fills the packet is accepted. */
    put_arg(rec, 2, 4, "wxyz", 4);
    if (!read_arg_record(rec, 10, 0, &argno, &text, &len, &next)) return 64;
    if (argno != 2 || len != 4) return 65;
  }

  /* --- Regression: the outgoing-buffer growth path must allocate at least as
     many bytes as the packet being built. A bad rounding mask (& ~BUFF_INCR
     instead of & ~(BUFF_INCR - 1)) could under-allocate by a byte, and SDCallx
     additionally failed to update buff_size after reallocating. We drive the
     growth path with a single argument sized so the packet lands exactly on
     the BUFF_INCR (4096) boundary:

        packet = 2 (subrname len) + 2 (padded "S") + 2 (argc)
                 + 4 (arg len) + arglen            == 10 + arglen

     No server is contacted: write_packet() returns FALSE on the INVALID_SOCKET
     and SDCallx() unwinds cleanly. --- */
  session[0].context = CX_CONNECTED;
  session_idx = 0;

  big = malloc(4086 + 1);
  if (big == NULL)
    return 10;
  memset(big, 'x', 4086);
  big[4086] = '\0';

  SDCallx("S", 1, big); /* packet == 4096 bytes, forces reallocation */

  if (buff == NULL)
    return 11;
  if (buff_size < 4096) /* under-allocated, or buff_size left stale */
    return 12;

  free(big);

  /* --- Regression: an over-long index name/value must be rejected, not
     memcpy'd into the fixed-size packet buffers (which would smash the stack).
     The guards fire before message_pair(), so no server is contacted. --- */
  {
    char longname[300];
    char *k;

    memset(longname, 'A', sizeof(longname) - 1);
    longname[sizeof(longname) - 1] = '\0';

    session_idx = 0;
    session[0].context = CX_CONNECTED;

    session[0].sd_status = 0;
    SDSelectIndex(1, longname, "value", 5);
    if (session[0].sd_status != ER_BAD_NAME)
      return 20;

    session[0].sd_status = 0;
    SDSetLeft(1, longname);
    if (session[0].sd_status != ER_BAD_NAME)
      return 21;

    session[0].sd_status = 0;
    k = SDSelectLeft(1, longname, 5);
    if (k == NULL || session[0].sd_status != ER_BAD_NAME)
      return 22;
    SDFree(k);
  }

  /* --- Regression: SDDisconnectAll() must reset every session and free the
     shared network buffer. --- */
  for (i = 0; i < MAX_SESSIONS; i++)
    session[i].context = CX_DISCONNECTED;
  session[0].context = CX_CONNECTED;
  session[2].context = CX_EXECUTING;
  session_idx = 0;

  SDDisconnectAll();

  if (session[0].context != CX_DISCONNECTED)
    return 1;
  if (session[2].context != CX_DISCONNECTED)
    return 2;
  if (buff != NULL)
    return 3;

  /* --- Regression (#4): a pre-network failure must not dereference a NULL
     buff on the exit path. With no connection and buff freed, SDReadList()
     must return an allocated empty string rather than crash. --- */
  {
    char *list;
    session_idx = 0;
    session[0].context = CX_DISCONNECTED; /* forces context_error */
    session[0].server_error = SV_OK;
    list = SDReadList(1);
    if (list == NULL || list[0] != '\0')
      return 60;
    SDFree(list);
    if (buff != NULL) /* this path must not have allocated buff */
      return 61;
    if (session[0].server_error != SV_ECONTXT)
      return 62;
  }

  /* A failed request/response exchange is distinct from a server-side error. */
  session[0].context = CX_CONNECTED;
  session[0].sock = INVALID_SOCKET;
  session[0].server_error = SV_OK;
  if (message_pair(SrvrOpen, NULL, 0))
    return 63;
  if (session[0].server_error != SV_EMSG_PAIR)
    return 66;

  puts("sdclilib internal session test passed");
  return 0;
}
