/* OP_CONFIG.C
 * Configuration parameter opcodes
 * Copyright (c) 2007 Ladybridge Systems, All Rights Reserved
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
 * rev 0.9.0 Jan 25 mab add CREATUSR allow create.account to create os user
 * END-HISTORY
 *
 * START-DESCRIPTION:
 *
 * END-DESCRIPTION
 *
 * START-CODE
 */

#include "sd.h"
#include "config.h"

/* ======================================================================
   op_config()  -  Retrieve a configuration parameter                     */

void op_config() {
  /* Stack:

      |================================|=============================|
      |            BEFORE              |           AFTER             |
      |================================|=============================|
  top |  Parameter name                | Value                       |
      |================================|=============================|

  */

  DESCRIPTOR* descr;
  char param[8 + 1];
  DESCRIPTOR result;
  char s[40] = "";

  process.status = 0;

  /* Get parameter name */

  descr = e_stack - 1;
  if (k_get_c_string(descr, param, 8) < 1)
    goto exit_op_config;

  InitDescr(&result, INTEGER);
  result.data.value = 0;

  /* !!CONFIG!! */
  if (!strcmp(param, "CMDSTACK"))
    result.data.value = sysseg->cmdstack;
  else if (!strcmp(param, "CODEPAGE"))
    result.data.value = pcfg.codepage;
  else if (!strcmp(param, "CREATUSR"))
    result.data.value = pcfg.create_user;  
  else if (!strcmp(param, "DEADLOCK"))
    result.data.value = sysseg->deadlock;
  else if (!strcmp(param, "DEBUG"))
    result.data.value = sysseg->flags >> 16;
  else if (!strcmp(param, "DUMPDIR"))
    k_put_c_string(pcfg.dumpdir, &result);
  else if (!strcmp(param, "ERRLOG"))
    result.data.value = sysseg->errlog >> 10;
  else if (!strcmp(param, "EXCLREM"))
    result.data.value = pcfg.exclrem;
  else if (!strcmp(param, "FDS"))
    result.data.value = sysseg->fds_limit;
  else if (!strcmp(param, "FILERULE"))
    result.data.value = pcfg.filerule;
  else if (!strcmp(param, "FIXUSERS")) {
    if (sysseg->fixusers_base) {
      sprintf(s, "%d,%d", sysseg->fixusers_base, sysseg->fixusers_range);
    }
    k_put_c_string(s, &result);
  } else if (!strcmp(param, "FLTDIFF")) {
    sprintf(s, "%.14lf", pcfg.fltdiff);
    k_put_c_string(s, &result);
  } else if (!strcmp(param, "FSYNC"))
    result.data.value = pcfg.fsync;
  else if (!strcmp(param, "GDI"))
    result.data.value = pcfg.gdi;
  /* 20240219 mab create-account based on type (user / group / other) */      
  else if (!strcmp(param, "GRPDIR"))
    k_put_c_string(pcfg.grpdir, &result);    
  else if (!strcmp(param, "GRPSIZE"))
    result.data.value = pcfg.grpsize;
  else if (!strcmp(param, "INTPREC"))
    result.data.value = pcfg.intprec;
  else if (!strcmp(param, "JNLMODE"))
    result.data.value = sysseg->jnlmode;
  else if (!strcmp(param, "JNLDIR"))
    k_put_c_string((char*)(sysseg->jnldir), &result);
  else if (!strcmp(param, "LPTRHIGH"))
    result.data.value = pcfg.lptrhigh;
  else if (!strcmp(param, "LPTRWIDE"))
    result.data.value = pcfg.lptrwide;
  else if (!strcmp(param, "MAXCALL"))
    result.data.value = pcfg.maxcall;
  else if (!strcmp(param, "MAXIDLEN"))
    result.data.value = sysseg->maxidlen;
  else if (!strcmp(param, "MUSTLOCK"))
    result.data.value = pcfg.must_lock;
  else if (!strcmp(param, "NETFILES"))
    result.data.value = sysseg->netfiles;
  else if (!strcmp(param, "NUMFILES"))
    result.data.value = sysseg->numfiles;
  else if (!strcmp(param, "NUMLOCKS"))
    result.data.value = sysseg->numlocks;
  else if (!strcmp(param, "NUMUSERS"))
    result.data.value = sysseg->max_users;
  else if (!strcmp(param, "OBJECTS"))
    result.data.value = pcfg.objects;
  else if (!strcmp(param, "OBJMEM"))
    result.data.value = pcfg.objmem / 1024;
  else if (!strcmp(param, "PDUMP"))
    result.data.value = sysseg->pdump;
  else if (!strcmp(param, "PORTMAP")) {
    if (sysseg->portmap_range) {
      sprintf(s, "%d,%d,%d", sysseg->portmap_base_port,
              sysseg->portmap_base_user, sysseg->portmap_range);
    }
    k_put_c_string(s, &result);
  } 
  else if (!strcmp(param, "SDCLIENT"))
    result.data.value = pcfg.sdclient_mode;
/* 20240219 mab mods to handle AF_UNIX sockets, security mode */  
  else if (!strcmp(param, "APILOGIN"))
    result.data.value = pcfg.api_login;  
  else if (!strcmp(param, "RECCACHE"))
    result.data.value = pcfg.reccache;
  else if (!strcmp(param, "RINGWAIT"))
    result.data.value = pcfg.ringwait;
  else if (!strcmp(param, "SAFEDIR"))
    result.data.value = pcfg.safedir;
  else if (!strcmp(param, "SH"))
    k_put_c_string(pcfg.sh, &result);
  else if (!strcmp(param, "SH1"))
    k_put_c_string(pcfg.sh1, &result);
  else if (!strcmp(param, "SORTMEM"))
    result.data.value = pcfg.sortmem / 1024;
  else if (!strcmp(param, "SORTMRG"))
    result.data.value = pcfg.sortmrg;
  else if (!strcmp(param, "SORTWORK"))
    k_put_c_string(pcfg.sortworkdir, &result);
  else if (!strcmp(param, "SPOOLER"))
    k_put_c_string(pcfg.spooler, &result);
  else if (!strcmp(param, "STARTUP"))
    k_put_c_string((char*)(sysseg->startup), &result);
  else if (!strcmp(param, "TEMPDIR"))
    k_put_c_string(pcfg.tempdir, &result);
  else if (!strcmp(param, "TERMINFO"))
    k_put_c_string(pcfg.terminfodir, &result);
 /* 20240219 mab create-account based on type (user / group / other) */      
  else if (!strcmp(param, "USRDIR"))
    k_put_c_string(pcfg.usrdir, &result);  
  else if (!strcmp(param, "YEARBASE"))
    result.data.value = pcfg.yearbase;
  else {
    InitDescr(&result, STRING);
    result.data.str.saddr = NULL;
    process.status = ER_NOT_FOUND;
  }

exit_op_config:
  k_dismiss();
  *(e_stack++) = result;
}

