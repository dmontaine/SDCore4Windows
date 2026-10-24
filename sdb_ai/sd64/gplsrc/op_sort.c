/* OP_SORT.C
 * Sort handling opcodes
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
 * 18 Oct 26 Windows port - from Linux ddd991e (16 Oct 26): Expose user-callable SORT(), SORTADD, SORTCLEAR, SORTDATA(),
 *               SORTNEXT() with multiple active sort sessions and all SRT$
 *               modes (QM4 Fixes item 371).
 * 18 Oct 26 Windows port - from Linux 8ff2bdc (16 Oct 26): The key being inserted is read as a number ONCE per level (KEY_NUM, key_as_number()) and not at every
 *               comparison: the rewrite had made numeric sorts of 120,000 keys 28-35% slower to load than ac509e4.
 * 18 Oct 26 Windows port - from Linux ddd991e (16 Oct 26): Audit of that change: sess_sortdata() starts its target string before the merge again (a merge that
 *               failed reached ts_terminate() with no ts_init() behind it); messages 12403 (not a sort variable) and
 *               12404 (all 255 sorts open) in the place of 1487 and 1482, which named the wrong thing.
 * 23 Oct 26 Windows port - from Linux e07c616 (20 Oct 26): A run of the sort is collected in arrival order and sorted once (array_add /
 *               array_finalize) instead of being walked into an unbalanced tree node by node: 100,000 equal or ordered keys took
 *               150-230 s, now well under a second.  Same output, byte for byte: the order of equal keys (newest first), the
 *               work files and the merge are unchanged.  UNIQUE, COMPOUND and STRICT sorts, and any run in which a right
 *               justified level has met both numbers and text (where the comparison is not transitive), keep the classic insertion.
 * rev 0.9.0 Jan 25 mab catch null key id in op_sortdata()
 * 18 Oct 26 Windows port - from Linux 7aba47d (16 Oct 26): Disk record lengths are 32 bits (item 455), fields padded to 4.
 * 31 Dec 23 SD launch - prior history suppressed
 * END-HISTORY
 *
 * START-DESCRIPTION:
 *
 * Opcodes:
 *    op_sortclr   SORTCLEAR   Clear sort data (tidy up after sort complete)
 *    op_sortdata  SORTDATA    Retrieve all sort data as dynamic array
 *    op_sortinit  SORTINIT    Initialise a sort
 *    op_sortnext  SORTNEXT    Retrieve next item from sort data
 *    op_sortadd   SORTADD     Add an entry to a sort tree
 *
 * XFUN handlers (QM4 Fixes item 371):
 *    x_sort       SORT(key.count, {MAT} flags)
 *    x_sortadd    SORTADD sortvar, {MAT} keys {, data}
 *    x_sortclear  SORTCLEAR sortvar
 *    x_sortdata   SORTDATA(sortvar {, max.items})
 *    x_sortnext   SORTNEXT(sortvar {, {MAT} keys})
 *
 * END-DESCRIPTION
 *
 * START-CODE
 */

/* Modified by Composer AI - 2026/06/10.
   k_error() never returns, but the analyzer cannot see that across
   translation units. */
void k_error(char msg[], ...) __attribute__((noreturn));
/* -------------------- */

#include "sd.h"
#include "config.h"

#define DISK_BUFFER_SIZE 4096

/* SRT$ flag definitions matching sdsys/syscom/keys.h */
#define SRT_LEFT        0
#define SRT_RIGHT       1
#define SRT_COMPOUND    2
#define SRT_RIGHT_FLOAT 3
#define SRT_STRICT      4
#define SRT_MODE_MASK   0x0F
#define SRT_DESCENDING  0x10 /* 16 */
#define SRT_UNIQUE      0x20 /* 32 */
#define SRT_NOCASE      0x40 /* 64 */
#define SRT_DATA        0x80 /* 128 */

/* A key read as a number once, for a comparison that is made again and again against the same key (sess_insert_bte) */
typedef struct KEY_NUM {
  bool is_num; /* the key reads as a number in the mode it is sorted in */
  double val;  /* ...and this is the number */
} KEY_NUM;

typedef struct SORT_SESSION {
  bool in_use;
  int16_t session_id;                /* 0 = legacy internal sort, >= 1 = user SORT() */
  bool legacy_bt;                    /* TRUE for session 0 (SORTINIT) */
  BTREE_ELEMENT* sort_tree;          /* Head of sort tree */
  int16_t sort_keys;                 /* Number of keys */
  u_char sort_flags[MAX_SORT_KEYS];  /* SRT$ flags per key */
  bool sort_has_data;                /* SRT_DATA set in flags[0]? */
  int32_t sort_size;                 /* Memory data size (bytes) */
  BTREE_ELEMENT* sort_ptr;           /* Pointer to next element */
  bool sorting;                      /* True while collecting data */
  int16_t sortwork;                  /* Sort work subfile counter */
  char* sort_buff;                   /* Disk read buffer */
  int32_t sort_buff_bytes;           /* Bytes in buffer */
  int32_t sort_buff_offset;          /* Offset of next byte to extract */
  OSFILE sort_fu;                    /* File unit for sort file */

  /* An ARRAY run (20 Oct 26): the nodes of the run are kept in the order they arrived and sorted once, when the run is read
     or written to a work file, instead of being walked into the tree one at a time (which is quadratic on equal keys and on
     ordered input).  The positional initialiser of legacy_session above stops before these, so they start as zero. */
  BTREE_ELEMENT** pend;              /* the run's nodes, in arrival order */
  int32_t pend_n;
  int32_t pend_cap;
  double* pend_num;                  /* pend_cap * nrlev numbers: the right justified keys, each read once */
  int16_t nrlev;                     /* right justified levels */
  signed char rl_idx[MAX_SORT_KEYS]; /* level -> column of pend_num, -1 for a left justified level */
  u_char lvl_seen[MAX_SORT_KEYS];    /* 1: numeric keys seen at this level, 2: non-numeric keys seen (3 = both) */
  u_char run_kind;                   /* RK_NONE, RK_ARRAY or RK_CLASSIC */
  bool tree_built;                   /* RK_ARRAY: sort_tree holds the nodes, sorted */
} SORT_SESSION;

#define RK_NONE 0    /* no run has begun */
#define RK_ARRAY 1   /* nodes are collected, then sorted once */
#define RK_CLASSIC 2 /* nodes are walked into the tree one by one, as before 20 Oct 26 */

#define MAX_USER_SORTS 256

Private SORT_SESSION legacy_session = {
  FALSE, 0, TRUE, NULL, 0, {0}, FALSE, 0, NULL, FALSE, 0,
  NULL, 0, 0, INVALID_FILE_HANDLE
};

Private SORT_SESSION* user_sorts[MAX_USER_SORTS] = {NULL};

/* Disk record fields.  Lengths are int32_t and every area is padded to a
   multiple of four bytes.  The lengths are read and written through memcpy
   so that no alignment is assumed.                                         */

#define pad4(n) (((n) + 3) & ~3)
#define LEN_BYTES 4 /* Size of a length value on disk */

Private int32_t get32(const char* p) {
  int32_t v;
  memcpy(&v, p, sizeof(v));
  return v;
}

Private void put32(char* p, int32_t v) {
  memcpy(p, &v, sizeof(v));
}

void op_sortclr(void);
void free_sort_session(int16_t id);
void x_sort(void);
void x_sortadd(void);
void x_sortclear(void);
void x_sortdata(void);
void x_sortnext(void);

Private void clear_sort_session(SORT_SESSION* sess);
Private SORT_SESSION* alloc_sort_session(void);
Private SORT_SESSION* get_sort_session(DESCRIPTOR* d);
Private int sort_compare_keys(const char* k1, const char* k2, u_char flags, bool legacy_bt, const KEY_NUM* k1num);
Private void sess_insert_bte(SORT_SESSION* sess, BTREE_ELEMENT* new_bte, int32_t size);
Private void sess_sortdata(SORT_SESSION* sess, int32_t max_items, bool require_sorting);
Private bool sortmerge(SORT_SESSION* sess);
Private bool flush_sort_tree(SORT_SESSION* sess);
Private bool merge_sort_files(SORT_SESSION* sess);
Private void make_workfile_path(SORT_SESSION* sess, int subfile, char* pathname, const char* caller);
Private char* read_merge_record(OSFILE fu,
                                char* buff,
                                int32_t* buff_bytes,
                                int32_t* buff_offset,
                                bool* temp);
Private bool write_merge_record(char* rec,
                                OSFILE fu,
                                char* buff,
                                int32_t* buff_bytes,
                                bool temp);
Private bool tree_insert(SORT_SESSION* sess, BTREE_ELEMENT* new_bte);
Private void array_release(SORT_SESSION* sess);
Private void free_pending_nodes(SORT_SESSION* sess);
Private void array_finalize(SORT_SESSION* sess);

/* ======================================================================
   make_workfile_path()  -  Format sort workfile path for a session       */

