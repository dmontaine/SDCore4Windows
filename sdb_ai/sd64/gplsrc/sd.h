/* SD.H
 * Common include file for all modules
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
 * 25 Oct 26 Windows port - from Linux fc4030a (S.66): EDIT_SHARED_WRITE and EDIT_SHARED_STRUCT; prototypes of the shared-account tests (op_sh.c), of
 *               shared_structure_refusal() (op_dio3.c) and of get_voc_file_reference_ex() (op_dio1.c).
 * 17 Oct 26 Windows port - from Linux e7ea5f8 - S.65 slice 3c: prototypes of netfiles.c (net_open, net_close, net_read, net_readv, net_fileinfo, net_refuse, net_close_all, net_message).
 * 18 Oct 26 Windows port - from Linux 5315c65 - S.65 slice 3e: prototypes and constants of the write and lock entry points of netfiles.c (net_gate, net_write, net_delete, net_clear,
 * 19 Oct 26 Windows port - from Linux fc8e304 - S.67, the verifier's findings: masters_note_read, masters_cas_on and masters_cas_check (a save of a master record is judged against the record the
 * 20 Oct 26 Windows port - from Linux eb9ef4a - S.72b: NETG_PEEK (net_gate's read-mode test alone, for RECORDLOCKED()).
 *               session read, and again inside the account's write).
 * 19 Oct 26 Windows port - from Linux fc8e304 - S.67: prototypes of masters.c (stage 1: the hook and K_MASTERS; stage 2: masters_before_write, masters_before_delete,
 *               masters_txn_refusal, masters_refusal_text, masters_fix_modes and the status DHE_MASTER_REFUSED).
 * 18 Oct 26 Windows port - from Linux fc8e304 - S.66: EDIT_SHARED_WRITE and EDIT_SHARED_STRUCT; prototypes of the shared-account tests (op_sh.c), of shared_structure_refusal()
 *               (op_dio3.c) and of get_voc_file_reference_ex() (op_dio1.c).
 * 20 Oct 26 Windows port - from Linux fc8e304 - S.72: prototypes of net_filelock_step, net_fileunlock and net_recordlocked (netfiles.c).
 *               net_lock, net_lock_step, net_check_lock, net_release, net_release_all, net_flush_closes) and edit_kind_of_net_name().
 * 17 Oct 26 Windows port - from Linux 5315c65 - S.65 slice 3c: prototypes of netfiles.c (net_open, net_close, net_read, net_readv, net_fileinfo, net_refuse, net_close_all, net_message).
 * 17 Oct 26 dm  S.64 part 2: edit_os_path_refusal() takes include_leaf (does the final component of the path count?); edit_leaf_counts().
 * 17 Oct 26 dm  S.64: prototypes of the edit gates (op_sh.c): edit_kind_of_path, edit_permitted, edit_ok_for_path, edit_os_path_refusal.
 * 31 Dec 23 SD launch - prior history suppressed
 * END-HISTORY
 * 
*/

#ifndef __SD
#define __SD

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stddef.h>
#include <limits.h>
#include <fcntl.h>
#include <dirent.h>
#include <errno.h>
#include <sys/types.h>
#include <sys/stat.h>

#include "sddefs.h"

/* Select list limits */

#define HIGH_SELECT          12
#define HIGH_USER_SELECT     10
#define InvalidSelectListNo(list_no) \
 ((list_no < 0) \
  || (list_no > HIGH_SELECT) \
  || ((list_no > HIGH_USER_SELECT) && !(process.program.flags & HDR_INTERNAL)))
#define SelectList(n) \
 Element(Element(process.syscom, SYSCOM_SELECT_LIST)->data.ahdr_addr, (n))
#define SelectCount(n) \
 Element(Element(process.syscom, SYSCOM_SELECT_COUNT)->data.ahdr_addr, (n))



/* Memory management */

   #define k_alloc(tag, n) malloc(n)
   #define k_free(p) free(p)

#define k_free_ptr(p) if (p != NULL) k_free(p), p = NULL

/* Typedefs */

