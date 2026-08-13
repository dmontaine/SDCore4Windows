/* PCODE.H
 * Pcode definitions.
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
 * 15 Jun 24 mab - remove banner, login, pickmsg, ttyset, ttyget from pcode
 * END-HISTORY
 *
 * START-DESCRIPTION:
 *
 * END-DESCRIPTION
 *
 * START-CODE
 */

Pcode(ak)        /* AK(MODE, MAT AK.DATA, ID, OLD.REC, NEW.REC) */
Pcode(bindkey)   /* BINDKEY(STRING, ACTION) */
Pcode(break)     /* BREAK() */
Pcode(cconv)     /* CCONV(SRC, CONV) */
Pcode(chain)     /* CHAIN() */
Pcode(data)      /* DATA(STRING) */
Pcode(dellist)   /* DELLIST(NAME) */
Pcode(extendlist) /* EXTENDLIST(ITEMS, LIST.NO) */
Pcode(fold)      /* FOLD(STRING, WIDTH) */
Pcode(formcsv)   /* FORMCSV(STR) */
Pcode(formlst)   /* FORMLIST(SRC, LIST.NO) */
Pcode(getlist)   /* DELLIST(NAME, LIST.NO) */
Pcode(getmsg)    /* GETMSG() */
Pcode(hf)        /* HF(PU, PGNO, HF.IN) */
Pcode(iconv)     /* ICONV(SRC, CONV) */
Pcode(in)        /* IN(TIMEOUT) */
Pcode(indices)   /* INDICES(MAT AK.DATA, AKNO) */
Pcode(input)     /* INPUT(STRING, MAX.LENGTH, FLAGS) */
Pcode(inputat)   /* INPUTAT(X, Y, STRING, MAX.LENGTH, MASK, FLAGS) */
Pcode(itype)     /* ITYPE(DICT.REC) */
Pcode(keycode)   /* KEYCODE(TIMEOUT) */
Pcode(keyedit)   /* KEYEDIT(KEY.CODE, KEY.STRING) */
Pcode(maximum)   /* MAXIMUM(DYN.ARRAY) */
Pcode(message)   /* MESSAGE() */
Pcode(minimum)   /* MINIMUM(DYN.ARRAY) */
Pcode(msgargs)   /* MSGARGS(TEXT,ARG1,ARG2,ARG3,ARG4) */
Pcode(nextptr)   /* NEXTPTR() */
Pcode(oconv)     /* OCONV(SRC, CONV) */
Pcode(ojoin)     /* OJOIN(FILE.NAME, INDEX.NAME, INDEXED.VALUE) */
Pcode(overlay)   /* OVERLAY(PU) */
Pcode(pclstart)  /* PCL.START(PU) */
Pcode(prefix)    /* PREFIX(UNIT, PATHNAME) */
Pcode(prfile)    /* PRFILE(FILE, RECORD, PATHNAME, STATUS.CODE) */
Pcode(readlst)   /* READLIST(TGT, LIST.NO, STATUS.CODE) */
Pcode(readv)     /* READV(TGT, FILE, ID, FIELD.NO, LOCK) */
Pcode(repadd)    /* REPADD(DYN.ARRAY, F, V, S, VAL) */
Pcode(repcat)    /* REPCAT(DYN.ARRAY, F, V, S, VAL) */
Pcode(repdiv)    /* REPDIV(DYN.ARRAY, F, V, S, VAL) */
Pcode(repmul)    /* REPMUL(DYN.ARRAY, F, V, S, VAL) */
Pcode(repsub)    /* REPSUB(DYN.ARRAY, F, V, S, VAL) */
Pcode(repsubst)  /* REPSUBST(DYN.ARRAY, F, V, S, P, Q, VAL) */
Pcode(savelst)   /* SAVELIST(NAME, LIST.NO) */
Pcode(sselct)    /* SSELECT(FVAR, LIST.NO) */
Pcode(subst)     /* SUBSTITUTE(STR, OLD.LIST, NEW.LIST, DELIMITER) */
Pcode(substrn)   /* SUBSTRNG(STR, START, LENGTH) */
Pcode(sum)       /* SUM(STR) */
Pcode(sumall)    /* SUMMATION(STR) */
Pcode(system)    /* SYSTEM(ARG) */
Pcode(tconv)     /* TCONV(SRC, CONV, OCONV) */
Pcode(trans)     /* TRANS(FILE.NAME, ID.LIST, FIELD.NO, CODE) */
Pcode(voc_cat)   /* VOC.CAT(VOC.ID, PATHNAME) */
Pcode(voc_ref)   /* VOC.REF(VOC.ID, FIELD.NO, RESULT) */
Pcode(writev)    /* WRITEV(STRING, FILE, ID, FIELD.NO, LOCK) */

/* END-CODE */