Private void make_workfile_path(SORT_SESSION* sess,
                                int subfile,
                                char* pathname,
                                const char* caller) {
  int n;
  if (sess->session_id == 0) {
    n = snprintf(pathname, MAX_PATHNAME_LEN + 1, "%s%c~SDS%d.%d",
                 pcfg.sortworkdir, DS, (int)process.user_no, subfile);
  } else {
    n = snprintf(pathname, MAX_PATHNAME_LEN + 1, "%s%c~SDS%d_%d.%d",
                 pcfg.sortworkdir, DS, (int)process.user_no,
                 (int)sess->session_id, subfile);
  }
  if (n >= (MAX_PATHNAME_LEN + 1)) {
    k_error("Overflowed path/filename max length in %s!", caller);
  }
}

/* ======================================================================
   clear_sort_session()  -  Free tree, buffer, and disk work files        */

Private void clear_sort_session(SORT_SESSION* sess) {
  char pathname[MAX_PATHNAME_LEN + 1];
  char prefix[32];
  int16_t prefix_len;
  DIR* dfu;
  struct dirent* dp;

  if (sess == NULL)
    return;

  /* Cast off all sort tree elements */

  free_pending_nodes(sess); /* nodes of an array run that were never put in the tree */
  if (sess->sort_tree != NULL) {
    free_btree_element(sess->sort_tree, sess->sort_keys);
    sess->sort_tree = NULL;
  }
  array_release(sess);

  /* Free the disk based sort read buffer */

  if (sess->sort_buff != NULL) {
    k_free(sess->sort_buff);
    sess->sort_buff = NULL;
  }

  /* Close the file for a disk based sort */

  if (ValidFileHandle(sess->sort_fu)) {
    CloseFile(sess->sort_fu);
    sess->sort_fu = INVALID_FILE_HANDLE;
  }

  /* Delete any sort work files (only if we have done a disk based sort) */

  if (sess->sortwork) {
    if ((dfu = opendir(pcfg.sortworkdir)) == NULL) {
      k_error(sysmsg(1480), pcfg.sortworkdir, errno);
    }

    if (sess->session_id == 0) {
      prefix_len = (int16_t)sprintf(prefix, "~SDS%d.", (int)process.user_no);
    } else {
      prefix_len = (int16_t)sprintf(prefix, "~SDS%d_%d.",
                                    (int)process.user_no,
                                    (int)sess->session_id);
    }

    while ((dp = readdir(dfu)) != NULL) {
      if (memcmp(dp->d_name, prefix, prefix_len) == 0) {
        if (snprintf(pathname, MAX_PATHNAME_LEN + 1, "%s%c%s", pcfg.sortworkdir,
                     DS, dp->d_name) >= (MAX_PATHNAME_LEN + 1)) {
          closedir(dfu);
          k_error("Overflowed path/filename max length in clear_sort_session()!");
        } else {
          remove(pathname);
        }
      }
    }

    closedir(dfu);
    sess->sortwork = 0;
  }

  sess->sort_size = 0;
  sess->sort_ptr = NULL;
  sess->sorting = FALSE;
  sess->sort_buff_bytes = 0;
  sess->sort_buff_offset = 0;
}

/* ======================================================================
   alloc_sort_session()  -  Allocate a user SORT_SESSION slot             */

Private SORT_SESSION* alloc_sort_session() {
  int16_t id;
  SORT_SESSION* sess;

  for (id = 1; id < MAX_USER_SORTS; id++) {
    if (user_sorts[id] == NULL) {
      sess = (SORT_SESSION*)k_alloc(61, sizeof(SORT_SESSION));
      if (sess == NULL)
        k_error(sysmsg(1482));
      memset(sess, 0, sizeof(SORT_SESSION));
      sess->in_use = TRUE;
      sess->session_id = id;
      sess->sort_fu = INVALID_FILE_HANDLE;
      user_sorts[id] = sess;
      return sess;
    }
  }

  k_error(sysmsg(12404)); /* all 255 slots are taken (was 1482, "Insufficient memory for sort element") */
}

/* ======================================================================
   free_sort_session()  -  Release a user SORT_SESSION when sortvar freed */

void free_sort_session(int16_t id) {
  if ((id >= 1) && (id < MAX_USER_SORTS) && (user_sorts[id] != NULL)) {
    clear_sort_session(user_sorts[id]);
    k_free(user_sorts[id]);
    user_sorts[id] = NULL;
  }
}

/* ======================================================================
   get_sort_session()  -  Resolve a sortvar descriptor to SORT_SESSION*   */

Private SORT_SESSION* get_sort_session(DESCRIPTOR* d) {
  int16_t id;

  while (d->type == ADDR)
    d = d->data.d_addr;
  /* 12403 "Not a sort variable" (was 1487, "SORTDATA executed when not sorting", which named the wrong statement) */
  if ((d->type != BTREE) || (d->data.btree == NULL))
    k_error(sysmsg(12403));
  id = d->data.btree->pad;
  if ((id < 1) || (id >= MAX_USER_SORTS) || (user_sorts[id] == NULL))
    k_error(sysmsg(12403));
  return user_sorts[id];
}

/* ======================================================================
   Key comparison helpers for SRT$ modes                                  */

Private int cmp_char(u_char c1, u_char c2, bool nocase) {
  if (nocase)
    return (int)UpperCase(c1) - (int)UpperCase(c2);
  return (int)c1 - (int)c2;
}

/* Is p a non-empty integer string (optional + or - followed by >= 1 digits)? */
Private bool is_int_key(const char* p, double* val) {
  bool neg = FALSE;
  double v = 0.0;
  int digits = 0;

  if ((p == NULL) || (*p == '\0'))
    return FALSE;
  if (*p == '-') {
    neg = TRUE;
    p++;
  } else if (*p == '+') {
    p++;
  }
  if (!IsDigit(*p))
    return FALSE;
  while (IsDigit(*p)) {
    if (++digits > 15)
      return FALSE;
    v = (v * 10.0) + (double)(*p - '0');
    p++;
  }
  if (*p != '\0')
    return FALSE;
  *val = neg ? -v : v;
  return TRUE;
}

/* Is p a non-empty floating point number string (optional spaces, + or -, digits/decimal)? */
Private bool is_float_key(const char* p, double* val) {
  bool neg = FALSE;
  int digits = 0;
  int frac_digits = 0;
  double v = 0.0;
  double dplace;

  if (p == NULL)
    return FALSE;
  while (*p == ' ')
    p++;
  if (*p == '\0')
    return FALSE;
  if (*p == '-') {
    neg = TRUE;
    p++;
  } else if (*p == '+') {
    p++;
  }
  while (IsDigit(*p)) {
    if (++digits > 15)
      return FALSE;
    v = (v * 10.0) + (double)(*p - '0');
    p++;
  }
  if (*p == '.') {
    p++;
    dplace = 0.1;
    while (IsDigit(*p)) {
      frac_digits++;
      v += (double)(*p - '0') * dplace;
      dplace /= 10.0;
      p++;
    }
  }
  while (*p == ' ')
    p++;
  if ((*p != '\0') || ((digits == 0) && (frac_digits == 0)))
    return FALSE;
  *val = neg ? -v : v;
  return TRUE;
}

Private double parse_compound_num(const char* s, size_t len) {
  bool neg = FALSE;
  size_t i = 0;
  double val = 0.0;

  if ((len > 0) && ((s[0] == '-') || (s[0] == '+'))) {
    neg = (s[0] == '-');
    i = 1;
  }
  for (; i < len; i++) {
    val = (val * 10.0) + (double)(s[i] - '0');
  }
  return neg ? -val : val;
}

Private void next_compound_elem(const char** pp,
                                bool at_start,
                                const char** start_out,
                                size_t* len_out,
                                bool* is_num_out) {
  const char* p = *pp;
  bool is_num = IsDigit(*p) ||
                (at_start && ((*p == '-') || (*p == '+')) && IsDigit(*(p + 1)));
  *start_out = p;
  *is_num_out = is_num;
  if (is_num) {
    if ((*p == '-') || (*p == '+'))
      p++;
    while (IsDigit(*p))
      p++;
  } else {
    p++;
    while ((*p != '\0') && !IsDigit(*p))
      p++;
  }
  *len_out = (size_t)(p - *start_out);
  *pp = p;
}

/* Does k read as a number in this mode?  Only the right justified modes ask: SRT_RIGHT takes integers, SRT_RIGHT_FLOAT any
   number (the internal sort, legacy_bt, reads them with strdbl() as it always did).  A null key reads as 0 for the internal
   sort and as text for the others. */
Private bool key_as_number(const char* k, u_char mode, bool legacy_bt, double* val) {
  if (mode == SRT_RIGHT)
    return is_int_key(k, val);
  if (mode == SRT_RIGHT_FLOAT)
    return legacy_bt ? strdbl((char*)(k ? k : ""), val) : is_float_key(k, val);
  return FALSE;
}

/* A key that is compared again and again against the keys of a tree (the one being inserted) is read as a number ONCE and the
   answer passed in: the first version of this function read it afresh at every comparison, which made numeric sorts of
   120,000 keys 28-35% slower to load than before the rewrite (16 Oct 26 audit).  k1num may be NULL, as in the merge, where
   both keys come off the disk and are read each time. */