typedef struct DESCRIPTOR DESCRIPTOR;
typedef struct STRING_CHUNK STRING_CHUNK;
typedef struct FILE_VAR FILE_VAR;
typedef struct ARRAY_CHUNK ARRAY_CHUNK;
typedef struct ARRAY_HEADER ARRAY_HEADER;
typedef struct SCREEN_IMAGE SCREEN_IMAGE;
typedef struct BTREE_HEADER BTREE_HEADER;
typedef struct PMATRIX_HEADER PMATRIX_HEADER;
typedef struct SOCKVAR SOCKVAR;
typedef struct OBJDATA OBJDATA;
typedef struct COLL_HEADER COLL_HEADER;
typedef struct COLL_ENTRY COLL_ENTRY;

/* ======================================================================
   Standard includes needed everywhere                                    */

#include "dh.h"
#include "sysseg.h"
#include "err.h"
#include "descr.h"
#include "kernel.h"
#include "sdsem.h"
#include "linuxlb.h"
#include "exepath.h"

/* ======================================================================
   Command line items                                                     */

Public int16_t command_options init(0);
#define CMD_APPLY_LICENCE    0x0001      /* -l option */
#define CMD_QUERY_ACCOUNT    0x0002      /* -a option */
#define CMD_INSTALL          0x0004      /* -i option */
#define CMD_QUIET            0x0008      /* -quiet option */
#define CMD_PERSONAL         0x0010      /* -ip option */
#define CMD_STDOUT           0x0020      /* -stdout option (Windows) */
#define CMD_FLASH            0x0040      /* -f option */

Public bool trace_option init(FALSE);    /* -t option */

/* ======================================================================
   Environment                                                            */

Public bool internal_mode
#ifdef INTERNAL
            init(TRUE);
#else
            init(FALSE);
#endif

/* Mapping for directory file record names */

Public char * df_restricted_chars init("*,=><%/+:;?\\\"");
Public char * df_substitute_chars init("ACEGLPSVXYZBQ");
/* Also, leading . and ~ become %d and %t */

/* Date formats */

Public bool european_dates init(FALSE);
Public char default_date_conversion[32+1] init("D");

#define MAX_NLS_CURRENCY 8
Public struct
{
 char currency[MAX_NLS_CURRENCY+1];
 char thousands;
 char decimal;
} national;

Public char * null_string init("");
Public char * CRLF init("\r\n");

/* ======================================================================
   Internal function definitions                                          */

/* SD.C */
void fatal(void);
void dump(u_char * addr, int32_t bytes);
void set_console_title(void);

/* ANALYSE.C */
int64 dir_filesize(FILE_VAR * fvar);

/* CONFIG.C */
   struct CONFIG * read_config(char * errmsg);

/* CONSOLE.C */
bool init_console(void);
void shut_console(void);
bool write_console(char * p, int bytes);
bool save_screen(SCREEN_IMAGE * scrn, int16_t x, int16_t y,
                 int16_t w, int16_t h);
void restore_screen(SCREEN_IMAGE * scrn, bool restore_cursor);
void set_codepage(void);

/* CTYPE.C */
void set_default_character_maps(void);
char * LowerCaseString(char * s);
int MemCompareNoCase(char * p, char * q, int16_t len);
char * memichr(char * s, char c, int n);
void memucpy(char * tgt, char * src, int16_t len);
int sort_compare(char * s1, char * s2, int16_t bytes, bool nocase);
int StringCompLenNoCase(char * p, char * q, int16_t len);
void UpperCaseMem(char * str, int16_t len);
char * UpperCaseString(char * s);
/* 20240225  add misc dyn array functions for c strings */
char* Extract(char* src, int fno, int vno, int svno);
int Dcount(char* src, char* delim_str);

/* DH_FILE.C */
OSFILE dio_open(char * fn, int mode);
   #define DIO_NEW       1 /* Create new file, fail if exists */
   #define DIO_REPLACE   2 /* Create new file, overwriting if exists */
   #define DIO_READ      3 /* Open existing file, read only */
   #define DIO_UPDATE    4 /* Open existing file, read/write */
   #define DIO_OVERWRITE 5 /* Open file, creating if doesn't exist */

/* INIPATH.C */
bool GetConfigPath(char * inipath);

