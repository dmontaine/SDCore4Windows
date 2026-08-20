/* QMCLIENT.H
 * QMClient Server Interface.
 * Copyright (c) 2004 Ladybridge Systems, All Rights Reserved
 *
 * Modifications Copyright (c) 2026 Donald Montaine
 *
 * This library is free software: you can redistribute it and/or modify it
 * under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or (at
 * your option) any later version.
 *
 * This library is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU Lesser
 * General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this library.  If not, see <https://www.gnu.org/licenses/>.
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
 * 
 * 
 * 
 * START-HISTORY (SD):
 * 
 * START-HISTORY (OpenQM):
 * 01 Jul 07  2.5-7 Extensive change for PDA merge.
 * 16 Sep 04  2.0-1 OpenQM launch. Earlier history details suppressed.
 * END-HISTORY
 *
 * START-DESCRIPTION:
 *
 * END-DESCRIPTION
 *
 * START-CODE
 */

/* Server commands */

#define SrvrQuit          1    /* Disconnect */
#define SrvrGetError      2    /* Get extended error text */
#define SrvrAccount       3    /* Set account */
#define SrvrOpen          4    /* Open file */
#define SrvrClose         5    /* Close file */
#define SrvrRead          6    /* Read record */
#define SrvrReadl         7    /* Read record with shared lock */
#define SrvrReadlw        8    /* Read record with shared lock, waiting */
#define SrvrReadu         9    /* Read record with exclusive lock */
#define SrvrReaduw       10    /* Read record with exclusive lock, waiting */
#define SrvrSelect       11    /* Select file */
#define SrvrReadNext     12    /* Read next id from select list */
#define SrvrClearSelect  13    /* Clear select list */
#define SrvrReadList     14    /* Read a select list */
#define SrvrRelease      15    /* Release lock */
#define SrvrWrite        16    /* Write record */
#define SrvrWriteu       17    /* Write record, retaining lock */
#define SrvrDelete       18    /* Delete record */
#define SrvrDeleteu      19    /* Delete record, retaining lock */
#define SrvrCall         20    /* Call catalogued subroutine */
#define SrvrExecute      21    /* Execute command */
#define SrvrRespond      22    /* Respond to request for input */
#define SrvrEndCommand   23    /* Abort command */
#define SrvrLogin        24    /* Network login */
#define SrvrLocalLogin   25    /* QMLocal login */
#define SrvrSelectIndex  26    /* Select index */
#define SrvrEnterPackage 27    /* Enter a licensed package */
#define SrvrExitPackage  28    /* Exit from a licensed package */
#define SrvrOpenQMNet    29    /* Open QMNet file */
#define SrvrLockRecord   30    /* Lock a record */
#define SrvrClearfile    31    /* Clear file */
#define SrvrFilelock     32    /* Get file lock */
#define SrvrFileunlock   33    /* Release file lock */
#define SrvrRecordlocked 34    /* Test lock */
#define SrvrIndices1     35    /* Fetch information about indices */
#define SrvrIndices2     36    /* Fetch information about specific index */
#define SrvrSelectList   37    /* Select file and return list */
#define SrvrSelectIndexv 38    /* Select index, returning indexed values */
#define SrvrSelectIndexk 39    /* Select index, returning keys for indexed value */
#define SrvrFileinfo     40    /* FILEINFO() */
#define SrvrReadv        41    /* READV and variants */
#define SrvrSetLeft      42    /* Align index position to left */
#define SrvrSetRight     43    /* Align index position to right */
#define SrvrSelectLeft   44    /* Move index position to left */
#define SrvrSelectRight  45    /* Move index position to right */
#define SrvrMarkMapping  46    /* Enable/disable mark mapping */
/* 19 Aug 26 Windows port - SCRAM-SHA-256 login, docs/SCRAM_AUTH.md phase 3/4.
   The two halves of one exchange; both bodies are the SCRAM message itself,
   with no length prefixes and no padding, because the packet already carries
   its own length.  APISRVR's dispatch table is the other half of this pair. */
#define SrvrScramFirst   47    /* SCRAM client-first  -> server-first */
#define SrvrScramFinal   48    /* SCRAM client-final  -> server-final */

/* Server error status values */
#define SV_OK             0    /* Action successful                       */
#define SV_ON_ERROR       1    /* Action took ON ERROR clause             */
#define SV_ELSE           2    /* Action took ELSE clause                 */
#define SV_ERROR          3    /* Action failed. Error text available     */
#define SV_LOCKED         4    /* Action took LOCKED clause               */
#define SV_PROMPT         5    /* Server requesting input                 */
/* 15 Aug 26 Windows port - TRANSPOSED AGAINST sdb64 AND FIXED HERE.
   winsdclilib commit 13e4bf5 (5 Aug 2026), "Align Windows client error
   handling with Linux", introduced these as ECONTXT=6/EMSG_PAIR=7 - the
   opposite of the sdb64 dev commit d0647b9 it was aligning TO, which had
   defined EMSG_PAIR=6/ECONTXT=7 seventeen days earlier.  sdb64's values
   came first and are the shared ones.
   19 Aug 26 - winsdclilib fixed it independently in a1987b0, and now takes
   this file wholesale, so the debt this note used to record is paid and the
   three copies agree.                                                    */
#define SV_EMSG_PAIR      6    /* Client request/response transport failed */
#define SV_ECONTXT        7    /* Client called function in wrong context */

/* END-CODE */