Private int sort_compare_keys(const char* k1,
                              const char* k2,
                              u_char flags,
                              bool legacy_bt,
                              const KEY_NUM* k1num) {
  u_char mode = flags & SRT_MODE_MASK;
  bool desc = (flags & SRT_DESCENDING) != 0;
  bool nocase = (flags & SRT_NOCASE) != 0;
  int d = 0;
  double v1, v2;
  bool num1;
  int32_t n;

  if (k1 == NULL)
    k1 = "";
  if (k2 == NULL)
    k2 = "";

  switch (mode) {
    case SRT_RIGHT:
    case SRT_RIGHT_FLOAT:
      if (k1num != NULL) {
        num1 = k1num->is_num;
        v1 = k1num->val;
      } else {
        num1 = key_as_number(k1, mode, legacy_bt, &v1);
      }
      if (num1 && key_as_number(k2, mode, legacy_bt, &v2)) {
        d = (v1 > v2) ? 1 : (v1 < v2) ? -1 : 0;
        break;
      }
      /* not both numbers: the shorter key is padded on the left with spaces */
      n = (int32_t)strlen(k1) - (int32_t)strlen(k2);
      if (n > 0) {
        while (n--) {
          if ((d = cmp_char((u_char)*k1++, ' ', nocase)) != 0)
            goto done;
        }
      } else if (n < 0) {
        while (n++) {
          if ((d = cmp_char(' ', (u_char)*k2++, nocase)) != 0)
            goto done;
        }
      }
      while (*k1 && *k2) {
        if ((d = cmp_char((u_char)*k1++, (u_char)*k2++, nocase)) != 0)
          goto done;
      }
      if (*k1)
        d = 1;
      else if (*k2)
        d = -1;
      break;

    case SRT_COMPOUND:
    case SRT_STRICT: {
      const char* p1 = k1;
      const char* p2 = k2;
      bool first = TRUE;
      while ((*p1 != '\0') && (*p2 != '\0')) {
        const char* s1;
        const char* s2;
        size_t l1, l2;
        bool num1, num2;
        next_compound_elem(&p1, first, &s1, &l1, &num1);
        next_compound_elem(&p2, first, &s2, &l2, &num2);
        first = FALSE;
        if (num1 && !num2) {
          d = -1;
          break;
        }
        if (!num1 && num2) {
          d = 1;
          break;
        }
        if (num1) {
          v1 = parse_compound_num(s1, l1);
          v2 = parse_compound_num(s2, l2);
          if (v1 < v2) {
            d = -1;
            break;
          }
          if (v1 > v2) {
            d = 1;
            break;
          }
          if (mode == SRT_STRICT) {
            if (l1 != l2) {
              d = (l1 < l2) ? -1 : 1;
              break;
            }
            for (size_t k = 0; k < l1; k++) {
              if ((d = (int)(u_char)s1[k] - (int)(u_char)s2[k]) != 0)
                break;
            }
            if (d != 0)
              break;
          }
        } else {
          size_t min_l = (l1 < l2) ? l1 : l2;
          for (size_t k = 0; k < min_l; k++) {
            if ((d = cmp_char((u_char)s1[k], (u_char)s2[k], nocase)) != 0)
              break;
          }
          if ((d == 0) && (l1 != l2))
            d = (l1 < l2) ? -1 : 1;
          if (d != 0)
            break;
        }
      }
      if (d == 0) {
        if (*p1 != '\0')
          d = 1;
        else if (*p2 != '\0')
          d = -1;
      }
      break;
    }

    default: /* SRT_LEFT */
      while (*k1 && *k2) {
        if ((d = cmp_char((u_char)*k1++, (u_char)*k2++, nocase)) != 0)
          goto done;
      }
      if (*k1)
        d = 1;
      else if (*k2)
        d = -1;
      break;
  }

done:
  if (desc)
    d = -d;
  return (d < 0) ? -1 : (d > 0) ? 1 : 0;
}

/* ======================================================================
   Array runs (20 Oct 26).

   The classic insertion walks the tree from the root for every node, and the tree is not balanced: a run of equal keys makes
   a chain on the left that every equal key walks to its end, and ordered or reversed keys make a chain on one side, so
   100,000 equal or ordered keys took 150-230 seconds (SELECT file BY a field of five values, 94 seconds).  An array run
   keeps the nodes in the order they arrive and sorts them once, when the run is read or written to a work file.

   THE ORDER IT GIVES IS THE ORDER THE TREE GAVE.  The tree puts a new node before every node it compares equal to, so the
   tree reads out in key order with equal keys NEWEST FIRST.  The sort below is stable over the nodes taken newest first, which
   is the same order.  That holds only while the comparison is a consistent order, and it is not for a right justified level
   that has met both numbers and text ("0010" < "11" by value, "11" < "1x" as text, "1x" < "0010" as text padded on the left,
   observed 20 Oct 26): there the order depends on the shape of the tree.  So a run falls back to the classic tree, rebuilt
   from the nodes in the order they came, as soon as a level has seen both, and a sort with a UNIQUE, COMPOUND or STRICT
   level never uses an array run.  The run's records, the flush points (sort_size) and the merge are untouched, so a sort that
   spills writes the same work files as before. */

Private bool run_is_array_ok(SORT_SESSION* sess) {
  int16_t i;
  u_char mode;

  for (i = 0; i < sess->sort_keys; i++) {
    mode = sess->sort_flags[i] & SRT_MODE_MASK;
    if ((sess->sort_flags[i] & SRT_UNIQUE) || ((mode != SRT_LEFT) && (mode != SRT_RIGHT) && (mode != SRT_RIGHT_FLOAT)))
      return FALSE;
  }
  return TRUE;
}

/* Free the arrays only (the nodes are in the tree or have been freed) and end the run */
Private void array_release(SORT_SESSION* sess) {
  if (sess->pend != NULL)
    k_free(sess->pend);
  if (sess->pend_num != NULL)
    k_free(sess->pend_num);
  sess->pend = NULL;
  sess->pend_num = NULL;
  sess->pend_n = 0;
  sess->pend_cap = 0;
  sess->run_kind = RK_NONE;
  sess->tree_built = FALSE;
}

/* The nodes of an array run that are not in the tree yet */
Private void free_pending_nodes(SORT_SESSION* sess) {
  int32_t i;
  int16_t k;
  BTREE_ELEMENT* bte;

  if ((sess->run_kind == RK_ARRAY) && !sess->tree_built) {
    for (i = 0; i < sess->pend_n; i++) {
      bte = sess->pend[i];
      if (bte->data != NULL)
        k_free(bte->data);
      for (k = 0; k < sess->sort_keys; k++) {
        if (bte->key[k] != NULL)
          k_free(bte->key[k]);
      }
      k_free(bte);
    }
    sess->pend_n = 0;
  }
}

Private void array_start(SORT_SESSION* sess) {
  int16_t i;
  u_char mode;

  array_release(sess);
  sess->nrlev = 0;
  for (i = 0; i < sess->sort_keys; i++) {
    mode = sess->sort_flags[i] & SRT_MODE_MASK;
    sess->lvl_seen[i] = 0;
    sess->rl_idx[i] = ((mode == SRT_RIGHT) || (mode == SRT_RIGHT_FLOAT)) ? (signed char)(sess->nrlev++) : (signed char)-1;
  }
  sess->run_kind = RK_ARRAY;
  sess->tree_built = FALSE;
}

/* Take one more node into an array run.  FALSE (and the node not taken) if the run has to become a classic one: a right
   justified level would have seen both numbers and text, or there is no memory for the arrays. */
Private bool array_add(SORT_SESSION* sess, BTREE_ELEMENT* bte) {
  double val[MAX_SORT_KEYS];
  u_char seen[MAX_SORT_KEYS];
  int16_t i;
  bool isnum;

  for (i = 0; i < sess->sort_keys; i++) {
    if (sess->rl_idx[i] < 0)
      continue;
    isnum = key_as_number(bte->key[i], sess->sort_flags[i] & SRT_MODE_MASK, sess->legacy_bt, &(val[i]));
    seen[i] = sess->lvl_seen[i] | (isnum ? 1 : 2);
    if (seen[i] == 3)
      return FALSE;
  }

  if (sess->pend_n == sess->pend_cap) {
    int32_t ncap = (sess->pend_cap > 0) ? (sess->pend_cap * 2) : 1024;
    BTREE_ELEMENT** np = (BTREE_ELEMENT**)k_alloc(117, (size_t)ncap * sizeof(BTREE_ELEMENT*));
    double* nn = NULL;

    if (sess->nrlev > 0)
      nn = (double*)k_alloc(118, (size_t)ncap * sess->nrlev * sizeof(double));
    if ((np == NULL) || ((sess->nrlev > 0) && (nn == NULL))) {
      if (np != NULL)
        k_free(np);
      if (nn != NULL)
        k_free(nn);
      return FALSE;
    }
    if (sess->pend_n > 0) {
      memcpy(np, sess->pend, (size_t)sess->pend_n * sizeof(BTREE_ELEMENT*));
      if (sess->nrlev > 0)
        memcpy(nn, sess->pend_num, (size_t)sess->pend_n * sess->nrlev * sizeof(double));
    }
    if (sess->pend != NULL)
      k_free(sess->pend);
    if (sess->pend_num != NULL)
      k_free(sess->pend_num);
    sess->pend = np;
    sess->pend_num = nn;
    sess->pend_cap = ncap;
  }

  for (i = 0; i < sess->sort_keys; i++) {
    if (sess->rl_idx[i] < 0)
      continue;
    sess->lvl_seen[i] = seen[i];
    sess->pend_num[(size_t)sess->pend_n * sess->nrlev + sess->rl_idx[i]] = (seen[i] == 1) ? val[i] : 0.0;
  }
  sess->pend[sess->pend_n++] = bte;
  if (sess->tree_built)
    tree_insert(sess, bte); /* the run has been read once already: an ordinary insertion keeps the tree (no UNIQUE here) */
  return TRUE;
}