/* KERNEL.C */
int16_t assign_user_no(int16_t user_table_index, bool interactive);
bool init_kernel(void);
int16_t in_group(char * name);
char * account(void);
void kernel(void);
void k_recurse(u_char * code_ptr, int num_args);
void k_recurse_object(u_char * code_ptr, int num_args, OBJDATA * objdata);
void k_call(char * name, int num_args, u_char * code_ptr, int16_t stack_adj);
void k_return(void);
void k_run_program(void);
bool raise_event(int16_t event, int16_t user);
/* 04 Sep 26 Windows port - PRE_RELEASE_FIXES.md 16.  Declared beside
   raise_event() because op_logout() chooses between the two: an event for a
   session that is still there, a reap for one that is not.  Defined in
   clopts.c, beside cleanup(), whose process_exists() and remove_user() it
   shares so that both routes reclaim a slot identically.                   */
bool reap_lost_user(int16_t user);
void process_events(void);
void show_stack(void);
void sigchld_handler(int signum);
void suspend_updates(void);
void ReleaseLicence(USER_ENTRY * uptr);

/* K_ERROR.C */
void k_data_type(DESCRIPTOR * descr);
void k_deadlock(void);
void k_dh_error(DESCRIPTOR * descr);
void k_div_zero_error(DESCRIPTOR * descr);
void k_div_zero_warning(DESCRIPTOR * descr);
void k_illegal_call_name(void);
void k_index_error(DESCRIPTOR * descr);
void k_not_array_error(DESCRIPTOR * descr);
void k_value_error(DESCRIPTOR * descr);
void k_non_numeric_error(DESCRIPTOR * descr);
void k_non_numeric_warning(DESCRIPTOR * descr);
void k_unassigned(DESCRIPTOR * descr);
void k_strnum_len(DESCRIPTOR * descr);
void k_not_socket(DESCRIPTOR * descr);
void k_null_id(DESCRIPTOR * descr);
void k_illegal_id(DESCRIPTOR * descr);
void k_inva_task_lock_error(void);
void k_nary_length_error(void);
void k_select_range_error(void);
void k_txn_error(void);
void k_unassigned_zero(DESCRIPTOR * descr);
void k_unassigned_null(DESCRIPTOR * descr);
void k_error(char msg[], ...);
void k_quit(void);
void k_err_pu(void);
int k_line_no(int32_t offset, u_char * xcbase);
void try_level_gone(void);                   /* op_jumps.c: TRY frames of a returned level */
void exc_value(int which, DESCRIPTOR * descr); /* op_jumps.c: @EXCEPTION and friends */
bool exc_sys_can_catch(const char * name);       /* op_jumps.c: would a throw of this SYS.* exception find a handler? */
void exc_sys_throw(const char * name, const char * text); /* op_jumps.c: throw it; returns only if nothing can catch it */
bool k_can_resume(void);                         /* kernel.c: does a dispatch loop stand ready to take a system exception? */
void k_resume_exception(void);                   /* kernel.c: go back to it (does not return) */
void txn_rollback_to(int depth);                 /* txn.c: roll back the transactions begun since the nesting depth was depth */
char * k_var_name(DESCRIPTOR * descr);
void log_message(char * msg);
void audit_message(char * msg);
void audit_rotate(void);
int log_printf(char * str, ...);
void log_permissions_error(FILE_VAR * fvar);

