/* OPTIONS.H
 * Option flags.
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
 * 31 Dec 23 SD Launch - Prior history suppressed
 * END-HISTORY
 *
 * START-DESCRIPTION:
 *
 * END-DESCRIPTION
 *
 * START-CODE
 */

/* Option flags
   All references are by macro so that the implementation can change to
   accommodate larger numbers of option flags.
   NOTE: This list is known by the BP OPTION program and BP INT$KEYS.H.   */

#define OptUnassignedWarning  0
#define OptQueryDebug         1
#define OptPickWildcard       2
#define OptQualDisplay        3
#define OptPickBreakpoint     4
#define OptWithImpliesOr      5
#define OptDumpOnError        6
#define OptDivZeroWarning     7
#define OptNonNumericWarning  8
#define OptAssocUnassocMV     9
#define OptPickBreakpointU   10
#define OptNoUserAborts      11
#define OptRunNoPage         12
#define OptShowStackOnError  13
#define OptCRDBUpcase        14
#define OptAMPMUpcase        15
#define OptPickNull          16
#define OptPickGrandTotal    17
#define OptSuppressAbortMsg  18
#define OptDebugRebindKeys   19
#define OptEDNoQueryFD       20
#define OptNoSelListQuery    21
#define OptChainKeepCommon   22
#define OptSelectKeepCase    23
#define OptCreateFileCase    24
#define OptPickExplode       25
#define OptInherit           26
#define OptQueryNoCase       27
#define OptLockBeep          28
#define OptPickImpliedEQ     29
#define OptQueryPriorityAnd  30
#define OptNoDateWrapping    31
#define OptProcA             32
#define OptSpaceMCT          33
#define OptQueryStringComp   34   /* 10 Oct 26  1.2-0 openQM refs 140, 299,  */
#define OptQueryStrCompAll   35   /*            412, 165, 205, 403: every    */
#define OptQuerySortNoCase   36   /*            new option is read by BASIC  */
#define OptBackslashNotQuote 37   /*            only (gpl.bp/qproc, parser,  */
#define OptDefaultMV         38   /*            cproc), so the C side only   */
#define OptClearSelect       39   /*            needs room for the flags.    */
#define OptCatalogueLocal    40   /* 12 Oct 26  openQM refs 288 and 445: CATALOGUE.LOCAL is read by BASIC (catalog,  */
#define OptDirSelOmitHidden  41   /*            delcat); DIR.SEL.OMIT.HIDDEN by dir_select() in op_dio4.c.       */
#define NumOptions           42

Public char option_flags[NumOptions];

#define Option(opt) (option_flags[(opt)])
#define SetOption(opt, val) option_flags[(opt)] = (val);

/* END-CODE */
