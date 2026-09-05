/* qmclilib.h - QM-compatible C/C++ API for the 32-bit sdclilib build.
 *
 * Modifications Copyright (c) 2026 Donald Montaine
 * Distributed under the GNU Lesser General Public License, version 3 or
 * later (LGPL-3.0-or-later). See LICENSE and GPLv3.txt for the full terms.
 *
 * Linking exception:
 *
 * As a special exception, the copyright holders of this library give you
 * permission to link this library with independent modules to produce an
 * executable, regardless of the license terms of these independent modules,
 * and to copy and distribute the resulting executable under terms of your
 * choice, provided that you also meet, for each linked independent module,
 * the terms and conditions of the license of that module. An independent
 * module is a module which is not derived from or based on this library. If
 * you modify this library, you may extend this exception to your version of
 * the library, but you are not obligated to do so. If you do not wish to do
 * so, delete this exception statement from your version.
 */

#ifndef QMCLILIB_H
#define QMCLILIB_H

/* 19 Aug 26 - the QM-named face of sdclilib, for applications written against
   the original QMClient API.  Every function below is the SD function of the
   same base name, reached through an export alias declared in qmclilib.def;
   there is no separate implementation and no forwarding layer.  Declaring
   SDConnect and QMConnect in one program is legal and calls the same code.

   SDCallx and SDGetArg have no QM name here, because the original QMClient
   had no such entry points for qmclilib.def to alias.  Both remain exported
   under their SD names, so a program that wants them can declare them from
   sdclilib.h.

   QMConnectLocal is declared but is a stub that always fails - it is
   Linux-only in sdclilib.  See qmcompat.c. */

#include <stdint.h>

#if defined(_WIN32)
#  if defined(BUILDING_SDCLILIB)
#    define QM_API __declspec(dllexport)
#  else
#    define QM_API __declspec(dllimport)
#  endif
#else
#  define QM_API
#endif

#ifdef __cplusplus
extern "C" {
#endif

QM_API void QMCall(char *subrname, int16_t argc, ...);
QM_API char *QMChange(char *src, char *old_string, char *new_string, int occurrences, int start);
QM_API void QMClearSelect(int listno);
QM_API void QMClose(int fno);
QM_API int QMConnect(char *host, int port, char *username, char *password, char *account);
QM_API int QMConnected(void);
QM_API int QMDcount(char *src, char *delim);
QM_API void QMDebug(int16_t mode);
QM_API char *QMDel(char *src, int fno, int vno, int svno);
QM_API void QMDelete(int fno, char *id);
QM_API void QMDeleteu(int fno, char *id);
QM_API void QMDisconnect(void);
QM_API void QMDisconnectAll(void);
QM_API void QMEndCommand(void);
QM_API int16_t QMEnterPackage(char *name);
QM_API char *QMError(void);
QM_API char *QMExecute(char *command, int *err);
QM_API int16_t QMExitPackage(char *name);
QM_API char *QMExtract(char *src, int fno, int vno, int svno);
QM_API char *QMField(char *src, char *delim, int first, int occurrences);
QM_API void QMFree(void *p);
QM_API int QMGetSession(void);
QM_API char *QMIns(char *src, int fno, int vno, int svno, char *new_string);
QM_API int QMLocate(char *item, char *src, int fno, int vno, int svno, int *pos, char *order);
QM_API int QMLogto(char *account_name);
QM_API void QMMarkMapping(int16_t fno, int16_t state);
QM_API int QMMatch(char *str, char *pattern);
QM_API char *QMMatchfield(char *str, char *pattern, int component);
QM_API int QMOpen(char *filename);
QM_API char *QMRead(int fno, char *id, int *err);
QM_API char *QMReadList(int listno);
QM_API char *QMReadNext(int16_t listno);
QM_API char *QMReadl(int fno, char *id, int wait, int *err);
QM_API char *QMReadu(int fno, char *id, int wait, int *err);
QM_API void QMRecordlock(int fno, char *id, int update_lock, int wait);
QM_API void QMRelease(int fno, char *id);
QM_API char *QMReplace(char *src, int fno, int vno, int svno, char *new_string);
QM_API char *QMRespond(char *response, int *err);
QM_API void QMSelect(int fno, int listno);
QM_API void QMSelectIndex(int16_t fno, char *index_name, char *index_value, int16_t listno);
QM_API char *QMSelectLeft(int16_t fno, char *index_name, int16_t listno);
QM_API char *QMSelectRight(int16_t fno, char *index_name, int16_t listno);
QM_API void QMSetLeft(int16_t fno, char *index_name);
QM_API void QMSetRight(int16_t fno, char *index_name);
QM_API int QMSetSession(int session);
QM_API int QMStatus(void);
QM_API void QMWrite(int fno, char *id, char *data);
QM_API void QMWriteu(int fno, char *id, char *data);
QM_API int QMConnectLocal(char *account);

#define SV_OK       0
#define SV_ON_ERROR 1
#define SV_ELSE     2
#define SV_ERROR    3
#define SV_LOCKED   4
#define SV_PROMPT   5
/* 15 Aug 26 - TRANSPOSED, NOW CORRECTED.  13e4bf5 "Align Windows client
   error handling with Linux" introduced these as ECONTXT=6/EMSG_PAIR=7,
   which is the opposite of the sdb64 commit d0647b9 it was aligning TO -
   that had defined EMSG_PAIR=6/ECONTXT=7 seventeen days earlier, on
   19 Jul 2026.  sdb64's values came first and are the shared ones.  Names
   identical, values swapped, is the worst kind of disagreement to leave. */
#define SV_EMSG_PAIR 6
#define SV_ECONTXT   7

#ifdef __cplusplus
}
#endif

#endif