/* End an array run: the nodes go into the tree in the order they came, as the classic insertion would have put them */
Private void array_to_classic(SORT_SESSION* sess) {
  int32_t i;
  BTREE_ELEMENT* bte;

  sess->sort_tree = NULL;
  for (i = 0; i < sess->pend_n; i++) {
    bte = sess->pend[i];
    bte->parent = NULL;
    bte->left = NULL;
    bte->right = NULL;
  }
  for (i = 0; i < sess->pend_n; i++)
    tree_insert(sess, sess->pend[i]);
  array_release(sess);
  sess->run_kind = RK_CLASSIC;
}

/* Compare two nodes of the run by their arrival numbers: the keys at every level, as the tree compared them */
Private int pend_cmp(SORT_SESSION* sess, int32_t a, int32_t b) {
  BTREE_ELEMENT* ba = sess->pend[a];
  BTREE_ELEMENT* bb = sess->pend[b];
  int16_t i;
  int d;
  double v1;
  double v2;

  for (i = 0; i < sess->sort_keys; i++) {
    if ((sess->rl_idx[i] >= 0) && (sess->lvl_seen[i] == 1)) {
      /* every key of this level is a number: compare the values read when the nodes arrived */
      v1 = sess->pend_num[(size_t)a * sess->nrlev + sess->rl_idx[i]];
      v2 = sess->pend_num[(size_t)b * sess->nrlev + sess->rl_idx[i]];
      d = (v1 > v2) ? 1 : (v1 < v2) ? -1 : 0;
      if (sess->sort_flags[i] & SRT_DESCENDING)
        d = -d;
    } else if ((sess->sort_flags[i] & (SRT_MODE_MASK | SRT_NOCASE)) == SRT_LEFT) {
      /* a plain left justified key: strcmp() orders bytes as unsigned chars and ends at the null, as sort_compare_keys does */
      d = strcmp(ba->key[i] ? ba->key[i] : "", bb->key[i] ? bb->key[i] : "");
      d = (d < 0) ? -1 : (d > 0) ? 1 : 0;
      if (sess->sort_flags[i] & SRT_DESCENDING)
        d = -d;
    } else {
      d = sort_compare_keys(ba->key[i], bb->key[i], sess->sort_flags[i], sess->legacy_bt, NULL);
    }
    if (d != 0)
      return d;
  }
  return 0;
}

/* Stable bottom-up merge sort of a[0..n), b is the same size; the result is in a */
Private void merge_sort_idx(SORT_SESSION* sess, int32_t* a, int32_t* b, int32_t n) {
  int32_t width;
  int32_t lo;
  int32_t mid;
  int32_t hi;
  int32_t i;
  int32_t j;
  int32_t k;
  int32_t* src = a;
  int32_t* dst = b;
  int32_t* t;

  for (width = 1; width < n; width *= 2) {
    for (lo = 0; lo < n; lo += 2 * width) {
      mid = min(lo + width, n);
      hi = min(lo + 2 * width, n);
      i = lo;
      j = mid;
      k = lo;
      while ((i < mid) && (j < hi)) {
        if (pend_cmp(sess, src[i], src[j]) <= 0)
          dst[k++] = src[i++];
        else
          dst[k++] = src[j++];
      }
      while (i < mid)
        dst[k++] = src[i++];
      while (j < hi)
        dst[k++] = src[j++];
    }
    t = src;
    src = dst;
    dst = t;
  }
  if (src != a)
    memcpy(a, src, (size_t)n * sizeof(int32_t));
}

Private BTREE_ELEMENT* build_balanced(BTREE_ELEMENT** s, int32_t lo, int32_t hi, BTREE_ELEMENT* parent) {
  int32_t mid;
  BTREE_ELEMENT* bte;

  if (lo > hi)
    return NULL;
  mid = lo + ((hi - lo) / 2);
  bte = s[mid];
  bte->parent = parent;
  bte->left = build_balanced(s, lo, mid - 1, bte);
  bte->right = build_balanced(s, mid + 1, hi, bte);
  return bte;
}

/* Sort an array run that has not been read yet and link its nodes into a balanced tree, so that the walks that read the
   tree (the next element, the flush to a work file) are the ones they always were */
Private void array_finalize(SORT_SESSION* sess) {
  int32_t n = sess->pend_n;
  int32_t i;
  int32_t* idx;
  int32_t* tmp;
  BTREE_ELEMENT** sorted;

  if ((sess->run_kind != RK_ARRAY) || sess->tree_built || (n == 0))
    return;

  idx = (int32_t*)k_alloc(119, (size_t)n * sizeof(int32_t));
  tmp = (int32_t*)k_alloc(120, (size_t)n * sizeof(int32_t));
  sorted = (BTREE_ELEMENT**)k_alloc(121, (size_t)n * sizeof(BTREE_ELEMENT*));
  if ((idx == NULL) || (tmp == NULL) || (sorted == NULL)) {
    if (idx != NULL)
      k_free(idx);
    if (tmp != NULL)
      k_free(tmp);
    if (sorted != NULL)
      k_free(sorted);
    array_to_classic(sess); /* slow, but right */
    return;
  }

  for (i = 0; i < n; i++)
    idx[i] = n - 1 - i; /* newest first: equal keys keep this order */
  merge_sort_idx(sess, idx, tmp, n);
  for (i = 0; i < n; i++)
    sorted[i] = sess->pend[idx[i]];
  sess->sort_tree = build_balanced(sorted, 0, n - 1, NULL);
  sess->tree_built = TRUE;

  k_free(idx);
  k_free(tmp);
  k_free(sorted);
}

/* ======================================================================
   sess_insert_bte()  -  Insert a new BTREE_ELEMENT into a sort session   */

Private void sess_insert_bte(SORT_SESSION* sess,
                             BTREE_ELEMENT* new_bte,
                             int32_t size) {
  /* Flush the tree if this would take us past the SORTMEM limit */

  sess->sort_size += size;
  if (sess->sort_size > pcfg.sortmem) {
    if (!flush_sort_tree(sess))
      k_error(sysmsg(1485), process.os_error);
    sess->sort_size = size;
  }

  /* A run begins with the first node after a flush (or the first of the sort).  20 Oct 26: unless the sort has a UNIQUE
     or a COMPOUND / STRICT level, the nodes of the run are collected and sorted once (array_add / array_finalize); the
     classic walk into the tree is kept for those sorts, and for any run in which a right justified level has met both
     numbers and text, where the comparison is not transitive and only the tree gives the order it always gave. */

  if ((sess->sort_tree == NULL) && (sess->pend_n == 0)) {
    if (run_is_array_ok(sess))
      array_start(sess);
    else
      sess->run_kind = RK_CLASSIC;
  }

  if (sess->run_kind == RK_ARRAY) {
    if (array_add(sess, new_bte))
      return;
    array_to_classic(sess); /* put the nodes so far in the tree in the order they came, then this one as usual */
  }

  if (tree_insert(sess, new_bte))
    sess->sort_size -= size;
}

/* ======================================================================
   tree_insert()  -  The classic insertion: walk the tree to the place
   TRUE if the new element was a duplicate of a UNIQUE level and was freed */

Private bool tree_insert(SORT_SESSION* sess, BTREE_ELEMENT* new_bte) {
  BTREE_ELEMENT* bte;
  int16_t index;
  int d;
  KEY_NUM new_num[MAX_SORT_KEYS]; /* the new key at each level, read as a number the first time that level is compared... */
  u_int32_t num_done = 0;         /* ...bit n set once new_num[n] holds it (only a right justified key is ever read) */

  /* Walk tree to insertion point */

  bte = sess->sort_tree;
  if (bte == NULL) {
    sess->sort_tree = new_bte;
    new_bte->parent = NULL;
  } else {
    index = 0;
    do {
      if (!(num_done & ((u_int32_t)1 << index))) {
        num_done |= (u_int32_t)1 << index;
        new_num[index].is_num = key_as_number(new_bte->key[index], sess->sort_flags[index] & SRT_MODE_MASK,
                                              sess->legacy_bt, &(new_num[index].val));
      }
      d = sort_compare_keys(new_bte->key[index], bte->key[index],
                            sess->sort_flags[index], sess->legacy_bt, &(new_num[index]));

      if (d < 0) {
        if (bte->left == NULL) {
          bte->left = new_bte;
          new_bte->parent = bte;
          return FALSE;
        }
        bte = bte->left;
        index = 0;
      } else if (d > 0) {
        if (bte->right == NULL) {
          bte->right = new_bte;
          new_bte->parent = bte;
          return FALSE;
        }
        bte = bte->right;
        index = 0;
      } else {
        if (sess->sort_flags[index] & SRT_UNIQUE) {
          free_btree_element(new_bte, sess->sort_keys);
          process.status = 1;
          return TRUE;
        }

        if (++index == sess->sort_keys) {
          /* Complete duplicate at all key levels.  Insert to left. */
          if (bte->left == NULL) {
            bte->left = new_bte;
            new_bte->parent = bte;
            return FALSE;
          }
          bte = bte->left;
          index = 0;
        }
      }
    } while (1);
  }
  return FALSE;
}

