/* DEBUG.H
 * Debugger include file
 * Copyright (c) 2005 Ladybridge Systems, All Rights Reserved
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
 *
 * END-DESCRIPTION
 *
 * START-CODE
 */

Public bool in_debugger init(FALSE);

Public int32_t debug_status;      /* Saved process.status */
Public int32_t debug_inmat;       /* Saved process.inmat */
Public bool debug_suppress_como;   /* Saved tio.suppress_como */
Public bool debug_hush;            /* Saved tio.hush */
Public bool debug_capturing;       /* Saved capturing */
Public char debug_prompt_char;     /* Saved tio.prompt_char */
Public int32_t debug_dsp_line;    /* Saved tio.dsp.line */
Public bool debug_dsp_paginate;    /* Saved tio.dsp.paginate */
Public int32_t debug_os_error;    /* Saved process.os_error */

/* Event codes (additive) */

#define DE_WATCH            1     /* Watch variable has changed */
#define DE_BREAKPOINT       2     /* At breakpoint */

/* END-CODE */

