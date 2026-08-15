/* sdclilib.h - public C/C++ API for the sdclilib ScarletDME client library.
 *
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

#ifndef SDCLILIB_H
#define SDCLILIB_H

#include <stdint.h>

#if defined(_WIN32)
#  if defined(BUILDING_SDCLILIB)
#    define SD_API __declspec(dllexport)
#  else
#    define SD_API __declspec(dllimport)
#  endif
#else
#  define SD_API
#endif

#ifdef __cplusplus
extern "C" {
#endif

SD_API void SDCall(char *subrname, int16_t argc, ...);
SD_API void SDCallx(char *subrname, int16_t argc, ...);
SD_API char *SDGetArg(int arg_number);
SD_API char *SDChange(char *src, char *old_string, char *new_string, int occurrences, int start);
SD_API void SDClearSelect(int listno);
SD_API void SDClose(int fno);
SD_API int SDConnect(char *host, int port, char *username, char *password, char *account);
/* Connect to an SD server on this machine over a named pipe, authenticated
   from the calling process owner.  No host, port or credentials are needed. */
SD_API int SDConnectLocal(char *account);
SD_API int SDConnected(void);
SD_API int SDDcount(char *src, char *delim);
SD_API void SDDebug(int16_t mode);
SD_API char *SDDel(char *src, int fno, int vno, int svno);
SD_API void SDDelete(int fno, char *id);
SD_API void SDDeleteu(int fno, char *id);
SD_API void SDDisconnect(void);
SD_API void SDDisconnectAll(void);
SD_API void SDEndCommand(void);
SD_API int16_t SDEnterPackage(char *name);
SD_API char *SDError(void);
SD_API char *SDExecute(char *command, int *err);
SD_API int16_t SDExitPackage(char *name);
SD_API char *SDExtract(char *src, int fno, int vno, int svno);
SD_API char *SDField(char *src, char *delim, int first, int occurrences);
SD_API void SDFree(void *p);
SD_API int SDGetSession(void);
SD_API char *SDIns(char *src, int fno, int vno, int svno, char *new_string);
SD_API int SDLocate(char *item, char *src, int fno, int vno, int svno, int *pos, char *order);
SD_API int SDLogto(char *account_name);
SD_API void SDMarkMapping(int16_t fno, int16_t state);
SD_API int SDMatch(char *str, char *pattern);
SD_API char *SDMatchfield(char *str, char *pattern, int component);
SD_API int SDOpen(char *filename);
SD_API char *SDRead(int fno, char *id, int *err);
SD_API char *SDReadl(int fno, char *id, int wait, int *err);
SD_API char *SDReadList(int listno);
SD_API char *SDReadNext(int16_t listno);
SD_API char *SDReadu(int fno, char *id, int wait, int *err);
SD_API void SDRecordlock(int fno, char *id, int update_lock, int wait);
SD_API void SDRelease(int fno, char *id);
SD_API char *SDReplace(char *src, int fno, int vno, int svno, char *new_string);
SD_API char *SDRespond(char *response, int *err);
SD_API void SDSelect(int fno, int listno);
SD_API void SDSelectIndex(int16_t fno, char *index_name, char *index_value, int16_t listno);
SD_API char *SDSelectLeft(int16_t fno, char *index_name, int16_t listno);
SD_API char *SDSelectRight(int16_t fno, char *index_name, int16_t listno);
SD_API void SDSetLeft(int16_t fno, char *index_name);
SD_API void SDSetRight(int16_t fno, char *index_name);
SD_API int SDSetSession(int session);
SD_API int SDStatus(void);
SD_API void SDWrite(int fno, char *id, char *data);
SD_API void SDWriteu(int fno, char *id, char *data);

#define SV_OK       0
#define SV_ON_ERROR 1
#define SV_ELSE     2
#define SV_ERROR    3
#define SV_LOCKED   4
#define SV_PROMPT   5
/* 15 Aug 26 Windows port - THESE TWO CONFLICT WITH sdb64 AND THE NUMBERING IS
   NOT SETTLED.  sdb64's dev branch (1.0-3, 19 Jul 2026) defines the same two
   names the other way round: EMSG_PAIR=6, ECONTXT=7.  Left as winsdclilib has
   them, because this directory is a vendored copy and must stay faithful to
   its source (VENDORING.md) - NOT because this numbering is known to be
   right.  Which came first cannot be determined from this repository: the
   imported snapshot b6624565 is dated 5 Aug 2026, after their 19 Jul commit,
   but that is the snapshot date and not when the constants were written.
   DO NOT "align" either side without settling it - see UPSTREAM_FIXES.md.  */
#define SV_ECONTXT   6
#define SV_EMSG_PAIR 7

#ifdef __cplusplus
}
#endif

#endif
