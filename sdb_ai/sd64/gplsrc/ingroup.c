/* INGROUP.C
 * Test whether user is in a named group.
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
 * END-HISTORY
 *
 * START-DESCRIPTION:
 *
 * END-DESCRIPTION
 *
 * START-CODE
 */

#include <sys/types.h>
#include <stdlib.h>
#include <string.h>

#include <unistd.h>
#include <grp.h>

typedef struct GROUP_INFO GROUP_INFO;
struct GROUP_INFO {
  GROUP_INFO* next;
  int16_t member;
  char name[1];
};

static GROUP_INFO* gi_head = NULL;

/* ====================================================================== */

int16_t in_group(char* group_name) {
  int16_t status = 0;
  GROUP_INFO* gi;
  struct group* grp;
  /* Modified by Composer AI - 2026/06/10.
     group_id holds a gid_t and is compared with getegid() and gid_t array
     elements; declare it with the correct (unsigned) type to avoid
     signed/unsigned comparison issues. */
  /* int group_id; */
  gid_t group_id;
  /* -------------------- */
  static int num_groups = 0;
  gid_t* groups = NULL;
  int i;  /* Fix for Issue #16 */

  /* Have we already identified membership of this group? */

  for (gi = gi_head; gi != NULL; gi = gi->next) {
    if (!strcmp(group_name, gi->name))
      return gi->member;
  }

  /* We do not already know about this one */

  grp = getgrnam(group_name);
  if (grp != NULL) {
    group_id = grp->gr_gid;

    if (group_id == getegid()) {
      status = 1;
    } else { /* Not primary group */
      if (groups == NULL) {
        num_groups = getgroups(0, NULL);
        groups = (gid_t*)malloc(num_groups * sizeof(gid_t));
        if (groups != NULL) {
          num_groups = getgroups(num_groups, groups);
        }
      }

      /* Modified by Composer AI - 2026/06/10.
         If the malloc() above fails, groups is NULL while num_groups can be
         non-zero (it is static), so the loop dereferenced a NULL pointer.
         Only scan the list when the allocation succeeded. */
      /* for (i = 0; i < num_groups; i++) {
        if (groups[i] == group_id) {
          status = 1;
          break;
        }
      } */
      if (groups != NULL) {
        for (i = 0; i < num_groups; i++) {
          if (groups[i] == group_id) {
            status = 1;
            break;
          }
        }
      }
      /* -------------------- */
    }
  }

  /* Modified by Composer AI - 2026/06/10.
     groups is allocated on every call but was never released - a memory
     leak. Free it before returning. */
  if (groups != NULL) {
    free(groups);
  }
  /* -------------------- */

  /* Add this group name to our list of checked names */

  /* Modified by Composer AI - 2026/06/10.
     malloc() result was used without a NULL check, crashing on allocation
     failure. If the allocation fails, skip caching the result (only costs
     a repeat lookup next time) and return the computed status. */
  /* gi = (GROUP_INFO*)malloc(sizeof(GROUP_INFO) + strlen(group_name));
  strcpy(gi->name, group_name);
  gi->member = status;
  gi->next = gi_head;
  gi_head = gi; */
  gi = (GROUP_INFO*)malloc(sizeof(GROUP_INFO) + strlen(group_name));
  if (gi != NULL) {
    strcpy(gi->name, group_name);
    gi->member = status;
    gi->next = gi_head;
    gi_head = gi;
  }
  /* -------------------- */

  return status;
}

/* END-CODE */
