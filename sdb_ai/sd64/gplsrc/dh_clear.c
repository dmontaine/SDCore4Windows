/* DH_CLEAR.C
 * Clear file
 * Copyright (c) 2006 Ladybridge Systems, All Rights Reserved
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
 * 31 Dec 23 SD launch - prior history suppressed
 * END-HISTORY
 *
 * START-DESCRIPTION:
 *
 * END-DESCRIPTION
 *
 * START-CODE
 */

#include "sd.h"
#include "dh_int.h"

/* ====================================================================== */

bool dh_clear(DH_FILE* dh_file) {
  bool status = FALSE;
  FILE_ENTRY* fptr;
  int32_t new_modulus;
  int32_t mod_value;
  int32_t group;
  int group_size_bytes;
  u_int32_t ak_map;
  int16_t akno;

  dh_err = 0;
  process.os_error = 0;

  dh_end_select_file(dh_file); /* Kill any select */

  fptr = FPtr(dh_file->file_id);
  StartExclusive(FILE_TABLE_LOCK, 44);
  fptr->stats.clears++;
  sysseg->global_stats.clears++;
  EndExclusive(FILE_TABLE_LOCK);

  /* ----------------------------------------------------------------------
    Rewrite primary subfile header with minimum modulus, etc               */

  FDS_open(dh_file, PRIMARY_SUBFILE);
  if (!dh_read_group(dh_file, PRIMARY_SUBFILE, 0, dh_buffer,
                     (int16_t)(dh_file->header_bytes))) {
    goto exit_dh_clear;
  }
  ak_map = ((DH_HEADER*)dh_buffer)->ak_map;

  new_modulus = fptr->params.min_modulus;
  group_size_bytes = dh_file->group_size;

  fptr->params.modulus = new_modulus;
  fptr->params.load_bytes = 0;
  fptr->params.free_chain = 0;
  fptr->record_count = 0;

  /* Calculate mod_value as next power of two >= new_modulus */

  for (mod_value = 1; mod_value < new_modulus; mod_value <<= 1) {
  }
  fptr->params.mod_value = mod_value;

  dh_file->flags |= FILE_UPDATED;
  dh_flush_header(dh_file);

  /* Initialise data groups */

  memset(dh_buffer, 0, group_size_bytes);
  ((DH_BLOCK*)(dh_buffer))->used_bytes = BLOCK_HEADER_SIZE;
  ((DH_BLOCK*)(dh_buffer))->block_type = DHT_DATA;

  if (Seek(dh_file->sf[PRIMARY_SUBFILE].fu, (int64)(dh_file->header_bytes),
           SEEK_SET) < 0) {
    dh_err = DHE_SEEK_ERROR;
    process.os_error = OSError;
    goto exit_dh_clear;
  }

  for (group = 1; group <= new_modulus; group++) {
    if (Write(dh_file->sf[PRIMARY_SUBFILE].fu, dh_buffer, group_size_bytes) <
        0) {
      dh_err = DHE_INIT_DATA_ERROR;
      process.os_error = OSError;
      goto exit_dh_clear;
    }
  }

  /* Remove any excess group's disk space */

  SetFileSize(dh_file->sf[PRIMARY_SUBFILE].fu,
              GroupOffset(dh_file, ((int64)new_modulus) + 1));

  /* ----------------------------------------------------------------------
    Cast off all overflow blocks                                           */

  FDS_open(dh_file, OVERFLOW_SUBFILE);
  SetFileSize(dh_file->sf[OVERFLOW_SUBFILE].fu, dh_file->header_bytes);

  /* ----------------------------------------------------------------------
   Clear down AKs                                                         */

  for (akno = 0; akno < MAX_INDICES; akno++) {
    if ((ak_map >> akno) & 1) {
      if (!ak_clear(dh_file, AK_BASE_SUBFILE + akno))
        goto exit_dh_clear;
    }
  }

  status = TRUE;

exit_dh_clear:

  return status;
}

/* END-CODE */