/* ======================================================================
   op_sortclr()  -  Tidy up after completion of a legacy sort             */

void op_sortclr() {
  clear_sort_session(&legacy_session);
  process.program.flags &= ~SORT_ACTIVE;
}

/* ======================================================================
   op_sortadd()  -  Add entry to the legacy sort tree                     */

void op_sortadd() {
  DESCRIPTOR* descr;
  ARRAY_HEADER* a_hdr;
  BTREE_ELEMENT* new_bte;
  int16_t index;
  int bytes;
  int32_t size = 2 * LEN_BYTES;
  STRING_CHUNK* str;
  char* p;

  descr = e_stack - 2;
  while (descr->type == ADDR)
    descr = descr->data.d_addr;
  if (descr->type != ARRAY)
    k_not_array_error(descr);

  a_hdr = descr->data.ahdr_addr;
  if ((a_hdr->rows != legacy_session.sort_keys) || (a_hdr->cols != 0)) {
    k_error(sysmsg(1481));
  }

  bytes = sizeof(struct BTREE_ELEMENT) +
          ((legacy_session.sort_keys - 1) * sizeof(char*));
  new_bte = (BTREE_ELEMENT*)k_alloc(61, bytes);
  if (new_bte == NULL)
    k_error(sysmsg(1482));
  memset(new_bte, 0, bytes);

  for (index = 0; index < legacy_session.sort_keys; index++) {
    descr = Element(a_hdr, index + 1);
    GetString(descr);
    str = descr->data.str.saddr;
    if (str != NULL) {
      bytes = str->string_len + 1;
      p = (char*)k_alloc(115, bytes);
      k_get_c_string(descr, p, str->string_len);
      new_bte->key[index] = p;
      size += LEN_BYTES + pad4(bytes);
    } else {
      size += LEN_BYTES;
    }
  }

  if (legacy_session.sort_has_data) {
    descr = e_stack - 1;
    GetString(descr);
    str = descr->data.str.saddr;
    if (str != NULL) {
      bytes = str->string_len + 1;
      p = (char*)k_alloc(116, bytes);
      k_get_c_string(descr, p, str->string_len);
      new_bte->data = p;
      size += pad4(bytes);
    }
  }

  sess_insert_bte(&legacy_session, new_bte, size);

  k_dismiss(); /* Data */
  k_pop(1);    /* ADDR to keys array */
}

/* ======================================================================
   op_sortinit()  -  Initialise a legacy sort                             */

void op_sortinit() {
  DESCRIPTOR* descr;
  int keys;
  ARRAY_HEADER* a_hdr;
  int i;

  op_sortclr();

  descr = e_stack - 2;
  GetInt(descr);
  keys = descr->data.value;
  if ((keys < 1) || (keys > MAX_SORT_KEYS))
    k_error(sysmsg(1486));

  descr = e_stack - 1;
  while (descr->type == ADDR)
    descr = descr->data.d_addr;
  if (descr->type != ARRAY)
    k_not_array_error(descr);
  a_hdr = descr->data.ahdr_addr;
  if ((keys > a_hdr->rows) || (a_hdr->cols != 0))
    k_index_error(descr);

  legacy_session.in_use = TRUE;
  legacy_session.session_id = 0;
  legacy_session.legacy_bt = TRUE;
  legacy_session.sort_keys = (int16_t)keys;
  for (i = 1; i <= keys; i++) {
    u_char bt, sf;
    descr = Element(a_hdr, i);
    GetInt(descr);
    bt = (u_char)(descr->data.value);
    sf = (bt & BT_RIGHT_ALIGNED) ? SRT_RIGHT_FLOAT : SRT_LEFT;
    if (bt & BT_DESCENDING)
      sf |= SRT_DESCENDING;
    if (bt & BT_UNIQUE)
      sf |= SRT_UNIQUE;
    if (bt & BT_DATA)
      sf |= SRT_DATA;
    legacy_session.sort_flags[i - 1] = sf;
  }

  legacy_session.sort_has_data = (legacy_session.sort_flags[0] & SRT_DATA) != 0;

  k_pop(2);

  legacy_session.sort_size = 0;
  legacy_session.sorting = TRUE;
  process.program.flags |= SORT_ACTIVE;
}

/* ======================================================================
   sess_sortdata()  -  Retrieve data from a sort session                  */

Private void sess_sortdata(SORT_SESSION* sess,
                           int32_t max_items,
                           bool require_sorting) {
  BTREE_ELEMENT* bte;
  BTREE_ELEMENT* old_bte;
  STRING_CHUNK* head = NULL;
  int32_t skip_bytes = 0;
  int32_t data_bytes = 0;
  int32_t bytes_remaining;
  int32_t n;
  int16_t phase;

  process.status = 0;

  if (require_sorting && !sess->sorting)
    k_error(sysmsg(1487));

  /* The target string is started BEFORE the merge, as it was before the 16 Oct 26 rewrite: a merge that cannot open its
     last file takes the exit below, and ts_terminate() there needs a ts_init() behind it (16 Oct 26 audit). */
  ts_init(&head, 1024);

  if (sess->sorting) {
    if (sess->sortwork) {
      if (!sortmerge(sess))
        goto exit_sess_sortdata;
    } else {
      array_finalize(sess);
      bte = sess->sort_tree;
      if (bte != NULL)
        while (bte->left != NULL)
          bte = bte->left;
      sess->sort_ptr = bte;
    }
    sess->sorting = FALSE;
  }

  if (sess->sortwork) /* Disk based sort */
  {
    if (!ValidFileHandle(sess->sort_fu))
      goto exit_sess_sortdata;

    phase = 1;
    do {
      while (sess->sort_buff_offset >= sess->sort_buff_bytes) {
        sess->sort_buff_offset -= sess->sort_buff_bytes;
        sess->sort_buff_bytes =
            (int32_t)Read(sess->sort_fu, sess->sort_buff, DISK_BUFFER_SIZE);
        if (sess->sort_buff_bytes <= 0)
          goto exit_sess_sortdata;
      }

      switch (phase) {
        case 1:
          skip_bytes = get32(sess->sort_buff + sess->sort_buff_offset) - LEN_BYTES;
          sess->sort_buff_offset += LEN_BYTES;
          if (head != NULL)
            ts_copy_byte(FIELD_MARK);
          if (!sess->sort_has_data) {
            sess->sort_buff_offset += LEN_BYTES;
            skip_bytes -= LEN_BYTES;
          }
          phase = 2;
          break;

        case 2:
          data_bytes = get32(sess->sort_buff + sess->sort_buff_offset);
          if (!sess->sort_has_data && data_bytes > 0)
            data_bytes--;
          sess->sort_buff_offset += LEN_BYTES;
          skip_bytes -= LEN_BYTES;
          phase = 3;
          break;

        case 3:
          bytes_remaining = sess->sort_buff_bytes - sess->sort_buff_offset;
          n = min(bytes_remaining, data_bytes);
          ts_copy(sess->sort_buff + sess->sort_buff_offset, n);
          data_bytes -= n;
          n = pad4(n);
          sess->sort_buff_offset += n;
          skip_bytes -= n;
          if (data_bytes == 0) {
            process.status++;
            phase = 4;
          }
          break;

        case 4:
          sess->sort_buff_offset += skip_bytes;
          phase = 1;
          if ((max_items > 0) && (process.status >= max_items))
            goto exit_sess_sortdata;
          break;
      }
    } while (1);
  } else /* Memory based sort */
  {
    bte = sess->sort_ptr;

    while (bte != NULL) {
      if (head != NULL)
        ts_copy_byte(FIELD_MARK);
      if (sess->sort_has_data) {
        if (bte->data != NULL)
          ts_copy(bte->data, strlen(bte->data));
      } else {
        if (bte->key[0] != NULL)
          ts_copy(bte->key[0], strlen(bte->key[0]));
      }
      process.status += 1;

      /* Locate next item */

      if (bte->right != NULL) {
        bte = bte->right;
        while (bte->left != NULL)
          bte = bte->left;
      } else {
        do {
          old_bte = bte;
          bte = bte->parent;
          if (bte == NULL)
            break;
        } while (old_bte == bte->right);
      }

      sess->sort_ptr = bte;
      if ((max_items > 0) && (process.status >= max_items))
        break;
    }
  }

exit_sess_sortdata:
  ts_terminate();

  InitDescr(e_stack, STRING);
  (e_stack++)->data.str.saddr = head;
}

/* ======================================================================
   op_sortdata()  -  Retrieve all data from legacy sort                   */

void op_sortdata() {
  sess_sortdata(&legacy_session, 0, TRUE);
}

/* ======================================================================
   sess_sortnext()  -  Retrieve next item from a sort session             */

