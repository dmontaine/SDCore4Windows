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
 * 28 Oct 26 dm  S.87: four more option numbers retired: 18, 41, 46, 52.
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

#define OptQueryDebug         1
/* 27 Oct 26: the options marked REMOVE in the owner's emulation survey are gone.  Their numbers stay RESERVED (the later options keep theirs, and the option
   flags travel as a string in a phantom's cargo); 2, 3, 4, 5, 9, 10, 14, 15, 16, 17, 19, 20, 23, 24, 25, 27, 28, 29, 30, 31, 32 and 33 are retired:
   PickWildcard, QualDisplay, PickBreakpoint, WithImpliesOr, AssocUnassocMV, PickBreakpointU, CRDBUpcase, AMPMUpcase, PickNull, PickGrandTotal,
   DebugRebindKeys, EDNoQueryFD, SelectKeepCase, CreateFileCase, PickExplode, QueryNoCase, LockBeep, PickImpliedEQ, QueryPriorityAnd, NoDateWrapping,
   ProcA and SpaceMCT.  gpl.bp/option holds a blank row for each, in this order. */
/* 27 Oct 26 (S.87 batch 7): 12, 34, 35, 38, 42, 43, 44, 47, 51, 54 and 57 are retired too: RunNoPage, QueryStringComp, QueryStrCompAll, DefaultMV, PickMLConvMask, ChainedSelect,
   PaginateOnHeading, QueryFooterPause, KeepOldObject, AssocAll and QueryMergePrint.  Blank rows again.
   Batch 8: 21, 40, 48 and 55 as well: NoSelListQuery, CatalogueLocal, InheritMFilePath and CorrelativeNoCase.
   Batch 12: 22, 37 and 56: ChainKeepCommon, BackslashNotQuote and CorrelativeReuse.
   Batch 16: 0, 7, 8, 26, 36 and 39: UnassignedWarning, DivZeroWarning, NonNumericWarning, Inherit, QuerySortNoCase and ClearSelect.
   28 Oct 26 (S.87, the 83 open entries): 46 NumericExponent, 18 SuppressAbortMsg, 41 DirSelOmitHidden, 52 NoPhantomNotify, 45 ForceReload, 59 StackedAccount, 58 CommandLevelLocks. */
#define OptDumpOnError        6
#define OptNoUserAborts      11
#define OptShowStackOnError  13
#define OptGit               49   /* 15 Oct 26  Q-17, the QM4 gaps: .gitignore and .gitattributes are not mapped in a directory file (map_t1_id() in op_dio3.c) */
#define OptDirDtm            50   /*            a write to a directory file moves the directory's date and time modified (dir_write() in op_dio3.c) */
#define OptSpoolCommand      53   /*            show the operating system command that prints (kernel, the print start) */
#define OptInheritOwnership  60   /* 16 Oct 26  openQM ref 239: CREATE.FILE gives a new file the account directory's owner and group (inherit_ownership_of() in op_dio1.c) */
#define NumOptions           61

Public char option_flags[NumOptions];

#define Option(opt) (option_flags[(opt)])
#define SetOption(opt, val) option_flags[(opt)] = (val);

/* The REUSE flag of an operand of an array operation (DF_REUSE, or 0): the descriptor's own.  (OPTION CORRELATIVE.REUSE, which made it
   always set in a correlative or I-type, was removed on 27 Oct 26: S.87 batch 12.) */
#define ReuseFlag(d) ((d)->flags & DF_REUSE)

/* END-CODE */
