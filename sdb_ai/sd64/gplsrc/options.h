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
#define OptDebugRebindKeys   19   /* reserved: it rebound AccuTerm keys; no code uses it (13 Oct 26) */
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
#define OptPickMLConvMask    42   /* 14 Oct 26  openQM ref 49: read by masked_decimal_conversion() in op_oconv.c */
#define OptChainedSelect     43   /* 14 Oct 26  openQM refs 79, 314: read by BASIC only (gpl.bp/cproc) */
#define OptPaginateOnHeading 44   /* openQM ref 154: read by hf_paginate() in op_tio.c */
#define OptForceReload       45   /* 14 Oct 26  openQM ref 37: read by process_events() in kernel.c; the CALL ops refresh a stale link */
#define OptNumericExponent   46   /* 14 Oct 26  openQM ref 404: read by k_str_to_num() and k_is_num() in k_funcs.c */
#define OptQueryFooterPause  47   /* 14 Oct 26  openQM ref 429: read by BASIC only (gpl.bp/qdisp) */
#define OptInheritMFilePath  48   /* 14 Oct 26  openQM ref 461: read by BASIC only (gpl.bp/createf) */
#define OptGit               49   /* 15 Oct 26  Q-17, the QM4 gaps: .gitignore and .gitattributes are not mapped in a directory file (map_t1_id() in op_dio3.c) */
#define OptDirDtm            50   /*            a write to a directory file moves the directory's date and time modified (dir_write() in op_dio3.c) */
#define OptKeepOldObject     51   /*            a failed compilation leaves the previous object code (BASIC, gpl.bp/basic or bcomp) */
#define OptNoPhantomNotify   52   /*            a phantom does not send its parent the message when it ends (BASIC, cproc) */
#define OptSpoolCommand      53   /*            show the operating system command that prints (kernel, the print start) */
#define OptAssocAll          54   /*            the query processor treats all fields as one association (BASIC, qproc) */
#define OptCorrelativeNoCase 55   /*            string operations in a correlative or I-type are case blind: HDR_NOCASE is set when its object is started (kernel.c) */
#define OptCorrelativeReuse  56   /*            every operand of an array operation in a correlative or I-type is read as if it had REUSE() (ReuseFlag below) */
#define OptQueryMergePrint   57   /* 15 Oct 26  openQM ref 57: a query to printer 0 leaves an already active printer on (BASIC, gpl.bp/qdisp) */
#define OptCommandLevelLocks 58   /* 16 Oct 26  openQM refs 231 / 428: a file variable that goes keeps its locks until the program returns to the command processor (park_fvar() in op_lock.c) */
#define OptStackedAccount    59   /* 16 Oct 26  openQM ref 248: an EXECUTE that changes account reverts to the account it started in (BASIC, gpl.bp/cproc) */
#define OptInheritOwnership  60   /* 16 Oct 26  openQM ref 239: CREATE.FILE gives a new file the account directory's owner and group (inherit_ownership_of() in op_dio1.c) */
#define NumOptions           61

Public char option_flags[NumOptions];

#define Option(opt) (option_flags[(opt)])
#define SetOption(opt, val) option_flags[(opt)] = (val);

/* The REUSE flag of an operand of an array operation (DF_REUSE, or 0): the descriptor's own, or, in a correlative or I-type with
   CORRELATIVE.REUSE on, always.  The option is read when the correlative runs, not when it was compiled. */
#define ReuseFlag(d) \
  (((d)->flags & DF_REUSE) | ((((process.program.flags & HDR_ITYPE) != 0) && Option(OptCorrelativeReuse)) ? DF_REUSE : 0))

/* END-CODE */