Private void sess_sortnext(SORT_SESSION* sess,
                           ARRAY_HEADER* a_hdr,
                           DESCRIPTOR* scalar_key,
                           bool has_keys_arg) {
  DESCRIPTOR* data_descr;
  DESCRIPTOR* descr;
  BTREE_ELEMENT* bte;
  BTREE_ELEMENT* old_bte;
  int16_t index;
  char* buff = NULL;
  int32_t bytes;
  int32_t n;
  char* q;

  process.status = 1;

  data_descr = e_stack++;
  InitDescr(data_descr, STRING);
  data_descr->data.str.saddr = NULL;

  if (sess->sorting) {
    if (sess->sortwork) {
      if (!sortmerge(sess))
        goto exit_sess_sortnext;
    } else {
      array_finalize(sess);
      bte = sess->sort_tree;
      if (bte != NULL)
        while (bte->left != NULL)
          bte = bte->left;
      sess->sort_ptr = bte;
    }
    sess->sorting = FALSE;
  }

  if (sess->sortwork) /* Disk based sort */
  {
    if (!ValidFileHandle(sess->sort_fu))
      goto exit_sess_sortnext;

    while (sess->sort_buff_offset >= sess->sort_buff_bytes) {
      sess->sort_buff_offset -= sess->sort_buff_bytes;
      sess->sort_buff_bytes =
          (int32_t)Read(sess->sort_fu, sess->sort_buff, DISK_BUFFER_SIZE);
      if (sess->sort_buff_bytes <= 0)
        goto exit_sess_sortnext;
    }

    bytes = get32(sess->sort_buff + sess->sort_buff_offset);

    if (sess->sort_buff_offset + bytes <= sess->sort_buff_bytes) {
      q = sess->sort_buff + sess->sort_buff_offset + LEN_BYTES;
      sess->sort_buff_offset += pad4(bytes);
    } else {
      buff = (char*)k_alloc(65, bytes);
      if (buff == NULL)
        k_error("Insufficient memory for sort record buffer");
      q = buff;

      while (bytes) {
        n = sess->sort_buff_bytes - sess->sort_buff_offset;
        if (n == 0) {
          sess->sort_buff_bytes =
              (int32_t)Read(sess->sort_fu, sess->sort_buff, DISK_BUFFER_SIZE);
          if (sess->sort_buff_bytes <= 0)
            goto exit_sess_sortnext;
          sess->sort_buff_offset = 0;
          n = sess->sort_buff_bytes;
        }
        n = min(bytes, n);
        memcpy(q, sess->sort_buff + sess->sort_buff_offset, n);
        q += n;
        bytes -= n;
        sess->sort_buff_offset += n;
      }

      q = buff + LEN_BYTES;
    }

    /* Extract the data */

    bytes = get32(q);
    q += LEN_BYTES;
    if (bytes) {
      ts_init(&(data_descr->data.str.saddr), bytes);
      ts_copy(q, bytes);
      ts_terminate();
      q += pad4(bytes);
    }

    /* Extract the keys */

    for (index = 1; index <= sess->sort_keys; index++) {
      bytes = get32(q);
      q += LEN_BYTES;
      if ((index == 1) && !sess->sort_has_data && !has_keys_arg) {
        if (bytes > 1) {
          ts_init(&(data_descr->data.str.saddr), bytes - 1);
          ts_copy(q, bytes - 1);
          ts_terminate();
        }
      }
      if (a_hdr != NULL) {
        descr = Element(a_hdr, index);
        k_release(descr);
        InitDescr(descr, STRING);
        descr->data.str.saddr = NULL;
        if (bytes > 1) {
          ts_init(&(descr->data.str.saddr), bytes - 1);
          ts_copy(q, bytes - 1);
          ts_terminate();
        }
      } else if ((scalar_key != NULL) && (index == 1)) {
        k_release(scalar_key);
        InitDescr(scalar_key, STRING);
        scalar_key->data.str.saddr = NULL;
        if (bytes > 1) {
          ts_init(&(scalar_key->data.str.saddr), bytes - 1);
          ts_copy(q, bytes - 1);
          ts_terminate();
        }
      }
      if (bytes)
        q += pad4(bytes);
    }
  } else /* Memory based sort */
  {
    if ((bte = sess->sort_ptr) == NULL)
      goto exit_sess_sortnext;

    if (sess->sort_has_data) {
      k_put_c_string(bte->data, data_descr);
    } else if (!has_keys_arg) {
      k_put_c_string(bte->key[0], data_descr);
    }

    if (a_hdr != NULL) {
      for (index = 1; index <= sess->sort_keys; index++) {
        descr = Element(a_hdr, index);
        k_release(descr);
        k_put_c_string(bte->key[index - 1], descr);
      }
    } else if (scalar_key != NULL) {
      k_release(scalar_key);
      k_put_c_string(bte->key[0], scalar_key);
    }

    /* Locate next item */

    if (bte->right != NULL) {
      bte = bte->right;
      while (bte->left != NULL)
        bte = bte->left;
    } else {
      do {
        old_bte = bte;
        bte = bte->parent;
        if (bte == NULL)
          break;
      } while (old_bte == bte->right);
    }

    sess->sort_ptr = bte;
  }

  process.status = 0;

exit_sess_sortnext:
  if (buff != NULL)
    k_free(buff);
}

/* ======================================================================
   op_sortnext()  -  Retrieve next item from legacy sort data             */

void op_sortnext() {
  DESCRIPTOR* descr;
  ARRAY_HEADER* a_hdr;

  descr = e_stack - 1;
  while (descr->type == ADDR)
    descr = descr->data.d_addr;
  if (descr->type != ARRAY)
    k_not_array_error(descr);

  a_hdr = descr->data.ahdr_addr;
  if ((a_hdr->rows != legacy_session.sort_keys) || (a_hdr->cols != 0)) {
    k_error(sysmsg(1488));
  }
  k_pop(1);

  sess_sortnext(&legacy_session, a_hdr, NULL, TRUE);
}

/* ======================================================================
   x_sort()  -  SORT(key.count, {MAT} flags)                              */

void x_sort() {
  DESCRIPTOR* descr;
  int keys;
  ARRAY_HEADER* a_hdr;
  SORT_SESSION* sess;
  BTREE_HEADER* bth;
  int i;

  descr = e_stack - 2;
  GetInt(descr);
  keys = descr->data.value;
  if ((keys < 1) || (keys > MAX_SORT_KEYS))
    k_error(sysmsg(1486));

  sess = alloc_sort_session();
  sess->legacy_bt = FALSE;
  sess->sort_keys = (int16_t)keys;

  descr = e_stack - 1;
  while (descr->type == ADDR)
    descr = descr->data.d_addr;
  if (descr->type == ARRAY) {
    a_hdr = descr->data.ahdr_addr;
    if ((keys > a_hdr->rows) || (a_hdr->cols != 0)) {
      free_sort_session(sess->session_id);
      k_index_error(descr);
    }
    for (i = 1; i <= keys; i++) {
      descr = Element(a_hdr, i);
      GetInt(descr);
      sess->sort_flags[i - 1] = (u_char)(descr->data.value);
    }
  } else if (keys == 1) {
    descr = e_stack - 1;
    GetInt(descr);
    sess->sort_flags[0] = (u_char)(descr->data.value);
  } else {
    free_sort_session(sess->session_id);
    k_not_array_error(descr);
  }

  sess->sort_has_data = (sess->sort_flags[0] & SRT_DATA) != 0;
  sess->sort_size = 0;
  sess->sorting = TRUE;

  k_dismiss();
  k_dismiss();

  bth = (BTREE_HEADER*)k_alloc(28, sizeof(struct BTREE_HEADER));
  if (bth == NULL)
    k_error("Insufficient memory for BTree header");
  bth->ref_ct = 1;
  bth->pad = sess->session_id;
  bth->head = NULL;
  bth->current = NULL;
  bth->keys = 0;
  bth->flags[0] = 0;

  InitDescr(e_stack, BTREE);
  (e_stack++)->data.btree = bth;
}

/* ======================================================================
   x_sortadd()  -  SORTADD sortvar, {MAT} keys {, data}                   */

void x_sortadd() {
  SORT_SESSION* sess;
  DESCRIPTOR* descr;
  ARRAY_HEADER* a_hdr;
  BTREE_ELEMENT* new_bte;
  int16_t index;
  int bytes;
  int32_t size = 2 * LEN_BYTES;
  STRING_CHUNK* str;
  char* p;

  process.status = 0;
  sess = get_sort_session(e_stack - 3);
  if (!sess->sorting && (sess->sort_tree == NULL) && (sess->pend_n == 0) && (sess->sortwork == 0))
    sess->sorting = TRUE;

  bytes = sizeof(struct BTREE_ELEMENT) + ((sess->sort_keys - 1) * sizeof(char*));
  new_bte = (BTREE_ELEMENT*)k_alloc(61, bytes);
  if (new_bte == NULL)
    k_error(sysmsg(1482));
  memset(new_bte, 0, bytes);

  descr = e_stack - 2;
  while (descr->type == ADDR)
    descr = descr->data.d_addr;
  if (descr->type == ARRAY) {
    a_hdr = descr->data.ahdr_addr;
    if ((a_hdr->rows < sess->sort_keys) || (a_hdr->cols != 0))
      k_error(sysmsg(1481));
    for (index = 0; index < sess->sort_keys; index++) {
      descr = Element(a_hdr, index + 1);
      GetString(descr);
      str = descr->data.str.saddr;
      if (str != NULL) {
        bytes = str->string_len + 1;
        p = (char*)k_alloc(115, bytes);
        k_get_c_string(descr, p, str->string_len);
        new_bte->key[index] = p;
        size += LEN_BYTES + pad4(bytes);
      } else {
        size += LEN_BYTES;
      }
    }
  } else if (sess->sort_keys == 1) {
    descr = e_stack - 2;
    GetString(descr);
    str = descr->data.str.saddr;
    if (str != NULL) {
      bytes = str->string_len + 1;
      p = (char*)k_alloc(115, bytes);
      k_get_c_string(descr, p, str->string_len);
      new_bte->key[0] = p;
      size += LEN_BYTES + pad4(bytes);
    } else {
      size += LEN_BYTES;
    }
  } else {
    free_btree_element(new_bte, sess->sort_keys);
    k_not_array_error(descr);
  }

  if (sess->sort_has_data) {
    descr = e_stack - 1;
    while (descr->type == ADDR)
      descr = descr->data.d_addr;
    if (descr->type != UNASSIGNED) {
      descr = e_stack - 1;
      GetString(descr);
      str = descr->data.str.saddr;
      if (str != NULL) {
        bytes = str->string_len + 1;
        p = (char*)k_alloc(116, bytes);
        k_get_c_string(descr, p, str->string_len);
        new_bte->data = p;
        size += pad4(bytes);
      }
    }
  }

  sess_insert_bte(sess, new_bte, size);

  k_dismiss(); /* data */
  k_dismiss(); /* keys */
  k_dismiss(); /* sortvar */
}