/* K_FUNCS.C */
bool k_blank_string(DESCRIPTOR * descr);
DESCRIPTOR * k_dereference(DESCRIPTOR * p);
void k_get_num(DESCRIPTOR * p);
void k_get_bool(DESCRIPTOR * p);
void k_get_int(DESCRIPTOR * p);
void k_get_int32(DESCRIPTOR * p);
void k_get_float(DESCRIPTOR * p);
void k_get_string(DESCRIPTOR * p);
void k_get_file(DESCRIPTOR * p);
void k_get_value(DESCRIPTOR * p);
void k_num_array1(void(op(void)));
void k_num_array2(void(op(void)), int16_t default_value);
void k_release(DESCRIPTOR * p);
void k_deref_image(SCREEN_IMAGE * image);
void k_deref_string(STRING_CHUNK * str);
void coll_deref(COLL_HEADER * h);
bool coll_record_in(DESCRIPTOR * d);
bool coll_record_text(DESCRIPTOR * d);
void coll_debug_json(COLL_HEADER * h);
COLL_ENTRY * coll_debug_find(COLL_HEADER * root, char * path, int32_t len);
void csv_dequote(DESCRIPTOR * src_descr, char delim); /* op_csv.c: CSVDQ() of a comma (or other delimiter) separated line */
/* 20 Oct 26 dm - op_coll.c's building blocks, for the format code (op_csv.c, op_json.c, op_xml.c): CSV, JSON merge / patch / path / schema, XML */
COLL_HEADER * coll_new(bool is_array);
COLL_HEADER * coll_copy(COLL_HEADER * src);
void coll_insert(COLL_HEADER * h, int32_t pos);
void coll_remove(COLL_HEADER * h, int32_t pos);
bool coll_find(COLL_HEADER * h, char * name, int32_t len, int32_t * pos);
DESCRIPTOR coll_str_descr(char * s, int32_t len);
char * coll_chunks_to_buffer(STRING_CHUNK * s, int32_t * len);
int32_t coll_number_len(unsigned char * s, int32_t len, bool * is_int);
DESCRIPTOR coll_json_parse(char * text, int32_t len, int mode);
DESCRIPTOR coll_json_build(COLL_HEADER * root, int mode);
void coll_fill_entry(COLL_ENTRY * ent, DESCRIPTOR * v);
DESCRIPTOR coll_value_of(COLL_ENTRY * e);
int32_t url_encode_top(void);
int32_t url_decode_top(void);
int k_get_c_string(DESCRIPTOR * descr, char * s, int max_bytes);
void k_incr_refct(DESCRIPTOR * p);
void k_put_c_string(char * s, DESCRIPTOR * descr);
void k_put_string(char * s, int len, DESCRIPTOR * descr);
void k_num_to_str(DESCRIPTOR * p);
bool k_str_to_num(DESCRIPTOR * p);
STRING_CHUNK * k_copy_string(STRING_CHUNK * src);
bool k_is_num(DESCRIPTOR * p);
bool strdbl(char * p, double * value);
bool strnint(char * p, int16_t len, int32_t * value);
void k_unass_zero(DESCRIPTOR * original, DESCRIPTOR * dereferenced);
void k_unass_null(DESCRIPTOR * original, DESCRIPTOR * dereferenced);
u_int32_t GetUnsignedInt(DESCRIPTOR * descr);

#define k_pop(n) e_stack -= n
#define k_dismiss() k_release(--e_stack)


/* MESSAGES.C */
bool init_messages(void);
char * sysmsg(int msg_no);
char * sysmsg_arg1(int msg_no, const char * arg);
int sysmsg_number_of(const char * p);

/* NETFILES.C - files on another SD server (SDNet, S.65 slice 3c).  Gone in plan G4, back in a new form: the kernel holds no socket code, it
   calls the BASIC handler $netfile (sdsys/gpl.bp/netfile) as call_trigger() calls a trigger.  sdnet.h is a different file (the
   socket/termios portability header) and stays.
   net_open() returns 0 (fvar is now a NET_FILE), a positive status for the ELSE branch, or a negative one with net_message() set; it
   never raises the error itself (open_file() does).  net_read(), net_readv(), net_fileinfo() and net_refuse() RAISE the error with the
   handler's message, unless process.op_flags holds P_ON_ERROR at the call (they read nothing else of it and give it back as it was);
   without ON ERROR they do not return on an error.  net_close() is for dio_close(): it talks to the server only for a CLOSE statement.
   Every one of them that asks the handler runs BASIC, which can move the e-stack: find operands again by e_stack afterwards.
   net_close_all() is for LOGTO (via a kernel key) and sends NF$CLOSEALL when this process ever opened a remote file.            */
bool net_path_is_net(const char * path);
int net_open(FILE_VAR * fvar, const char * encoded_path);
void net_close(FILE_VAR * fvar);
int net_read(FILE_VAR * fvar, char * id, int16_t id_len, STRING_CHUNK ** rec);
int net_readv(FILE_VAR * fvar, char * id, int16_t id_len, int32_t field, STRING_CHUNK ** out);
STRING_CHUNK * net_fileinfo(FILE_VAR * fvar, int key);
int net_select(FILE_VAR * fvar, STRING_CHUNK ** ids, int32_t * count);
int net_refuse(FILE_VAR * fvar, const char * what);
void net_close_all(void);
const char * net_message(void);