/* ======================================================================
   op_pconfig()  -  Update private config parameter value                 */

void op_pconfig() {
  /* Stack:

      |================================|=============================|
      |            BEFORE              |           AFTER             |
      |================================|=============================|
  top |  Value                         | 1 = ok, 0 = error           |
      |--------------------------------|-----------------------------|
      |  Parameter name                |                             |
      |================================|=============================|

    STATUS() = 0   success
               1   Invalid parameter name
               2   Invalid parameter value
  */

  DESCRIPTOR* descr;
  bool status = FALSE;
  char param[8 + 1];
  STRING_CHUNK* str;
  int32_t n;

  process.status = 1;

  /* Get parameter name */

  descr = e_stack - 2;
  if (k_get_c_string(descr, param, 8) < 1)
    goto exit_op_pconfig;

  descr = e_stack - 1;

  process.status = 2;

  /* !!CONFIG!! */
  if (!strcmp(param, "CODEPAGE")) {
    GetInt(descr);
    pcfg.codepage = descr->data.value;
    
  } else if (!strcmp(param, "DUMPDIR")) {
    k_get_string(descr);
    if ((str = descr->data.str.saddr) == NULL)
      goto exit_op_pconfig;
    if (str->string_len > MAX_PATHNAME_LEN)
      goto exit_op_pconfig;
    k_get_c_string(descr, pcfg.dumpdir, MAX_PATHNAME_LEN);
  } else if (!strcmp(param, "EXCLREM")) {
    GetInt(descr);
    if ((descr->data.value < 0) || (descr->data.value > 1))
      goto exit_op_pconfig;
    pcfg.exclrem = descr->data.value;
  } else if (!strcmp(param, "FILERULE")) {
    GetInt(descr);
    pcfg.filerule &= descr->data.value; /* Can only unset bits */
  } else if (!strcmp(param, "FLTDIFF")) {
    k_get_float(descr);
    if ((descr->data.float_value < 0) || (descr->data.float_value > 1))
      goto exit_op_pconfig;
    pcfg.fltdiff = descr->data.float_value;
  } else if (!strcmp(param, "FSYNC")) {
    GetInt(descr);
    if ((descr->data.value < 0) || (descr->data.value > 3))
      goto exit_op_pconfig;
    pcfg.fsync = (int16_t)(descr->data.value);
  } else if (!strcmp(param, "GDI")) {
    GetInt(descr);
    if ((descr->data.value < 0) || (descr->data.value > 1))
      goto exit_op_pconfig;
    pcfg.gdi = descr->data.value;
  } else if (!strcmp(param, "GRPSIZE")) {
    GetInt(descr);
    if ((descr->data.value < 1) || (descr->data.value > MAX_GROUP_SIZE))
      goto exit_op_pconfig;
    pcfg.grpsize = (int16_t)(descr->data.value);
  } else if (!strcmp(param, "INTPREC")) {
    GetInt(descr);
    if ((descr->data.value < 0) || (descr->data.value > 14))
      goto exit_op_pconfig;
    pcfg.intprec = (int16_t)(descr->data.value);
  } else if (!strcmp(param, "LPTRHIGH")) {
    GetInt(descr);
    if ((descr->data.value < 1) || (descr->data.value > 32767))
      goto exit_op_pconfig;
    pcfg.lptrhigh = (int16_t)(descr->data.value);
  } else if (!strcmp(param, "LPTRWIDE")) {
    GetInt(descr);
    if ((descr->data.value < 1) || (descr->data.value > 1000))
      goto exit_op_pconfig;
    pcfg.lptrwide = (int16_t)(descr->data.value);
  } else if (!strcmp(param, "MAXCALL")) {
    GetInt(descr);
    if ((descr->data.value < 10) || (descr->data.value > 1000000))
      goto exit_op_pconfig;
    pcfg.maxcall = descr->data.value;
  } else if (!strcmp(param, "MUSTLOCK")) {
    GetInt(descr);
    if ((descr->data.value < 0) || (descr->data.value > 1))
      goto exit_op_pconfig;
    pcfg.must_lock = (descr->data.value != 0);
  } else if (!strcmp(param, "OBJECTS")) {
    GetInt(descr);
    if (descr->data.value < 0)
      goto exit_op_pconfig;
    pcfg.objects = (int16_t)(descr->data.value);
  } else if (!strcmp(param, "OBJMEM")) {
    GetInt(descr);
    if (descr->data.value < 0)
      goto exit_op_pconfig;
    pcfg.objmem = descr->data.value * 1024L;
  } else if (!strcmp(param, "SDCLIENT")) {
    GetInt(descr);
    if ((descr->data.value < pcfg.sdclient_mode) || (descr->data.value > 2))
      goto exit_op_pconfig;
    pcfg.sdclient_mode = descr->data.value;
  } else if (!strcmp(param, "RECCACHE")) {
    GetInt(descr);
    if ((descr->data.value < 0) || (descr->data.value > 32))
      goto exit_op_pconfig;
    pcfg.reccache = (int16_t)(descr->data.value);
    init_record_cache();
  } else if (!strcmp(param, "RINGWAIT")) {
    GetInt(descr);
    if ((descr->data.value < 0) || (descr->data.value > 1))
      goto exit_op_pconfig;
    pcfg.ringwait = descr->data.value;
  } else if (!strcmp(param, "SAFEDIR")) {
    GetInt(descr);
    if ((descr->data.value < 0) || (descr->data.value > 1))
      goto exit_op_pconfig;
    pcfg.safedir = (descr->data.value != 0);
  } else if (!strcmp(param, "SH")) {
    k_get_string(descr);
    /* the below if() was missing from this block -gwb 22Feb20 */
    /* when missing, it triggers the warning:
     * warning: ‘str’ may be used uninitialized in this function [-Wmaybe-uninitialized]
     */    
    if ((str = descr->data.str.saddr) == NULL)
      goto exit_op_pconfig;    
    if (str->string_len > MAX_SH_CMD_LEN)
      goto exit_op_pconfig;
    k_get_c_string(descr, pcfg.sh, MAX_SH_CMD_LEN);
  } else if (!strcmp(param, "SH1")) {
    k_get_string(descr);
    /* the below if() was missing from this block -gwb 22Feb20 */
    /* when missing, it triggers the warning:
     * warning: ‘str’ may be used uninitialized in this function [-Wmaybe-uninitialized]
     */
    if ((str = descr->data.str.saddr) == NULL)
      goto exit_op_pconfig;    
    if (str->string_len > MAX_SH_CMD_LEN)
      goto exit_op_pconfig;
    k_get_c_string(descr, pcfg.sh1, MAX_SH_CMD_LEN);
  } else if (!strcmp(param, "SORTMEM")) {
    GetInt(descr);
    if (descr->data.value < 4)
      goto exit_op_pconfig;
    pcfg.sortmem = descr->data.value * 1024L;
  } else if (!strcmp(param, "SORTMRG")) {
    GetInt(descr);
    if ((descr->data.value < 2) || (descr->data.value > MAX_SORTMRG))
      goto exit_op_pconfig;
    pcfg.sortmrg = (int16_t)(descr->data.value);
  } else if (!strcmp(param, "SORTWORK")) {
    k_get_string(descr);
    if ((str = descr->data.str.saddr) == NULL)
      goto exit_op_pconfig;
    if (str->string_len > MAX_PATHNAME_LEN)
      goto exit_op_pconfig;
    k_get_c_string(descr, pcfg.sortworkdir, MAX_PATHNAME_LEN);
  } else if (!strcmp(param, "SPOOLER")) {
    k_get_string(descr);
    if ((str = descr->data.str.saddr) == NULL)
      goto exit_op_pconfig;
    if (str->string_len > MAX_PATHNAME_LEN)
      goto exit_op_pconfig;
    k_get_c_string(descr, pcfg.spooler, MAX_PATHNAME_LEN);
  } else if (!strcmp(param, "TEMPDIR")) {
    k_get_string(descr);
    if ((str = descr->data.str.saddr) == NULL)
      goto exit_op_pconfig;
    if (str->string_len > MAX_PATHNAME_LEN)
      goto exit_op_pconfig;
    k_get_c_string(descr, pcfg.tempdir, MAX_PATHNAME_LEN);
  } else if (!strcmp(param, "TERMINFO")) {
    k_get_string(descr);
    if ((str = descr->data.str.saddr) == NULL)
      goto exit_op_pconfig;
    if (str->string_len > MAX_PATHNAME_LEN)
      goto exit_op_pconfig;
    k_get_c_string(descr, pcfg.terminfodir, MAX_PATHNAME_LEN);
  } else if (!strcmp(param, "YEARBASE")) {
    GetInt(descr);
    n = descr->data.value;
    if ((n < 1900) || (n > 2500))
      goto exit_op_pconfig;
    pcfg.yearbase = (int16_t)(descr->data.value);
  } else {
    process.status = 1;
    goto exit_op_pconfig;
  }

  process.status = 0;
  status = TRUE;

exit_op_pconfig:
  k_dismiss();
  k_dismiss();

  InitDescr(e_stack, INTEGER);
  (e_stack++)->data.value = status;
}

/* END-CODE */