/* ======================================================================
   x_sortclear()  -  SORTCLEAR sortvar                                    */

void x_sortclear() {
  DESCRIPTOR* d = e_stack - 1;

  while (d->type == ADDR)
    d = d->data.d_addr;
  if ((d->type == BTREE) && (d->data.btree != NULL)) {
    int16_t id = d->data.btree->pad;
    if ((id >= 1) && (id < MAX_USER_SORTS) && (user_sorts[id] != NULL)) {
      clear_sort_session(user_sorts[id]);
    }
  }
  k_dismiss();
}

/* ======================================================================
   x_sortdata()  -  SORTDATA(sortvar {, max.items})                       */

void x_sortdata() {
  DESCRIPTOR* max_d = e_stack - 1;
  int32_t max_items;
  SORT_SESSION* sess;

  GetInt(max_d);
  max_items = max_d->data.value;
  sess = get_sort_session(e_stack - 2);

  k_dismiss(); /* max.items */
  k_dismiss(); /* sortvar */

  sess_sortdata(sess, max_items, FALSE);
}

/* ======================================================================
   x_sortnext()  -  SORTNEXT(sortvar {, {MAT} keys})                      */

void x_sortnext() {
  SORT_SESSION* sess;
  DESCRIPTOR* keys_d;
  ARRAY_HEADER* a_hdr = NULL;
  DESCRIPTOR* scalar_key = NULL;
  bool has_keys_arg = FALSE;

  sess = get_sort_session(e_stack - 2);
  keys_d = e_stack - 1;
  if (keys_d->type != UNASSIGNED) {
    has_keys_arg = TRUE;
    while (keys_d->type == ADDR)
      keys_d = keys_d->data.d_addr;
    if (keys_d->type == ARRAY) {
      a_hdr = keys_d->data.ahdr_addr;
      if ((a_hdr->rows < sess->sort_keys) || (a_hdr->cols != 0))
        k_error(sysmsg(1488));
    } else if (sess->sort_keys == 1) {
      scalar_key = keys_d;
    } else {
      k_not_array_error(keys_d);
    }
  }

  k_dismiss(); /* keys */
  k_dismiss(); /* sortvar */

  sess_sortnext(sess, a_hdr, scalar_key, has_keys_arg);
}

/* ======================================================================
   sortmerge()  -  Perform merge phase of disk sort                       */

Private bool sortmerge(SORT_SESSION* sess) {
  bool status = FALSE;
  char pathname[MAX_PATHNAME_LEN + 1];

  /* Flush final part to disk */

  if (!flush_sort_tree(sess))
    k_error(sysmsg(1489), process.os_error);

  /* Initialise scan pointer to start of sort data */

  if (!merge_sort_files(sess))
    k_error(sysmsg(1490));

  make_workfile_path(sess, (int)sess->sortwork, pathname, "sortmerge()");
  sess->sort_fu = dio_open(pathname, DIO_READ);
  if (!ValidFileHandle(sess->sort_fu))
    goto exit_sortmerge;

  sess->sort_buff = (char*)k_alloc(64, DISK_BUFFER_SIZE);
  sess->sort_buff_bytes = 0;
  sess->sort_buff_offset = 0;

  status = TRUE;

exit_sortmerge:
  return status;
}

/* ======================================================================
   flush_sort_tree()  - Write sort tree to disk                           */

Private bool flush_sort_tree(SORT_SESSION* sess) {
  bool status = FALSE;
  char pathname[MAX_PATHNAME_LEN + 1];
  OSFILE fu = INVALID_FILE_HANDLE;
  BTREE_ELEMENT* bte;
  BTREE_ELEMENT* old_bte;
  int bytes;
  int assembly_buffer_size = 0;
  char* assembly_buffer = NULL;
  char* disk_buffer = NULL;
  int32_t used_bytes;
  int32_t space;
  int16_t i;
  int32_t n;
  char* p;
  char* q;

  process.os_error = 0;
  array_finalize(sess); /* an array run is sorted and linked into the tree before it is written */
  make_workfile_path(sess, (int)sess->sortwork, pathname, "flush_sort_tree()");
  fu = dio_open(pathname, DIO_REPLACE);
  if (!ValidFileHandle(fu))
    k_error(sysmsg(1491), pathname, OSError);

  disk_buffer = (char*)k_alloc(63, DISK_BUFFER_SIZE);
  if (disk_buffer == NULL)
    k_error("Insufficient memory for sort disk buffer");
  used_bytes = 0;

  bte = sess->sort_tree;
  if (bte != NULL)
    while (bte->left != NULL)
      bte = bte->left;
  while (bte != NULL) {
    bytes = 2 * LEN_BYTES;
    if (bte->data != NULL)
      bytes += pad4(strlen(bte->data));

    for (i = 0; i < sess->sort_keys; i++) {
      bytes += LEN_BYTES;
      if (bte->key[i] != NULL)
        bytes += pad4(strlen(bte->key[i]) + 1);
    }

    if (assembly_buffer_size < bytes) {
      if (assembly_buffer != NULL)
        k_free(assembly_buffer);
      assembly_buffer_size = (bytes + 1023) & ~1023;
      assembly_buffer = (char*)k_alloc(62, assembly_buffer_size);
      if (assembly_buffer == NULL)
        k_error("Insufficient memory for sort assembly buffer");
    }

    if (assembly_buffer == NULL)
      k_error("Insufficient memory for sort assembly buffer");
    q = assembly_buffer;
    put32(q, bytes);
    q += LEN_BYTES;

    if (bte->data != NULL) {
      n = strlen(bte->data);
      put32(q, n);
      q += LEN_BYTES;
      memcpy(q, bte->data, n);
      q += n;
      while (n++ & 3)
        *(q++) = '\0';
    } else {
      put32(q, 0);
      q += LEN_BYTES;
    }

    for (i = 0; i < sess->sort_keys; i++) {
      if (bte->key[i] != NULL) {
        n = strlen(bte->key[i]) + 1;
        put32(q, n);
        q += LEN_BYTES;
        memcpy(q, bte->key[i], n);
        q += n;
        while (n++ & 3)
          *(q++) = '\0';
      } else {
        put32(q, 0);
        q += LEN_BYTES;
      }
    }

    p = assembly_buffer;
    do {
      space = DISK_BUFFER_SIZE - used_bytes;
      if (space == 0) {
        if (Write(fu, disk_buffer, used_bytes) != used_bytes) {
          process.os_error = OSError;
          goto exit_flush_sort_tree;
        }

        used_bytes = 0;
        space = DISK_BUFFER_SIZE;
      }

      n = min(bytes, space);
      memcpy(disk_buffer + used_bytes, p, n);
      p += n;
      used_bytes += n;
      bytes -= n;
    } while (bytes);

    if (bte->right != NULL) {
      bte = bte->right;
      while (bte->left != NULL)
        bte = bte->left;
    } else {
      do {
        old_bte = bte;
        bte = bte->parent;
        if (bte == NULL)
          break;
      } while (old_bte == bte->right);
    }
  }

  if (used_bytes != 0) {
    if (Write(fu, disk_buffer, used_bytes) != used_bytes) {
      process.os_error = OSError;
      goto exit_flush_sort_tree;
    }
  }

  sess->sortwork++;

  if (sess->sort_tree != NULL)
    free_btree_element(sess->sort_tree, sess->sort_keys);
  sess->sort_tree = NULL;
  array_release(sess); /* the run is over; the nodes were in the tree */
  sess->sort_size = 0;

  status = TRUE;

exit_flush_sort_tree:
  if (ValidFileHandle(fu))
    CloseFile(fu);

  if (disk_buffer != NULL)
    k_free(disk_buffer);
  if (assembly_buffer != NULL)
    k_free(assembly_buffer);

  return status;
}

/* ======================================================================
   free_sort_merge_buffs()  -  Release merge buffer array                 */

Private void free_sort_merge_buffs(char* buff[], int16_t count) {
  int16_t j;

  for (j = 0; j < count; j++) {
    if (buff[j] != NULL) {
      k_free(buff[j]);
      buff[j] = NULL;
    }
  }
}