/* NETFILES.C, slice 3e (18 Oct 26): writes and locks on a file of a server whose definition says mode=write (.claude/s65-stage2-design.md, 5.1).
   The same convention as net_read(): 0 is done, a negative status is an error that has ALREADY been raised unless the caller put P_ON_ERROR in
   process.op_flags (net_gate() takes it from its op_flags argument).  Each sets process.status itself afterwards, gives process.op_flags back
   as found, and runs BASIC (the handler) except net_gate(), net_check_lock() and net_refuse(): find operands again by e_stack afterwards.
   net_gate() decides whether the statement may go on at all (a read-mode handle: message 12506, as before; CREATING.SEQKEY; a transaction;
   the S.64 edit gate for the remote file's name) and sends nothing.  net_write() is given the record as a string chain and does not flatten
   it.  net_lock() is the no-wait form only: 0 held, ER_LCK busy with process.status the holder's user number (-1 table full, -2 deadlock);
   net_lock_step() is the READU / RECORDLOCKU idiom around it: NET_LOCK_WAIT means the caller has been set up to run the opcode again after
   250 ms (process.op_flags = op_flags, pc = retry_pc) and must RETURN AT ONCE; NET_LOCK_LOCKED that the lock is busy and the statement has a
   LOCKED clause (process.status = the holder).  retry_pc is op_pc as captured at the entry of the opcode, BEFORE the first net_ call: the
   handler's own opcodes overwrite op_pc.  net_check_lock() answers 1 when this session holds the update lock on the record.  net_release() and
   net_release_all() never raise and ignore the answer; net_release_all() does nothing unless this process opened a write-mode file.
   net_flush_closes() sends the queued closes (the lock of a file variable that went out of scope ends with its handle).               */
#define NETG_WRITE 1   /* WRITE WRITEU MATWRITE WRITEV WRITEVU */
#define NETG_DELETE 2  /* DELETE */
#define NETG_CLEAR 3   /* CLEARFILE */
#define NETG_LOCK 4    /* READU READL MATREADU MATREADL READVU READVL RECORDLOCKU RECORDLOCKL */
#define NETG_PEEK 5    /* RECORDLOCKED(): only the read-mode test of net_gate (S.72b) - it changes nothing, so a transaction does not matter */
#define NET_LOCK_HELD 0
#define NET_LOCK_WAIT 1
#define NET_LOCK_LOCKED 2
#define NET_ID_MAX 63  /* the server's limit for a record id (the class MAX.ID.LEN): a longer one is -ER_IID before anything is sent */
int net_gate(FILE_VAR * fvar, int kind, u_int16_t op_flags, const char * what);
int net_write(FILE_VAR * fvar, char * id, int16_t id_len, STRING_CHUNK * rec, bool keep_lock);
int net_delete(FILE_VAR * fvar, char * id, int16_t id_len, bool keep_lock);
int net_clear(FILE_VAR * fvar);
int net_lock(FILE_VAR * fvar, char * id, int16_t id_len, bool update);
int net_lock_step(FILE_VAR * fvar, char * id, int16_t id_len, bool update, u_int16_t op_flags, u_char * retry_pc);
/* S.72 (20 Oct 26, QMNet parity).  net_filelock_step() is FILELOCK as net_lock_step() is READU: net_gate() first (a refusal is returned at once), then the no-wait request 32 and
   the same three answers.  net_fileunlock() gives 0, ER_LCK or ER_NLK (what a local FILEUNLOCK leaves in STATUS(), and process.status is it) or a negative status.  net_recordlocked()
   gives the server's code -3 to 3 and leaves the lock owner's user number in process.status; it has no ON ERROR clause, so an error is raised, always, and it asks no gate (a read). */
int net_filelock_step(FILE_VAR * fvar, u_int16_t op_flags, u_char * retry_pc);
int net_fileunlock(FILE_VAR * fvar, u_int16_t op_flags);
int net_recordlocked(FILE_VAR * fvar, char * id, int16_t id_len);
int net_check_lock(FILE_VAR * fvar, char * id, int16_t id_len);
void net_release(FILE_VAR * fvar, char * id, int16_t id_len);
void net_release_all(void);
void net_flush_closes(void);

