'' sdclilib.bi - public FreeBASIC API for the sdclilib ScarletDME client library.
''
'' Distributed under the GNU Lesser General Public License, version 3 or
'' later (LGPL-3.0-or-later). See LICENSE and GPLv3.txt for the full terms.
''
'' Linking exception:
''
'' As a special exception, the copyright holders of this library give you
'' permission to link this library with independent modules to produce an
'' executable, regardless of the license terms of these independent modules,
'' and to copy and distribute the resulting executable under terms of your
'' choice, provided that you also meet, for each linked independent module,
'' the terms and conditions of the license of that module. An independent
'' module is a module which is not derived from or based on this library. If
'' you modify this library, you may extend this exception to your version of
'' the library, but you are not obligated to do so. If you do not wish to do
'' so, delete this exception statement from your version.

#ifndef __SDCLILIB_BI__
#define __SDCLILIB_BI__

#inclib "sdclilib"

#define SV_OK       0
#define SV_ON_ERROR 1
#define SV_ELSE     2
#define SV_ERROR    3
#define SV_LOCKED   4
#define SV_PROMPT   5
/* 15 Aug 26 Windows port - TRANSPOSED AGAINST sdb64 AND FIXED HERE.
   winsdclilib commit 13e4bf5 (5 Aug 2026), "Align Windows client error
   handling with Linux", introduced these as ECONTXT=6/EMSG_PAIR=7 - the
   opposite of the sdb64 dev commit d0647b9 it was aligning TO, which had
   defined EMSG_PAIR=6/ECONTXT=7 seventeen days earlier.  sdb64's values
   came first and are the shared ones.  The same fix is owed to
   winsdclilib itself - PROJECT_STATUS.md 5.3.                          */
#define SV_EMSG_PAIR 6
#define SV_ECONTXT   7

extern "C"
    declare sub SDCall cdecl (byval subrname as zstring ptr, byval argc as short, ...)
    declare sub SDCallx cdecl (byval subrname as zstring ptr, byval argc as short, ...)
    declare function SDGetArg (byval arg_number as long) as zstring ptr
    declare function SDChange (byval src as zstring ptr, byval old_string as zstring ptr, byval new_string as zstring ptr, byval occurrences as long, byval start as long) as zstring ptr
    declare sub SDClearSelect (byval listno as long)
    declare sub SDClose (byval fno as long)
    declare function SDConnect (byval host as zstring ptr, byval port as long, byval username as zstring ptr, byval password as zstring ptr, byval account as zstring ptr) as long
    declare function SDConnected () as long
    declare function SDDcount (byval src as zstring ptr, byval delim as zstring ptr) as long
    declare sub SDDebug (byval mode as short)
    declare function SDDel (byval src as zstring ptr, byval fno as long, byval vno as long, byval svno as long) as zstring ptr
    declare sub SDDelete (byval fno as long, byval id as zstring ptr)
    declare sub SDDeleteu (byval fno as long, byval id as zstring ptr)
    declare sub SDDisconnect ()
    declare sub SDDisconnectAll ()
    declare sub SDEndCommand ()
    declare function SDEnterPackage (byval name_ as zstring ptr) as short
    declare function SDError () as zstring ptr
    declare function SDExecute (byval command as zstring ptr, byref err as long) as zstring ptr
    declare function SDExitPackage (byval name_ as zstring ptr) as short
    declare function SDExtract (byval src as zstring ptr, byval fno as long, byval vno as long, byval svno as long) as zstring ptr
    declare function SDField (byval src as zstring ptr, byval delim as zstring ptr, byval first as long, byval occurrences as long) as zstring ptr
    declare sub SDFree (byval p as any ptr)
    declare function SDGetSession () as long
    declare function SDIns (byval src as zstring ptr, byval fno as long, byval vno as long, byval svno as long, byval new_string as zstring ptr) as zstring ptr
    declare function SDLocate (byval item as zstring ptr, byval src as zstring ptr, byval fno as long, byval vno as long, byval svno as long, byref pos as long, byval order_ as zstring ptr) as long
    declare function SDLogto (byval account_name as zstring ptr) as long
    declare sub SDMarkMapping (byval fno as short, byval state as short)
    declare function SDMatch (byval str_ as zstring ptr, byval pattern as zstring ptr) as long
    declare function SDMatchfield (byval str_ as zstring ptr, byval pattern as zstring ptr, byval component as long) as zstring ptr
    declare function SDOpen (byval filename as zstring ptr) as long
    declare function SDRead (byval fno as long, byval id as zstring ptr, byref err as long) as zstring ptr
    declare function SDReadl (byval fno as long, byval id as zstring ptr, byval wait_ as long, byref err as long) as zstring ptr
    declare function SDReadList (byval listno as long) as zstring ptr
    declare function SDReadNext (byval listno as short) as zstring ptr
    declare function SDReadu (byval fno as long, byval id as zstring ptr, byval wait_ as long, byref err as long) as zstring ptr
    declare sub SDRecordlock (byval fno as long, byval id as zstring ptr, byval update_lock as long, byval wait_ as long)
    declare sub SDRelease (byval fno as long, byval id as zstring ptr)
    declare function SDReplace (byval src as zstring ptr, byval fno as long, byval vno as long, byval svno as long, byval new_string as zstring ptr) as zstring ptr
    declare function SDRespond (byval response as zstring ptr, byref err as long) as zstring ptr
    declare sub SDSelect (byval fno as long, byval listno as long)
    declare sub SDSelectIndex (byval fno as short, byval index_name as zstring ptr, byval index_value as zstring ptr, byval listno as short)
    declare function SDSelectLeft (byval fno as short, byval index_name as zstring ptr, byval listno as short) as zstring ptr
    declare function SDSelectRight (byval fno as short, byval index_name as zstring ptr, byval listno as short) as zstring ptr
    declare sub SDSetLeft (byval fno as short, byval index_name as zstring ptr)
    declare sub SDSetRight (byval fno as short, byval index_name as zstring ptr)
    declare function SDSetSession (byval session as long) as long
    declare function SDStatus () as long
    declare sub SDWrite (byval fno as long, byval id as zstring ptr, byval data_ as zstring ptr)
    declare sub SDWriteu (byval fno as long, byval id as zstring ptr, byval data_ as zstring ptr)
end extern

#endif