/* ======================================================================
   merge_sort_files()  -  Merge individual disk based sort files          */

Private bool merge_sort_files(SORT_SESSION* sess) {
  bool status = FALSE;
  int16_t num_files;
  int16_t lo_file;
  int16_t nstream;

  OSFILE infu[MAX_SORTMRG];
  char* buff[MAX_SORTMRG] = {NULL};
  int32_t buff_bytes[MAX_SORTMRG];
  int32_t buff_offset[MAX_SORTMRG];
  char* rec[MAX_SORTMRG];
  bool temp[MAX_SORTMRG];
  char* p1;
  int32_t n1;
  char* k1;
  char* p2;
  int32_t n2;
  char* k2;
  int16_t best;
  int16_t ndata;

  OSFILE outfu = INVALID_FILE_HANDLE;
  char* outbuff = NULL;
  int32_t outbuff_bytes;

  char pathname[MAX_PATHNAME_LEN + 1];
  int16_t index;
  int16_t i;
  int d;

  num_files = sess->sortwork--;
  lo_file = 0;

  memset(buff, 0, sizeof(buff));
  memset(rec, 0, sizeof(rec));
  memset(temp, 0, sizeof(temp));

  for (i = 0; i < pcfg.sortmrg; i++) {
    infu[i] = INVALID_FILE_HANDLE;
    buff[i] = (char*)k_alloc(66, DISK_BUFFER_SIZE);
    if (buff[i] == NULL)
      k_error("Insufficient memory for sort merge buffer");
  }

  while (num_files > 1) {
    nstream = min(pcfg.sortmrg, num_files);

    for (i = 0; i < nstream; i++) {
      make_workfile_path(sess, (int)lo_file + i, pathname, "merge_sort_files()");
      infu[i] = dio_open(pathname, DIO_READ);
      if (!ValidFileHandle(infu[i])) {
        status = FALSE;
        free_sort_merge_buffs(buff, pcfg.sortmrg);
        goto exit_merge_sort_files;
      }
      buff_bytes[i] = 0;
      buff_offset[i] = 0;
      rec[i] = NULL;
      if (buff[i] == NULL)
        goto exit_merge_sort_files;
      rec[i] = read_merge_record(infu[i], buff[i], &(buff_bytes[i]),
                                 &(buff_offset[i]), &(temp[i]));
    }

    sess->sortwork++;
    make_workfile_path(sess, (int)sess->sortwork, pathname, "merge_sort_files()");
    outfu = dio_open(pathname, DIO_REPLACE);
    if (!ValidFileHandle(outfu)) {
      status = FALSE;
      free_sort_merge_buffs(buff, pcfg.sortmrg);
      goto exit_merge_sort_files;
    }

    outbuff = (char*)k_alloc(66, DISK_BUFFER_SIZE);
    if (outbuff == NULL)
      k_error("Insufficient memory for sort merge output buffer");
    outbuff_bytes = 0;

    ndata = nstream;
    do {
      for (best = 0; (best < nstream) && (rec[best] == NULL); best++) {
      }
      if (best >= nstream)
        break;

      for (i = best + 1; i < nstream; i++) {
        if (rec[i] == NULL)
          continue;

        p1 = rec[best] + LEN_BYTES;
        p1 += LEN_BYTES + pad4(get32(p1));

        p2 = rec[i] + LEN_BYTES;
        p2 += LEN_BYTES + pad4(get32(p2));

        bool dup_unique = FALSE;
        d = 0;
        for (index = 0; index < sess->sort_keys; index++) {
          n1 = get32(p1);
          k1 = (n1 == 0) ? "" : (p1 + LEN_BYTES);
          p1 += LEN_BYTES + pad4(n1);

          n2 = get32(p2);
          k2 = (n2 == 0) ? "" : (p2 + LEN_BYTES);
          p2 += LEN_BYTES + pad4(n2);

          d = sort_compare_keys(k1, k2, sess->sort_flags[index], sess->legacy_bt, NULL);
          if (d != 0)
            break;
          if (sess->sort_flags[index] & SRT_UNIQUE) {
            dup_unique = TRUE;
            break;
          }
        }

        if (dup_unique) {
          if (temp[i] && (rec[i] != NULL))
            k_free(rec[i]);
          rec[i] = read_merge_record(infu[i], buff[i], &(buff_bytes[i]),
                                     &(buff_offset[i]), &(temp[i]));
          if (rec[i] == NULL)
            ndata--;
          else
            i--;
          continue;
        }

        if (d >= 0)
          best = i;
      }

      if (!write_merge_record(rec[best], outfu, outbuff, &outbuff_bytes,
                              temp[best])) {
        goto exit_merge_sort_files;
      }

      rec[best] = read_merge_record(infu[best], buff[best], &(buff_bytes[best]),
                                    &(buff_offset[best]), &(temp[best]));
      if (rec[best] == NULL)
        ndata--;
    } while (ndata > 1);

    for (i = 0; i < nstream; i++) {
      if (rec[i] != NULL) {
        do {
          if (!write_merge_record(rec[i], outfu, outbuff, &outbuff_bytes,
                                  temp[i])) {
            goto exit_merge_sort_files;
          }
          rec[i] = read_merge_record(infu[i], buff[i], &(buff_bytes[i]),
                                     &(buff_offset[i]), &(temp[i]));
        } while (rec[i] != NULL);
        break;
      }
    }

    if (outbuff_bytes) {
      if (Write(outfu, outbuff, outbuff_bytes) != outbuff_bytes) {
        goto exit_merge_sort_files;
      }
    }

    CloseFile(outfu);
    outfu = INVALID_FILE_HANDLE;
    k_free(outbuff);
    outbuff = NULL;

    for (i = 0; i < nstream; i++) {
      CloseFile(infu[i]);
      infu[i] = INVALID_FILE_HANDLE;
      make_workfile_path(sess, (int)lo_file + i, pathname, "merge_sort_files()");
      remove(pathname);
    }

    lo_file += nstream;
    num_files -= nstream - 1;
  }

  status = TRUE;

exit_merge_sort_files:
  for (i = 0; i < pcfg.sortmrg; i++) {
    if (temp[i] && (rec[i] != NULL))
      k_free(rec[i]);
    if (ValidFileHandle(infu[i]))
      CloseFile(infu[i]);
  }
  free_sort_merge_buffs(buff, pcfg.sortmrg);
  if (outbuff != NULL)
    k_free(outbuff);

  return status;
}

/* ======================================================================
   read_merge_record()  -  Read a record for a sort file merge            */

Private char* read_merge_record(
    OSFILE fu,
    char* buff,
    int32_t* buff_bytes,
    int32_t* buff_offset,
    bool* temp)
{
  char* rec = NULL;
  int32_t buff_len = 0;
  int32_t offset = 0;
  int32_t bytes;
  char* q;
  int32_t n;

  *temp = FALSE;

  if (buff == NULL)
    goto exit_read_merge_record;

  buff_len = *buff_bytes;
  offset = *buff_offset;

  if (offset >= buff_len) {
    buff_len = (int32_t)Read(fu, buff, DISK_BUFFER_SIZE);
    if (buff_len <= 0)
      goto exit_read_merge_record;
    offset = 0;
  }

  bytes = get32(buff + offset);

  if (offset + bytes <= buff_len) {
    rec = buff + offset;
    offset += bytes;
  } else {
    rec = (char*)k_alloc(67, bytes);
    if (rec == NULL)
      k_error("Insufficient memory for sort merge record");
    *temp = TRUE;

    q = rec;

    while (bytes) {
      n = buff_len - offset;
      if (n == 0) {
        buff_len = (int32_t)Read(fu, buff, DISK_BUFFER_SIZE);
        if (buff_len <= 0) {
          if (*temp && (rec != NULL)) {
            k_free(rec);
            rec = NULL;
            *temp = FALSE;
          }
          goto exit_read_merge_record;
        }
        offset = 0;
        n = buff_len;
      }
      n = min(bytes, n);
      memcpy(q, buff + offset, n);
      q += n;
      bytes -= n;
      offset += n;
    }
  }

exit_read_merge_record:
  *buff_bytes = buff_len;
  *buff_offset = offset;

  return rec;
}

/* ======================================================================
   write_merge_record()  -  Write to merge target file buffer             */

Private bool write_merge_record(
    char* rec,
    OSFILE fu,
    char* buff,
    int32_t* buff_bytes,
    bool temp)
{
  bool status = FALSE;
  int32_t bytes;
  int32_t space;
  int32_t used_bytes;
  int32_t n;
  char* q;

  used_bytes = *buff_bytes;

  bytes = get32(rec);

  q = rec;
  do {
    space = DISK_BUFFER_SIZE - used_bytes;
    if (space == 0) {
      if (Write(fu, buff, used_bytes) != used_bytes) {
        goto exit_write_merge_record;
      }

      used_bytes = 0;
      space = DISK_BUFFER_SIZE;
    }

    n = min(bytes, space);
    memcpy(buff + used_bytes, q, n);
    q += n;
    used_bytes += n;
    bytes -= n;
  } while (bytes);

  status = TRUE;

exit_write_merge_record:

  if (temp)
    k_free(rec);

  *buff_bytes = used_bytes;

  return status;
}

/* END-CODE */