/* OBJECT.C */
void * load_object(char * name, bool abort_on_error);
void unload_object(void * obj_hdr);
void unload_all(void);
bool is_global(void * obj_hdr);
void stale_objects(void);
bool object_is_stale(void * obj_hdr);
void * refresh_subr_object(void * obj_hdr);
void invalidate_object(void);
void * find_object(int32_t id);
STRING_CHUNK * hsm_dump(void);
void hsm_enter(void);
void hsm_on(void);
/* 14 Oct 26 - sheet item 491: count a file operation against the running program (object.c) */
#define HSM_OPEN 0
#define HSM_READ 1
#define HSM_WRITE 2
#define HSM_DELETE 3
void hsm_io(int what);

/* OBJPROG.C */
OBJDATA * create_objdata(u_char * obj);
void free_object(OBJDATA * objdata);

/* OP_ARRAY.C */
ARRAY_HEADER * a_alloc(int32_t rows, int32_t cols, bool init_zero);
void free_common(ARRAY_HEADER * addr);
void free_array(ARRAY_HEADER * hdr_addr);
void delete_common(ARRAY_HEADER * ahdr);

/* OP_EXEC.C */
void stdfil_shared_restore(void);

/* PROFILER.C: the application event profiler (16 Oct 26, QM4 gap 66) */
#define PROF_CALL     0x0001
#define PROF_OPEN     0x0002
#define PROF_READ     0x0004
#define PROF_WRITE    0x0008
#define PROF_DELETE   0x0010
#define PROF_OPENSEQ  0x0020
#define PROF_READSEQ  0x0040
#define PROF_WRITESEQ 0x0080
#define PROF_EXECUTE  0x0100
#define PROF_OBJECT   0x0200
#define PROF_TYPES    10
#define PROF_ALL      0x03FF
Public int16_t prof_mask init(0);
void prof_set(int16_t mask);
void prof_event(int16_t bit, const char* qual, int qlen);
void prof_dump(DESCRIPTOR* result);
/* The hooks the opcodes use: nothing at all unless a profile is on. */
#define ProfEvent(bit, qual, qlen) do { if (prof_mask & (bit)) prof_event((bit), (qual), (qlen)); } while (0)
#define ProfFile(bit, fv) do { if (prof_mask & (bit)) prof_file_event((bit), (fv)); } while (0)
void prof_file_event(int16_t bit, FILE_VAR * fvar);

/* OP_LOCK.C: OPTION COMMAND.LEVEL.LOCKS */
Public bool explicit_close init(FALSE); /* op_close() is releasing the file variable: park_fvar() leaves it alone */
bool park_fvar(FILE_VAR * fvar);
void release_parked_fvars(int16_t level);

/* OP_BTREE.C */
bool bt_get_string(DESCRIPTOR * descr, char ** s);
void btree_to_string(DESCRIPTOR * descr);
void free_btree_element(BTREE_ELEMENT * element, int16_t keys);

/* OP_DIO1.C */
#define VOC_FLAGS_LEN 15  /* Longest field 6 of an F-type VOC entry that open_file() reads */
void dio_close(FILE_VAR * fvar);
bool get_voc_file_reference(char * voc_name, bool get_dict_name,
                            char * path, char * vflags);
/* 18 Oct 26 S.66: the same with a fifth argument; only open_file() passes TRUE, and only then may _voc_ref fall back to the shared account */
bool get_voc_file_reference_ex(char * voc_name, bool get_dict_name,
                               char * path, char * vflags, bool allow_shared);
void flush_dh_cache(void);

/* OP_DIO3.C - line terminator modes of directory and sequential files (16 Oct 26, QM4 Fixes item 452) */
u_char crlf_from_vflags(const char * vflags);
/* ...and the trigger function of a directory file (16 Oct 26, QM4 Fixes item 177) */
void dir_trigger_open(FILE_VAR * fvar, const char * dirpath);
void dir_trigger_close(FILE_VAR * fvar);
int dir_set_trigger(FILE_VAR * fvar, const char * name, int modes);
bool is_dir_header(const char * name);

/* OP_SH.C - the per-account OS-access gates (13 Oct 26, S.63; carried 23 Oct 26) */
bool os_gate_open(void);
bool os_path_ok_for_account(const char * name);
bool os_path_open_ok(const char * name);
bool os_path_inside(const char * rootdir, const char * name);

/* OP_SH.C - the edit gates (17 Oct 26, S.64): which guarded kind a file is, and may the session save a change to it */
#define EDIT_NONE 0
#define EDIT_VOC  1
#define EDIT_DICT 2
#define EDIT_PROG 3
/* 18 Oct 26 S.66: a record write to a file of the shared account needs shared.write (4); a structure change to one is SDSYS's alone (5, raised by
   the kernel structure refusals only, which print their own text; K$EDIT.KIND never answers 5) */
#define EDIT_SHARED_WRITE  4
#define EDIT_SHARED_STRUCT 5
bool shared_root_get(char * out);
bool path_in_shared(const char * canon);
bool path_resolved_in_shared(const char * name);
bool shared_write_ok(void);
int edit_refusal_for_canon(const char * canon);
int edit_refusal_for_name(const char * name);
bool shared_ref_ok(const char * path, int fno, const char * catname);
bool shared_once(const char * name);
int edit_refused_message(int kind);
int shared_structure_refusal(FILE_VAR * fvar);
int edit_kind_of_path(const char * path);
int edit_kind_of_net_name(const char * name); /* 18 Oct 26 S.65 slice 3e: the same, for the name of a file on another server ("dict " prefix and all); op_sh.c */
bool edit_permitted(int kind);
bool edit_ok_for_path(const char * path);
int edit_os_path_refusal(const char * name, bool include_leaf);
bool edit_leaf_counts(const char * name);

/* OP_DIO2.C */
bool delete_path(char * path);
bool fullpath(char * path, char * name);
bool make_path(char * tgt);
/* 21 Aug 26 Windows port - the containment gate for a network session.  Call
   it with an ABSOLUTE path, i.e. after fullpath(): it compares against @PATH
   and relies on sdrealpath() having already collapsed "..".  23 Oct 26: it now
   answers for EVERY session (owner, 23 Oct: the console is held too), TRUE for
   an administrator and for an account that holds OS.EXECUTE (os_gate_open()).
   account_path_permitted() is the same test without the $internal exemption.

   for_write SEPARATES THE TWO ANSWERS.  The account and NETDIRS are
   read-write; the shipped SDSYS entries a stock VOC needs are READ ONLY, so
   asking with TRUE about one of those is refused while FALSE is admitted.  A
   caller that opens without knowing the mode - which is every SD OPEN - asks
   with TRUE first and marks the file variable FV_RDONLY when the answer is no.
   See op_dio2.c.                                                           */
bool net_path_permitted(char * path, bool for_write);
bool account_path_permitted(char * path, bool for_write);
bool net_vocpath_permitted(char * path, bool for_write);
bool path_in_enterable_account(char * resolved);
bool path_view_for_edit(char * resolved, char * rel, size_t rel_size);
bool path_fold(char * resolved, char * out);

/* OP_DIO3.C */
bool dir_write(FILE_VAR * fvar, char * mapped_id, STRING_CHUNK * str);
/* 4 Sep 26 Windows port - the read half, which the directory code never had.
   PRE_RELEASE_FIXES 102.  Takes a MAPPED id, like dir_write().  */
bool dir_read(FILE_VAR * fvar, char * mapped_id, STRING_CHUNK ** str,
              int16_t * status);
bool map_t1_id(char * id, int16_t id_len, char * mapped_id);
bool call_trigger(DESCRIPTOR * fvar_descr, int16_t mode, DESCRIPTOR * id_descr,
                  DESCRIPTOR * data_descr, bool on_error, bool updatable);

/* OP_DIO4.C */
bool dio_init(void);
void clear_select(int16_t list_no);
void complete_select(int16_t list_no);
void end_select(int16_t list_no);

/* OP_ICONV.C */
int32_t iconv_time_conversion(void);

/* OP_JUMPS.C */
bool valid_call_name(char * call_name);

/* OP_LOCK.C */
bool check_lock(FILE_VAR * fvar, char * id, int16_t id_len);
int16_t lock_record(FILE_VAR *, char * id, int16_t id_len, bool update,
                      u_int32_t txn_id, bool no_wait);
bool unlock_record(FILE_VAR *, char * id, int16_t id_len);
char * deadlock_info_string(int * len);
void unlock_txn(u_int32_t txn);
void transfer_txn_locks(u_int32_t from, u_int32_t to); /* 15 Oct 26: a non-durable child commit hands its locks to the parent */
void clear_lock_wait(void);
void rebuild_llt(void);

/* OP_MISC.C */
void day_to_dmy(int32_t day_no, int16_t * day, int16_t * mon,
                int16_t * year, int16_t * julian);
char * day_to_ddmmmyyyy(int32_t day_no);

/* OP_OCONV.C */
int32_t length_conversion(char * p);
int oconv_d(int dt, char * code, char * tgt);

/* OP_SEQIO.C */
void close_seq(FILE_VAR * fvar);

/* OP_SKT.C */
void close_skt(SOCKVAR * skt);

/* OP_STR1.C */
void set_case(bool upcase);

/* OP_STR2.C */
bool find_item(STRING_CHUNK * str, int32_t field, int32_t value,
               int32_t subvalue, STRING_CHUNK ** chunk, int16_t * offset);
STRING_CHUNK * copy_string(STRING_CHUNK * tail, STRING_CHUNK ** head,
                      char * src, int16_t len, int16_t * chunk_size);

/* OP_STR4.C */
bool match_template(char * string, char * tmpl,
                    int16_t component, int16_t return_component);

/* TIME.C */
int32_t local_time(void);
int32_t sdtime(void);

/* OP_TIO.C */
void como_close(void);
void free_print_units(void);
bool settermtype(char * name);
void squeek(void);
bool tio_display_string(char * q, int16_t bytes, bool flush, bool transparent_newline);
bool tio_handle_break(void);
bool tio_init(void);
int tio_printf(char * tmpl, ...);
void tio_shut(void);
void tio_write(char * s);
/* op_sh.c - 17 Sep 26: Windows PowerShell's path, for sh() and the print
   spooler (linuxprt.c) alike. */
void sd_powershell_path(char * buf, int len);
void freescrn(SCREEN_IMAGE * image);
void break_key(void);
int16_t keyin(int timeout);
bool keyready(void);
int32_t type_ahead_count(void);
bool write_socket(char * str, int bytes, bool flush);
bool to_outbuf(char * str, int bytes);
void lock_beep(void);

/* PDUMP.C */
void pdump(void);

/* SDLIB.C */
int ftoa(double f, int16_t dp, bool truncate, char * result);
int strdcount(char * s, char d);
void strrep(char * s, char oldstr, char newstr);

/* RECCACHE.C */
void dump_rec_cache(void);
void init_record_cache(void);
void cache_record(int16_t fno, int16_t id_len, char * id, STRING_CHUNK * head);
bool scan_record_cache(int16_t fno, int16_t id_len, char * id, 
                       STRING_CHUNK ** data);

/* SOCKIO.C */
bool start_connection(int sa);
void shut_connection(void);
bool read_socket(char * str, int bytes);
bool flush_outbuf(void);

/* STRINGS.C */
char * alloc_c_string(DESCRIPTOR * descr);
char * dupstring(char * str);
STRING_CHUNK * s_alloc(int32_t size, int16_t * actual_size);
STRING_CHUNK * s_make_contiguous(STRING_CHUNK * str_addr, int16_t * errnum);
void s_free(STRING_CHUNK * p);
void s_free_all(void);
void setsdstring(char ** strptr, DESCRIPTOR * descr);
void setstring(char ** strptr, char * string);
void ts_fill(char c, int32_t len);
void ts_init(STRING_CHUNK ** head, int32_t base_size);
void ts_new_chunk(void);
void ts_copy_byte(char c);
void ts_copy(char * src, int len);
void ts_copy_c_string(char * str);
int ts_printf(char * tmpl, ...);
int32_t ts_terminate(void);
void ts_stack(void);
void ts_unstack(void);

/* SYSSEG.C */
bool attach_shared_memory(void);
void unbind_sysseg(void);
bool start_sd(void);
bool stop_sd(void);


/* WIN.C / LINUXIO.C */
/* 17 Aug 26 Windows port - login_user() is gone; the API authenticates
   against $CRED in APISRVR.  linuxio.c has the reasoning.                */
int64 lseek64(OSFILE handle, int64 offset, int fromwhere);
int64 filelength64(OSFILE handle);
int chsize64(OSFILE handle, int64 posn);
int sdpoll(int fd, int timeout);

/* WINPORT.C / LNXPORT.C */

bool is_port(char * name);
int openport(char * name);
void closeport(int hPort);
int readport(int hPort, char * str, int16_t bytes);
bool writeport(int hPort, char * str, int16_t bytes);
#endif

/* END-CODE */
