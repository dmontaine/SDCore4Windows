#!/usr/bin/env python3
#
# sandbox-q4.py - QM4 gaps, the 15 Oct 26 third sitting: BLOCK.PRINT / BLOCK.TERM, FILE.STAT, BSCAN / ROOT / KEY,
#                 SELECTLEFTV / SELECTRIGHTV, DISABLE.INDEX, SWAPMARKS, SYSTEM(1071), OPTION QUERY.MERGE.PRINT, PHANTOM GROUP
#                 (SYSTEM(1073), the G in LISTU), @PSTAT, SET.QUEUE / SP.ASSIGN and FSTAT.USER.  No install, no sudo.
#
#   python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/sandbox-q4.py <dir> [--build]
#
# <dir> is a sandbox made by sandbox-fromtree.py.  With --build it is built first from THIS tree (it must be empty or
# absent).  Exit 0 every row passed, 1 a row failed, 2 it could not run.
#
# START-HISTORY:
# 15 Oct 26 dm  Written for QM4 gaps bundle Q-8 (BLOCK.PRINT, BLOCK.TERM).
# END-HISTORY
#
# THE INSTRUMENT.  The sandbox, the sessions and the fixture account are those of sandbox-stmt-q3.py, which this file loads
# as a module and gives its own probes (its harness is the one place that knows how a fixture account is made).  The
# expected drawings are typed here as pictures, apart from the font table in gpl.bp/blockprt.
#
#   A  BLOCK.TERM and BLOCK.PRINT: the seven rows of a letter, the blank row, the width, wrapping at a space and by force,
#      lower case, the shapes and the question mark for what has none, no text, the printer's copy equal to the screen's
#   B  FILE.STAT against FILEINFO (modulus, sizes, record count), the flags, a directory file, a name, a select list, DICT
#   C  BSCAN, ROOT and KEY on an index of known values; D SELECTLEFTV / SELECTRIGHTV; E DISABLE.INDEX (updates, query, rebuild);
#   F  SWAPMARKS; G SYSTEM(1071) against STATUS; H QUERY.MERGE.PRINT read from the print job; I PHANTOM GROUP; J @PSTAT;
#   K  SET.QUEUE / SP.ASSIGN; L  FSTAT.USER

import importlib.util
import os
import re
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("q3", os.path.join(HERE, "sandbox-stmt-q3.py"))
q3 = importlib.util.module_from_spec(spec)
spec.loader.exec_module(q3)
say, row, has, tag, put = q3.say, q3.row, q3.has, q3.tag, q3.put

USER_PROGS = {
    # A: BLOCK.PRINT to a print unit that is a file: SETPTR 0 to a pathname is gated, so the copy goes through the spooler
    # hold file ($HOLD) with the unit set to hold mode 3
    "zzbp1": ("   execute 'SETPTR 0,80,60,0,0,3,AS zzbpjob,BRIEF' capturing j\n"
              "   execute 'BLOCK.PRINT HI' capturing j2\n"
              "   crt 'CAPT[':len(j2):']'\n"
              "   open '$hold' to h else stop 'no hold'\n"
              "   read r from h, 'zzbpjob' else r = ''\n"
              "   for i = 1 to dcount(r, @fm)\n      crt 'HL[':r<i>:']'\n   next i\n"
              "   crt 'BPDONE'\nend\n"),
    # B: FILE.STAT.  zzfsmk fills two files; zzfsi says what FILEINFO() gives for each (the oracle for the columns)
    "zzfsmk": ("   open 'zzfs1' to f1 else stop 'no zzfs1'\n   open 'zzfs2' to f2 else stop 'no zzfs2'\n"
               "   for i = 1 to 40\n      write str('x', 200) on f1, 'r':i\n   next i\n"
               "   open 'DICT zzfs3' to d3 else stop 'no dict'\n"
               "   write 'D':@fm:'1':@fm:'':@fm:'City':@fm:'12L':@fm:'S' on d3, 'CITY'\n"
               "   write 'one' on f2, 'a'\n   write 'two' on f2, 'b'\n   write 'three' on f2, 'c'\nend\n"),
    "zzfsi": ("$include keys.h\n"
              "   names = 'zzfs1':@fm:'zzfs3'\n"
              "   for n = 1 to 2\n      open names<n> to f else stop 'no file'\n"
              "      crt 'FI':n:'[':fileinfo(f, FL$MODULUS):'][':fileinfo(f, FL$MINMOD):'][':fileinfo(f, FL$GRPSIZE):'][':"
              "fileinfo(f, FL$RECORD.COUNT):'][':fileinfo(f, FL$PRI.BYTES):'][':fileinfo(f, FL$OVF.BYTES):'][':fileinfo(f, FL$AK):']'\n"
              "   next n\n   crt 'FIDONE'\nend\n"),
    "zzfsl": "   formlist 'zzfs2' to 0\nend\n",
    # C: BSCAN, ROOT and KEY on file zzaix: ten records, the city Paris in r1 to r5, Rome in r6 to r8, Oslo in r9, Lima in r10
    "zzaisu": ("   open 'zzaix' to f else stop 'no file'\n   open 'DICT zzaix' to d else stop 'no dict'\n"
               "   write 'D':@fm:'1':@fm:'':@fm:'City':@fm:'12L':@fm:'S' on d, 'CITY'\n"
               "   cities = 'Paris':@fm:'Paris':@fm:'Paris':@fm:'Paris':@fm:'Paris':@fm:'Rome':@fm:'Rome':@fm:'Rome':@fm:'Oslo':@fm:'Lima'\n"
               "   for i = 1 to 10\n      write cities<i> on f, 'r':i\n   next i\nend\n"),
    "zzbs1": ("   open 'zzaix' to f else stop 'no file'\n"
              "   bscan v, ids from f using 'CITY' reset then crt 'AF[':v:'][':change(ids, @fm, ','):'][':status():']' else crt 'AF ELSE'\n"
              "   n = 0\n"
              "   loop\n      bscan v, ids from f using 'CITY' then crt 'A[':v:'][':change(ids, @fm, ','):'][':status():']' else exit\n"
              "      n += 1\n   until n > 20\n   repeat\n"
              "   crt 'AEND[':v:'][':ids:'][':status():']'\n"
              "   bscan v, ids from f using 'CITY' reset by d then crt 'D1[':v:']'\n"
              "   loop\n      bscan v from f using 'CITY' by d then crt 'D[':v:'][':status():']' else exit\n"
              "      n += 1\n   until n > 40\n   repeat\n"
              "   crt 'DEND[':v:'][':status():']'\n"
              "   bscan v, ids from f, 'Paris' using 'CITY' then crt 'V1[':v:'][':dcount(ids, @fm):'][':status():']' else crt 'V1 ELSE'\n"
              "   bscan v, ids from f, 'Q' using 'CITY' then crt 'V2 THEN' else crt 'V2[':v:'][':change(ids, @fm, ','):'][':status():']'\n"
              "   bscan v, ids from f, 'Pa' using 'CITY' by d then crt 'V3 THEN' else crt 'V3[':v:'][':status():']'\n"
              "   bscan v, ids from f, 'Rome' using 'CITY' then crt 'V4[':v:']' else crt 'V4 ELSE'\n"
              "   bscan v, ids from f using 'CITY' then crt 'V5[':v:']' else crt 'V5 ELSE'\n"
              "   bscan v, ids from f using 'NOPE' then crt 'E1 THEN' else crt 'E1[':status():']'\n"
              "   bscan v, ids from f using 'CITY' reset by 'X' then crt 'E2 THEN' else crt 'E2[':status():']'\n"
              "   open 'zzfs2' to g else stop 'no zzfs2'\n"
              "   bscan v, ids from g using 'CITY' then crt 'E3 THEN' else crt 'E3[':status():']'\n"
              "   crt 'BSDONE'\nend\n"),
    "zzky1": ("   root 'zzaix', 'CITY' to idx then crt 'ROOT[':status():']' else crt 'ROOT ELSE'\n"
              "   v = '' ; id = ''\n   n = 0\n   seq = ''\n"
              "   loop\n      key('N', idx, v, id) then seq<-1> = v:'/':id else exit\n      n += 1\n   until n > 30\n   repeat\n"
              "   crt 'NSEQ[':change(seq, @fm, ' '):']'\n   crt 'NEND[':status():'][':v:'][':id:']'\n"
              "   v = '' ; id = ''\n   seq = ''\n   key('L', idx, v, id) then crt 'L[':v:'][':id:']' else crt 'L ELSE'\n"
              "   n = 0\n"
              "   loop\n      seq<-1> = v:'/':id\n      key('P', idx, v, id) then null else exit\n      n += 1\n   until n > 30\n   repeat\n"
              "   crt 'PSEQ[':change(seq, @fm, ' '):']'\n   crt 'PEND[':status():']'\n"
              "   v = 'Pa' ; id = ''\n   key('C', idx, v, id) then crt 'C1[':v:'][':id:']' else crt 'C1 ELSE'\n"
              "   v = 'Paris' ; id = ''\n   key('C', idx, v, id) then crt 'C2[':v:'][':id:']' else crt 'C2 ELSE'\n"
              "   v = 'Z' ; id = ''\n   key('C', idx, v, id) then crt 'C3 THEN' else crt 'C3[':status():']'\n"
              "   v = 'Rome' ; id = ''\n   key('R', idx, v, id) then crt 'R1[':v:'][':id:']' else crt 'R1 ELSE'\n"
              "   v = 'Nowhere' ; id = ''\n   key('R', idx, v, id) then crt 'R2 THEN' else crt 'R2[':status():']'\n"
              "   v = 'Paris' ; id = 'r2'\n   key('V', idx, v, id) then crt 'V1 THEN' else crt 'V1 ELSE'\n"
              "   v = 'Paris' ; id = 'r9'\n   key('V', idx, v, id) then crt 'V2 THEN' else crt 'V2 ELSE[':status():']'\n"
              "   v = 'Paris' ; id = ''\n   key('X', idx, v, id) then crt 'X[':dcount(id, @fm):'][':change(id, @fm, ','):']' else crt 'X ELSE'\n"
              "   v = 'Rome' ; id = ''\n   key 'r', idx, v, id then crt 'LC[':id:']' else crt 'LC ELSE'\n"
              "   v = 'Rome' ; id = ''\n   key('Q', idx, v, id) then crt 'Q THEN' else crt 'Q[':status():']'\n"
              "   root 'zzaix', 'NOPE' to idx2 then crt 'RT2 THEN' else crt 'RT2[':status():']'\n"
              "   root 'nofile', 'CITY' to idx3 then crt 'RT3 THEN' else crt 'RT3[':(status() # 0):']'\n"
              "   crt 'KYDONE'\nend\n"),
    # D: SELECTLEFTV and SELECTRIGHTV on file zzaix of part C
    "zzlr1": ("   open 'zzaix' to f else stop 'no file'\n"
              "   selectindex 'CITY', 'Paris' from f to 10\n   clearselect 10\n"
              "   n = 0\n"
              "   loop\n      selectleftv 'CITY' from f setting k to lv\n      st = status()\n      sel = @selected\n      ids = ''\n"
              "      loop\n         readnext x from lv else exit\n         ids<-1> = x\n      repeat\n"
              "      crt 'L[':k:'][':change(ids, @fm, ','):'][':st:'][':sel:']'\n      n += 1\n   until ids = '' or n > 6\n   repeat\n"
              "   setleft 'CITY' from f\n"
              "   n = 0\n"
              "   loop\n      selectrightv 'CITY' from f to lv\n      st = status()\n      ids = ''\n"
              "      loop\n         readnext x from lv else exit\n         ids<-1> = x\n      repeat\n"
              "      crt 'R[':dcount(ids, @fm):'][':st:']'\n      n += 1\n   until ids = '' or n > 6\n   repeat\n"
              "   selectrightv 'NOPE' from f setting k2 to lv2\n   crt 'BAD[':status():']'\n"
              # the controls: what the plain statements say at the end of the index and for an index the file has not
              "   selectright 'CITY' from f to 9\n   crt 'PLAINEND[':status():'][':@selected:']'\n"
              "   selectright 'NOPE' from f to 9\n   crt 'PLAINBAD[':status():']'\n"
              "   crt 'LRDONE'\nend\n"),
    # E: DISABLE.INDEX on file zzdix (the same ten records as zzaix: Paris r1-r5, Rome r6-r8, Oslo r9, Lima r10)
    "zzdisu": ("   open 'zzdix' to f else stop 'no file'\n   open 'DICT zzdix' to d else stop 'no dict'\n"
               "   write 'D':@fm:'1':@fm:'':@fm:'City':@fm:'12L':@fm:'S' on d, 'CITY'\n"
               "   cities = 'Paris':@fm:'Paris':@fm:'Paris':@fm:'Paris':@fm:'Paris':@fm:'Rome':@fm:'Rome':@fm:'Rome':@fm:'Oslo':@fm:'Lima'\n"
               "   for i = 1 to 10\n      write cities<i> on f, 'r':i\n   next i\nend\n"),
    # what the index says about itself, how many ids it has for the Paris, Rio, Kyiv and Nice, and how many records a query
    # that could use the index finds with CITY = Paris.  The first argument is a tag.
    "zzdist": ("$include keys.h\n"
               "   tag = field(@sentence, ' ', 4)\n"
               "   open 'zzdix' to f else stop 'no file'\n"
               "   info = indices(f, 'CITY')\n"
               "   crt tag:'[':(info<1,2> # ''):'][':(info<1,4> # ''):']'\n"
               "   cities = 'Paris':@fm:'Rio':@fm:'Kyiv':@fm:'Nice'\n   line = ''\n"
               "   for i = 1 to 4\n      selectindex 'CITY', cities<i> from f to 9\n      line<-1> = @selected\n   next i\n"
               "   clearselect 9\n"
               "   crt tag:'AK[':change(line, @fm, ','):']'\n"
               "   execute 'SELECT zzdix WITH CITY = \"Paris\"' capturing j\n   n = 0\n"
               "   loop\n      readnext x from 0 else exit\n      n += 1\n   repeat\n"
               "   crt tag:'QP[':n:']'\nend\n"),
    "zzdiw": ("   open 'zzdix' to f else stop 'no file'\n"
              "   write 'Rio' on f, 'r11'\n   write 'Kyiv' on f, 'r12'\n   write 'Nice' on f, 'r1'\nend\n"),
    "zzdiw1": ("   open 'zzdix' to f else stop 'no file'\n   write 'Rio' on f, 'r11'\nend\n"),
    "zzdiw2": ("   open 'zzdix' to f else stop 'no file'\n   write 'Kyiv' on f, 'r12'\n   write 'Nice' on f, 'r1'\nend\n"),
    "zzdix2": ("   open 'zzdix' to f else stop 'no file'\n"
               "   execute 'DISABLE.INDEX zzdix CITY' capturing out\n   crt 'HELD[':(index(out, 'exclusive access', 1) > 0):']'\n"
               "   info = indices(f, 'CITY')\n   crt 'HELDSTILL[':(info<1,4> # ''):']'\nend\n"),
    "zzswm": ("   a = 'x':@fm:'y':@vm:'z':@sm:'w':char(250):char(200):'end'\n"
              "   crt 'SWAP[':(swapmarks(a) = a):'][':len(swapmarks(a)):'][':len(a):']'\n"
              "   crt 'SWAPN[':swapmarks(12.5):'][':(swapmarks('') = ''):']'\n"
              "end\n"),
    # G: SYSTEM(1071) after OSREAD.  The file is made with OPENSEQ; the STATUS array of the same file, read from an open
    # file variable, is the oracle for the fields OSREAD should hand over
    "zzosr": ("   openseq 'zzosr.txt' to f else create f else stop 'cannot create'\n   weofseq f\n"
              "   writeseq 'twelve bytes' to f else null\n   closeseq f\n"
              "   crt 'BEFORE[':system(1071):']'\n"
              "   osread d from 'zzosr.txt' then crt 'READ[':len(d):']' else crt 'READ ELSE'\n"
              "   info = system(1071)\n"
              "   openseq 'zzosr.txt' readonly to g else stop 'no open'\n   status st from g then null else null\n   closeseq g\n"
              "   crt 'SAME[':(info<5> = st<5>):(info<6> = st<6>):(info<7> = st<7>):(info<8> = st<8>):(info<10> = st<10>):"
              "(info<15> = st<15>):(info<16> = st<16>):(info<20> = st<20>):(info<21> = st<21>):(info<35> = st<35>):']'\n"
              "   crt 'SIZE[':info<6>:'][':info<20>[len(info<20>) - 8, 9]:'][':info<1>:info<2>:info<4>:']'\n"
              "   osread d from 'nosuchfile.zz' then crt 'BADTHEN' else crt 'BAD[':system(1071):']'\n"
              "   osread d from 'zzosr.txt' then crt 'AGAIN[':(system(1071) # ''):']' else crt 'AGAIN ELSE'\n"
              "end\n"),
    # H: OPTION QUERY.MERGE.PRINT.  The report goes to a print unit held in $HOLD (SETPTR mode 3).  Case A: option off, printer
    # on before the report (control); B: option on, printer on before; C: option on, printer off before (control); D: option on
    # and then off again, printer on before (control).  What is seen is the job record in $HOLD: the program prints BEFOREMARK,
    # runs the report, prints AFTERMARK.  The report closes the print unit unless it merges, and a PRINT after a closed unit
    # starts another job with the same record id, which replaces the first; so a job that holds all three was never closed.
    # (SYSTEM(1) is not the test: closing the unit clears the printer flag only down to the command's own level, and the
    # program that said PRINTER ON is above it.)
    "zzmp": ("   c = field(@sentence, ' ', 4)\n"
             "   execute 'SETPTR 0,80,60,0,0,3,AS zzmp':c:',BRIEF' capturing j\n"
             "   if c = 'B' or c = 'C' or c = 'D' then execute 'OPTION QUERY.MERGE.PRINT' capturing j\n"
             "   if c = 'D' then execute 'OPTION QUERY.MERGE.PRINT OFF' capturing j\n"
             "   if c = 'C' then printer off else printer on\n"
             "   print 'BEFOREMARK'\n"
             "   execute 'LIST VOC WITH @ID = \"LIST\" LPTR' capturing j\n"
             "   print 'AFTERMARK'\n"
             "   printer off\n   printer close\n"
             "   open '$hold' to h else stop 'no hold'\n   read r from h, 'zzmp':c else r = ''\n"
             "   crt 'JOB[':c:'][':(index(r, 'BEFOREMARK', 1) > 0):(index(r, 'LIST', 1) > 0):(index(r, 'AFTERMARK', 1) > 0):']'\n"
             "end\n"),
    # I: PHANTOM GROUP.  One grouped and one plain phantom, each sleeping for a minute; what SYSTEM(1058) and SYSTEM(1073) say,
    # what LISTU shows, then the session ends and the next session looks for them
    "zzgp1": ("   execute 'PHANTOM NO.MSG GROUP SLEEP 60' capturing j\n   g = @system.return.code\n"
              "   execute 'PHANTOM NO.MSG SLEEP 60' capturing j\n   p = @system.return.code\n"
              "   crt 'GRP[':g:']'\n   crt 'PLN[':p:']'\n"
              # a phantom is counted as a child only once it has started (its own flag), so wait for both
              "   t = 0\n   loop\n      t += 1\n   until system(1052) >= 2 or t > 100\n      nap 100\n   repeat\n"
              "   crt 'KIDS[':change(system(1058), @fm, ','):'][':system(1052):'][':change(system(1073), @fm, ','):']'\n"
              "   execute 'LISTU' capturing lu\n"
              "   for i = 1 to dcount(lu, @fm)\n      crt 'LU[':lu<i>:']'\n   next i\n"
              "   crt 'ME[':@userno:']'\n"
              "end\n"),
    # the parent that goes before its grouped phantom has started
    "zzgp2": ("   execute 'PHANTOM NO.MSG GROUP SLEEP 60' capturing j\n   crt 'GRP2[':@system.return.code:']'\nend\n"),
    # J: @PSTAT.  zzps sets it (a value mark in it must not break the line), zzps0 is the control that sets nothing; both then
    # wait so that PSTAT USER can ask them
    "zzps": ("   @pstat = 'app status 42 of 90':@vm:'then more':@fm:'and a field mark'\n   crt 'PS[':@userno:']'\n   sleep 25\n   crt 'PSDONE'\nend\n"),
    "zzps0": ("   crt 'PS0[':@userno:']'\n   sleep 25\n   crt 'PS0DONE'\nend\n"),
    "zzps1": ("   @pstat = 77\n   crt 'PS1[':@userno:']'\n   sleep 25\n   crt 'PS1DONE'\nend\n"),
    # K: SET.QUEUE and SP.ASSIGN.  zzfq says what the print units hold; zzfq2 prints a line through unit 0 and reads the hold record
    "zzfq": ("$include keys.h\n   u = field(@sentence, ' ', 4) + 0\n"
             "   crt 'U[':u:'][':getpu(PU$MODE, u):'][':getpu(PU$WIDTH, u):'][':getpu(PU$LENGTH, u):'][':getpu(PU$TOPMARGIN, u):'][':"
             "getpu(PU$BOTMARGIN, u):'][':getpu(PU$COPIES, u):'][':getpu(PU$FORM.QUEUE, u):'][':system(1066):']'\n"
             "end\n"),
    "zzfq2": ("   printer on\n   print 'form queue line'\n   printer close\n"
              "   open '$hold' to h else stop 'no hold'\n   read r from h, field(@sentence, ' ', 4) else r = ''\n"
              "   crt 'HOLD[':(index(r, 'form queue line', 1) > 0):']'\nend\n"),
    # L: FSTAT.USER.  zzfu does 100 writes, 50 reads and 7 deletes between two reports on itself and two on the idle session whose
    # user number is its argument; zzfui is that idle session
    "zzfu": ("   open 'zzfuf' to f else stop 'no file'\n   idle = field(@sentence, ' ', 4)\n"
             "   execute 'FSTAT.USER USER ':@userno capturing a1\n   execute 'FSTAT.USER USER ':idle capturing i1\n"
             "   for i = 1 to 100\n      write 'x' on f, 'k':i\n   next i\n"
             "   for i = 1 to 50\n      read r from f, 'k':i else null\n   next i\n"
             "   for i = 1 to 7\n      delete f, 'k':i\n   next i\n"
             "   execute 'FSTAT.USER USER ':@userno capturing a2\n   execute 'FSTAT.USER USER ':idle capturing i2\n"
             "   execute 'FSTAT.USER' capturing tbl\n   execute 'FSTAT.USER TOP' capturing top\n"
             "   for i = 1 to dcount(a1, @fm)\n      crt 'A1[':a1<i>:']'\n   next i\n"
             "   for i = 1 to dcount(a2, @fm)\n      crt 'A2[':a2<i>:']'\n   next i\n"
             "   for i = 1 to dcount(i1, @fm)\n      crt 'I1[':i1<i>:']'\n   next i\n"
             "   for i = 1 to dcount(i2, @fm)\n      crt 'I2[':i2<i>:']'\n   next i\n"
             "   for i = 1 to dcount(tbl, @fm)\n      crt 'TB[':tbl<i>:']'\n   next i\n"
             "   for i = 1 to dcount(top, @fm)\n      crt 'TP[':top<i>:']'\n   next i\n"
             "   crt 'ME[':@userno:']'\nend\n"),
    "zzfui": "   crt 'IDLE[':@userno:']'\n   sleep 40\n   crt 'IDLEDONE'\nend\n",
    # a matrix called KEY is still a matrix; a scalar called KEY is still a scalar
    "zzky2": ("   dim key(3)\n   key(1) = 'x'\n   key(2) = 'y'\n   crt 'M[':key(1):key(2):']'\n"
              "   crt 'KY2DONE'\nend\n"),
    "zzky3": ("   key = 'a'\n   key<2> = 'b'\n   crt 'S[':change(key, @fm, ','):']'\n   root = 5\n   bscan = 6\n   crt 'S2[':root + bscan:']'\n"
              "   crt 'KY3DONE'\nend\n"),
}

H = ["W   W", "W   W", "W   W", "WWWWW", "W   W", "W   W", "W   W"]
I = [" WWW ", "  W  ", "  W  ", "  W  ", "  W  ", "  W  ", " WWW "]


def drawn(chars):
    """The seven rows of the picture of CHARS: a blank column, five columns, a blank column and two of gap, as the manual's 7 x 7
    block with two spaces between characters, with the trailing spaces taken off."""
    return [("".join(" " + c[r] + "   " for c in chars)).rstrip() for r in range(7)]


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) != 1:
        q3.bail("usage: sandbox-q4.py <dir> [--build]")
    q3.BOX = os.path.abspath(args[0])
    q3.SYS = os.path.join(q3.BOX, "sys")
    q3.SD = os.path.join(q3.SYS, "bin", "sd")
    q3.USER_PROGS = USER_PROGS
    BOX, SYS, SD = q3.BOX, q3.SYS, q3.SD
    say("sandbox-q4: sandbox  %s" % BOX)
    if "--build" in sys.argv:
        if os.path.exists(BOX) and os.listdir(BOX):
            q3.bail("%s is not empty" % BOX)
        r = subprocess.run([sys.executable, q3.TOOL, BOX, "all"], capture_output=True, text=True, errors="replace", timeout=900)
        if "[FAIL]" in r.stdout or r.returncode != 0 or "[PASS] THIRD.COMPILE" not in r.stdout:
            q3.bail("the sandbox build did not pass:\n" + r.stdout[-800:])
        say("sandbox-q4: built, bootstrap passed")
    elif not os.path.isfile(SD):
        q3.bail("%s holds no built sandbox (use --build, or point it at one)" % BOX)
    subprocess.run([sys.executable, q3.TOOL, BOX, "start"], capture_output=True, text=True, errors="replace", timeout=120)

    say("\n--- preparation ------------------------------------------------------------------------------------------------")
    q3.prepare()
    q3.build_account("zzaa")
    for nm, text in USER_PROGS.items():
        put(os.path.join(SYS, "bp", nm), text)
    out = q3.adm(["BASIC bp " + " ".join(USER_PROGS)])
    if not has(out, r"^Compiled %d program\(s\) with no errors" % len(USER_PROGS)):
        q3.bail("the probes did not compile in SDSYS:\n" + "\n".join(out[-8:]))

    try:
        say("\n--- A. BLOCK.TERM / BLOCK.PRINT -------------------------------------------------------------------------------")
        out = q3.plain("zzaa", ["BLOCK.TERM HI"])
        want = drawn([H, I])
        # the screen rows: the command's echo is already removed by sd(); blank rows are dropped with it, so compare the
        # non-blank rows in order
        got = [ln for ln in out if ln.strip()]
        row("A1: BLOCK.TERM HI draws H and I in seven rows of W", got == want, repr(got))
        row("A1: the fourth row of the H is the bar: WWWWW", len(got) == 7 and got[3].startswith(" WWWWW"), repr(got[3:4]))
        row("A1: no row is wider than the 72 columns eight characters take", all(len(g) <= 72 for g in got), repr(max(got, key=len)))
        out = q3.plain("zzaa", ["BLOCK.TERM hi"])
        row("A2: lower case draws as upper case", [ln for ln in out if ln.strip()] == want, repr(out))
        out = q3.plain("zzaa", ["BLOCK.TERM"])
        row("A3: no text is refused with the message", has(out, r"^Text to print required$"), repr(out))
        out = q3.plain("zzaa", ["BLOCK.TERM ABCDEFGHIJKL"])
        got = [ln for ln in out if ln.strip()]
        row("A4: twelve letters wrap by force after eight: 14 non-blank rows", len(got) == 14, str(len(got)))
        out = q3.plain("zzaa", ["BLOCK.TERM AB CDEFGHIJ"])
        got = [ln for ln in out if ln.strip()]
        row("A5: 'AB CDEFGHIJ' breaks at the space: AB on the first line, CDEFGHIJ on the second (14 rows)", len(got) == 14,
            str(len(got)))
        row("A5: ... and the first line is narrower than the second", len(got) == 14 and max(map(len, got[:7])) < max(map(len, got[7:])),
            repr([max(map(len, got[:7])), max(map(len, got[7:]))]))
        out = q3.plain("zzaa", ["BLOCK.TERM A~"])
        got = [ln for ln in out if ln.strip()]
        qm = [" WWW ", "W   W", "    W", "   W ", "  W  ", "     ", "  W  "]
        row("A6: a character with no shape (~) draws as a question mark, after the A", len(got) == 7 and
            got == drawn([[" WWW ", "W   W", "W   W", "WWWWW", "W   W", "W   W", "W   W"], qm]),
            repr(got))
        out = q3.adm(["RUN bp zzbp1"])         # the fixture account has no $HOLD file; SDSYS has
        hl = [t.rstrip() for t in tag(out, "HL")]
        row("A7: BLOCK.PRINT to the printer: the spooled job holds the same seven rows as the screen", [t for t in hl if t] == want,
            repr(hl))
        row("A7: ... and the command printed nothing on the screen (captured output empty)", tag(out, "CAPT") == ["0"], repr(tag(out, "CAPT")))
        row("A7: CONTROL: the printed rows are not the screen's by accident: BLOCK.TERM sent none of them to the job",
            len([t for t in hl if t]) == 7, str(len(hl)))

        say("\n--- B. FILE.STAT ----------------------------------------------------------------------------------------------")
        q3.plain("zzaa", ["CREATE.FILE zzfs1 DYNAMIC", "CREATE.FILE zzfs2 DIRECTORY", "CREATE.FILE zzfs3 DYNAMIC MINIMUM.MODULUS 7",
                          ])
        q3.plain("zzaa", ["RUN bp zzfsmk", "CREATE.INDEX zzfs3 CITY"])
        fi = q3.plain("zzaa", ["RUN bp zzfsi"])
        out = q3.plain("zzaa", ["FILE.STAT"])
        lines = {}
        for ln in out:
            m = re.match(r"^(\S+)\s+(DYN|DIR|COL)\s", ln)
            if m:
                lines[m.group(1)] = ln
        row("B1: the report has the heading line", has(out, r"^File name\s+Typ\s+Cur Mod\s+Min Mod\s+Grp\s+Record Cnt\s+Primary\s+Overflow\s+Total Size AK TR ST NC NR EN RP JN$"),
            repr(out[:3]))
        row("B1: the three files are on it, zzfs1 and zzfs3 as DYN and zzfs2 as DIR",
            lines.get("zzfs1", "").split()[1:2] == ["DYN"] and lines.get("zzfs3", "").split()[1:2] == ["DYN"]
            and lines.get("zzfs2", "").split()[1:2] == ["DIR"], repr(sorted(lines)))
        for n, nm in ((1, "zzfs1"), (2, "zzfs3")):
            want7 = tag(fi, "FI%d" % n)
            w = want7[0].split("][") if want7 else []
            f = lines.get(nm, "").split()
            row("B2: %s: modulus, minimum modulus, group size, record count and the two sizes are FILEINFO's" % nm,
                len(w) == 7 and len(f) >= 9 and f[2:8] == [w[0], w[1], w[2], w[3], w[4], w[5]] and int(f[8]) == int(w[4]) + int(w[5]),
                "%r vs %r" % (f, w))
        f1 = lines.get("zzfs1", "").split()
        f3 = lines.get("zzfs3", "").split()
        row("B3: zzfs1 holds 40 records", len(f1) > 5 and f1[5] == "40", repr(f1))
        row("B3: zzfs3 shows its minimum modulus of 7 and Y for the index (AK), zzfs1 N", len(f3) >= 10 and f3[3] == "7" and f3[9] == "Y"
            and len(f1) >= 10 and f1[9] == "N", repr((f3, f1)))
        row("B3: the NC column is Y for files made now (case insensitive ids) and ST, NR, EN, RP, JN are N",
            len(f1) >= 17 and f1[12] == "Y" and [f1[11], f1[13], f1[14], f1[15], f1[16]] == ["N"] * 5, repr(f1))
        f2 = lines.get("zzfs2", "").split()
        row("B4: the directory file shows the record count 3 and no modulus, sizes or flags", f2[:3] == ["zzfs2", "DIR", "3"] and len(f2) == 3,
            repr(f2))
        out = q3.plain("zzaa", ["FILE.STAT zzfs2"])
        names = [ln.split()[0] for ln in out if re.match(r"^\S+\s+(DYN|DIR)\s", ln)]
        row("B5: a name on the command line reports that file only", names == ["zzfs2"], repr(names))
        out = q3.plain("zzaa", ["RUN bp zzfsl", "FILE.STAT"])
        names = [ln.split()[0] for ln in out if re.match(r"^\S+\s+(DYN|DIR)\s", ln)]
        row("B6: an active select list names the files: list 0 of zzfs2 reports zzfs2 only", names == ["zzfs2"], repr(names))
        out = q3.plain("zzaa", ["FILE.STAT DICT zzfs1"])
        row("B7: DICT reports the dictionary of zzfs1: a DYN line named zzfs1 with a record count of 1 (the @id item)",
            any(re.match(r"^zzfs1\s+DYN\s+\d+\s+\d+\s+\d+\s+1\s", ln) for ln in out), repr(out[-3:]))
        out = q3.plain("zzaa", ["FILE.STAT nosuchfile"])
        row("B8: a file that does not exist is skipped and the report says there was nothing to report", has(out, r"^No files to report$"),
            repr(out[-2:]))
        out = q3.plain("zzaa", ["FILE.STAT LPTR 99"])
        row("B9: an impossible print unit is refused (message 2053), nothing listed",
            not has(out, r"^zzfs"), repr(out[-2:]))

        say("\n--- C. BSCAN, ROOT and KEY ------------------------------------------------------------------------------------")
        q3.plain("zzaa", ["CREATE.FILE zzaix DYNAMIC", "RUN bp zzaisu", "CREATE.INDEX zzaix CITY", "BUILD.INDEX zzaix CITY"])
        ids_of = {"Lima": {"r10"}, "Oslo": {"r9"}, "Paris": {"r1", "r2", "r3", "r4", "r5"}, "Rome": {"r6", "r7", "r8"}}
        order = ["Lima", "Oslo", "Paris", "Rome"]

        def entry(s):
            """'Paris][r1,r2][1' -> ('Paris', {'r1', 'r2'}, '1')"""
            p = s.split("][")
            return (p[0], set(p[1].split(",")) if len(p) > 1 and p[1] else set(), p[2] if len(p) > 2 else None)

        out = q3.plain("zzaa", ["RUN bp zzbs1"])
        row("C1: BSCAN ... RESET (ascending) returns the leftmost entry: Lima, its one id r10, STATUS() 1",
            [entry(t) for t in tag(out, "AF")] == [("Lima", {"r10"}, "1")], repr(tag(out, "AF")))
        a = [entry(t) for t in tag(out, "A")]
        row("C1: ... and BSCAN with neither value nor RESET moves right through Oslo, Paris and Rome, with their ids",
            [(v, i, s) for v, i, s in a] == [(c, ids_of[c], "1") for c in order[1:]], repr(tag(out, "A")))
        row("C1: ... and at the end of the index the ELSE runs with STATUS() 0 and null value and ids", tag(out, "AEND") == ["][][0"],
            repr(tag(out, "AEND")))
        row("C2: BSCAN ... RESET BY D returns the rightmost entry (Rome) and BSCAN BY D then walks Paris, Oslo, Lima to the end",
            tag(out, "D1") == ["Rome"] and tag(out, "D") == ["Paris][1", "Oslo][1", "Lima][1"] and tag(out, "DEND") == ["][0"],
            repr((tag(out, "D1"), tag(out, "D"), tag(out, "DEND"))))
        row("C3: BSCAN with a value that is in the index returns it: Paris, 5 ids, STATUS() 1", tag(out, "V1") == ["Paris][5][1"],
            repr(tag(out, "V1")))
        row("C3: ... a value that is not (Q) returns the nearest entry to the right, Rome, with STATUS() 2 through the ELSE",
            [entry(t) for t in tag(out, "V2")] == [("Rome", ids_of["Rome"], "2")], repr(tag(out, "V2")))
        row("C3: ... and with BY D the nearest to the left (Pa -> Oslo), STATUS() 2", tag(out, "V3") == ["Oslo][2"], repr(tag(out, "V3")))
        row("C3: ... and the scan goes on from the entry found: after Rome, ascending, the next BSCAN is the end",
            tag(out, "V4") == ["Rome"] and has(out, r"^V5 ELSE$"), repr((tag(out, "V4"), has(out, r"^V5 ELSE$"))))
        row("C4: BSCAN refuses an index the file has not (STATUS() 4), a sequence that is not A or D (5) and a directory file (3)",
            tag(out, "E1") == ["4"] and tag(out, "E2") == ["5"] and tag(out, "E3") == ["3"],
            repr((tag(out, "E1"), tag(out, "E2"), tag(out, "E3"))))
        row("C4: the probe ran to its end", has(out, r"^BSDONE$"), repr(out[-3:]))

        out = q3.plain("zzaa", ["RUN bp zzky1"])
        row("C5: ROOT of an existing index takes THEN with STATUS() 0", tag(out, "ROOT") == ["0"], repr(out[:4]))
        nseq = (tag(out, "NSEQ") or [""])[0].split()
        row("C5: KEY('N') from null/null walks every entry: Lima, Oslo, Paris x5, Rome x3, each id once and with its own value",
            [p.split("/")[0] for p in nseq] == ["Lima", "Oslo"] + ["Paris"] * 5 + ["Rome"] * 3
            and all(p.split("/")[1] in ids_of[p.split("/")[0]] for p in nseq) and len({p for p in nseq}) == 10, repr(nseq))
        row("C5: ... and at the end the ELSE runs with STATUS() 3030", (tag(out, "NEND") or [""])[0].startswith("3030]"), repr(tag(out, "NEND")))
        pseq = (tag(out, "PSEQ") or [""])[0].split()
        row("C6: KEY('L') with a null key is the last entry (Rome and the last of its ids)",
            tag(out, "L") and tag(out, "L")[0].split("][")[0] == "Rome" and nseq and tag(out, "L")[0] == nseq[-1].replace("/", "]["),
            repr((tag(out, "L"), nseq[-1:])))
        row("C6: ... and KEY('P') walks the same entries backwards: the P walk is the N walk reversed, ending with STATUS() 3030",
            pseq == list(reversed(nseq)) and tag(out, "PEND") == ["3030"], repr((pseq, tag(out, "PEND"))))
        first = {"Paris": "(no entry)", "Rome": "(no entry)"}      # a walk that found nothing fails its own row, not the run
        for p in nseq:
            first.pop(p.split("/")[0], None)
        for p in nseq:
            first.setdefault(p.split("/")[0], p.split("/")[1])
        row("C7: KEY('C') from Pa gives Paris and its first id; from Paris the same; beyond the last value it fails with 3030",
            tag(out, "C1") == ["Paris][" + first["Paris"]] and tag(out, "C2") == ["Paris][" + first["Paris"]] and tag(out, "C3") == ["3030"],
            repr((tag(out, "C1"), tag(out, "C2"), tag(out, "C3"))))
        row("C7: KEY('R') gives the first id of the value, and fails with STATUS() 1 when there is no such value",
            tag(out, "R1") == ["Rome][" + first["Rome"]] and tag(out, "R2") == ["1"], repr((tag(out, "R1"), tag(out, "R2"))))
        row("C7: KEY('V') takes THEN for a pair in the index (Paris r2) and ELSE for one that is not (Paris r9)",
            has(out, r"^V1 THEN$") and has(out, r"^V2 ELSE\[1\]$"), repr(out))
        xs = (tag(out, "X") or [""])[0].split("][")
        row("C7: KEY('X') gives the five ids of Paris as a field mark delimited list",
            len(xs) == 2 and xs[0] == "5" and set(xs[1].split(",")) == ids_of["Paris"], repr(tag(out, "X")))
        row("C7: the operator in lower case works and the brackets are optional", tag(out, "LC") == [first["Rome"]], repr(tag(out, "LC")))
        row("C7: an operator that is not one of the seven fails with STATUS() 2", tag(out, "Q") == ["2"], repr(tag(out, "Q")))
        row("C8: ROOT of an index the file has not fails with 3019, of a file that is not there with a non-zero STATUS()",
            tag(out, "RT2") == ["3019"] and tag(out, "RT3") == ["1"], repr((tag(out, "RT2"), tag(out, "RT3"))))
        row("C8: the probe ran to its end", has(out, r"^KYDONE$"), repr(out[-3:]))
        out = q3.plain("zzaa", ["RUN bp zzlr1"])
        lt = tag(out, "L")
        row("D1: SELECTLEFTV from the position of Paris gives Oslo (r9) and then Lima (r10) as list variables, each with SETTING its value "
            "and STATUS() 0, @SELECTED the number of ids", lt[:2] == ["Oslo][r9][0][1", "Lima][r10][0][1"], repr(lt))
        end_status = (tag(out, "PLAINEND") or ["?]["])[0].split("][")[0]
        row("D1: ... and past the left end the list is empty, @SELECTED 0 and STATUS() what the plain SELECTRIGHT says at the end",
            len(lt) == 3 and lt[2] == "][][%s][0" % end_status and end_status not in ("0", "?"), repr((lt, tag(out, "PLAINEND"))))
        rt = tag(out, "R")
        row("D2: after SETLEFT, SELECTRIGHTV (no SETTING clause) walks Lima, Oslo, Paris, Rome: 1, 1, 5, 3 ids, then the end",
            rt == ["1][0", "1][0", "5][0", "3][0", "0][" + end_status], repr(rt))
        row("D3: an index the file has not leaves the STATUS() the plain SELECTRIGHT leaves (not 0)",
            tag(out, "BAD") == tag(out, "PLAINBAD") and tag(out, "BAD") not in ([], ["0"]), repr((tag(out, "BAD"), tag(out, "PLAINBAD"))))
        out = q3.plain("zzaa", ["RUN bp zzky2"])
        row("C9: CONTROL: a program with DIM KEY(3) still assigns and reads the matrix element key(1)", tag(out, "M") == ["xy"] and
            has(out, r"^KY2DONE$"), repr(out[-4:]))
        out = q3.plain("zzaa", ["RUN bp zzky3"])
        row("C9: CONTROL: variables called KEY, ROOT and BSCAN are still ordinary variables", tag(out, "S") == ["a,b"] and
            tag(out, "S2") == ["11"] and has(out, r"^KY3DONE$"), repr(out[-4:]))

        say("\n--- E. DISABLE.INDEX ------------------------------------------------------------------------------------------")
        q3.plain("zzaa", ["CREATE.FILE zzdix DYNAMIC", "RUN bp zzdisu", "CREATE.INDEX zzdix CITY", "BUILD.INDEX zzdix CITY"])
        q3.plain("zzaa", ["RUN bp zzdiw1"])
        before = q3.plain("zzaa", ["RUN bp zzdist BEF"])
        row("E1: BEFORE: the index is on (no need to build, updates enabled), a record written with a new value is in it at once "
            "(Rio 1) and a query for Paris finds 5", tag(before, "BEF") == ["0][1"] and tag(before, "BEFAK") == ["5,1,0,0"]
            and tag(before, "BEFQP") == ["5"], repr(before))
        held = q3.plain("zzaa", ["RUN bp zzdix2"])
        row("E2: with the file open in the running program the verb is refused (exclusive access) and the index stays enabled",
            tag(held, "HELD") == ["1"] and tag(held, "HELDSTILL") == ["1"], repr(held))
        out = q3.plain("zzaa", ["DISABLE.INDEX zzdix city"])
        row("E3: DISABLE.INDEX with the name in lower case disables CITY and says so", has(out, r"^Disabled index CITY$"), repr(out))
        q3.plain("zzaa", ["RUN bp zzdiw2"])
        after = q3.plain("zzaa", ["RUN bp zzdist AFT"])
        row("E4: AFTER: INDICES() says it needs a build and updates are off", tag(after, "AFT") == ["1][0"], repr(after))
        row("E4: ... records written meanwhile are not in the index (Kyiv 0, Nice 0), the stale entry for Paris stays at 5 and the "
            "Rio from before is still there", tag(after, "AFTAK") == ["5,1,0,0"], repr(tag(after, "AFTAK")))
        row("E4: ... and a query does not use it: the query finds 4 records for Paris (r1 is Nice now), the index would have said 5",
            tag(after, "AFTQP") == ["4"], repr(tag(after, "AFTQP")))
        out = q3.plain("zzaa", ["BUILD.INDEX zzdix CITY"])
        rebuilt = q3.plain("zzaa", ["RUN bp zzdist REB"])
        row("E5: BUILD.INDEX switches it on again and the index is right: enabled, Paris 4, Rio 1, Kyiv 1, Nice 1, query 4",
            tag(rebuilt, "REB") == ["0][1"] and tag(rebuilt, "REBAK") == ["4,1,1,1"] and tag(rebuilt, "REBQP") == ["4"], repr(rebuilt))
        out = q3.plain("zzaa", ["DISABLE.INDEX zzdix NOPE"])
        row("E6: an index the file has not is reported by name and nothing is disabled", has(out, r"Unrecognised index name \(NOPE\)")
            and not has(out, r"^Disabled"), repr(out))
        out = q3.plain("zzaa", ["DISABLE.INDEX zzfs1 ALL"])
        row("E6: a file without indices is told so", has(out, r"File has no indices"), repr(out))
        out = q3.plain("zzaa", ["DISABLE.INDEX zzfs2 ALL"])
        row("E6: a directory file is refused (dynamic file required)", has(out, r"Dynamic file required") and not has(out, r"^Disabled"),
            repr(out))
        out = q3.plain("zzaa", ["DISABLE.INDEX zzdix ALL"])
        again = q3.plain("zzaa", ["RUN bp zzdist ALL"])
        row("E7: ALL disables every index of the file", has(out, r"^Disabled index CITY$") and tag(again, "ALL") == ["1][0"], repr((out, again)))
        out = q3.plain("zzaa", ["DISABLE.INDEX zzdix"])
        row("E7: no index name and no ALL is refused", not has(out, r"^Disabled"), repr(out))

        say("\n--- F. SWAPMARKS() --------------------------------------------------------------------------------------------")
        out = q3.plain("zzaa", ["RUN bp zzswm"])
        row("F1: SWAPMARKS() returns the data unchanged on a system without ECS: marks and all, the same length",
            tag(out, "SWAP") and tag(out, "SWAP")[0].startswith("1][") and len(set(tag(out, "SWAP")[0].split("][")[1:])) == 1, repr(out))
        row("F1: a number and the null string come back as they are", tag(out, "SWAPN") == ["12.5][1"], repr(out))

        say("\n--- G. SYSTEM(1071) after OSREAD ------------------------------------------------------------------------------")
        out = q3.plain("zzaa", ["RUN bp zzosr"])
        row("G1: before any OSREAD SYSTEM(1071) is null", tag(out, "BEFORE") == [""], repr(out))
        row("G1: after a successful OSREAD it is the STATUS array of the file: permissions, size, links, owner, inode, times, path "
            "and type are those STATUS gives for the same file", tag(out, "SAME") == ["1111111111"], repr(out))
        row("G1: the size is the 13 bytes written and the pathname ends zzosr.txt; position, end-of-file and bytes-left are null "
            "(those mean something only for a sequential file being read)", tag(out, "SIZE") == ["13][zzosr.txt]["], repr(out))
        row("G2: after an OSREAD that took ELSE it is null again", tag(out, "BAD") == [""], repr(out))
        row("G2: ... and a good OSREAD after that fills it once more", tag(out, "AGAIN") == ["1"], repr(out))

        say("\n--- H. OPTION QUERY.MERGE.PRINT -------------------------------------------------------------------------------")
        res = {}
        for c in "ABCD":
            res[c] = q3.adm(["RUN bp zzmp " + c])
        # JOB[x][abc]: a = the job holds BEFOREMARK, b = it holds the report, c = it holds AFTERMARK
        row("H1: option on, printer on before the report: one job holds BEFOREMARK, the report and AFTERMARK (the report did not close it)",
            tag(res["B"], "JOB") == ["B][111"], repr(tag(res["B"], "JOB")))
        row("H1: CONTROL, option off, printer on before: the report closed the job; AFTERMARK started another that replaced it",
            tag(res["A"], "JOB") == ["A][001"], repr(tag(res["A"], "JOB")))
        row("H1: CONTROL, option on and then off again: as with the option never set",
            tag(res["D"], "JOB") == ["D][001"], repr(tag(res["D"], "JOB")))
        row("H1: CONTROL, option on, printer off before: nothing to merge into, the job is the report alone (the marks went to the screen)",
            tag(res["C"], "JOB") == ["C][010"], repr(tag(res["C"], "JOB")))

        say("\n--- I. PHANTOM GROUP, SYSTEM(1073) and the G in LISTU --------------------------------------------------------")
        out = q3.adm(["RUN bp zzgp1"])
        g = (tag(out, "GRP") or ["?"])[0]
        p = (tag(out, "PLN") or ["?"])[0]
        me = (tag(out, "ME") or ["?"])[0]
        row("I1: both phantoms started (user numbers given)", g.isdigit() and p.isdigit() and g != p, repr((g, p, out[:4])))
        row("I1: SYSTEM(1058) lists both children, SYSTEM(1052) counts 2, SYSTEM(1073) only the grouped one",
            tag(out, "KIDS") == ["%s,%s][2][%s" % (g, p, g)] or tag(out, "KIDS") == ["%s,%s][2][%s" % (p, g, g)], repr(tag(out, "KIDS")))

        def lu_line(lines, uid):
            for ln in lines:
                m = re.match(r"^\s*\*?\s*(\d+)\s+(\d+)\s+(\d+)(G?)\s", ln)
                if m and m.group(1) == uid:
                    return m
            return None

        lg, lp = lu_line(tag(out, "LU"), g), lu_line(tag(out, "LU"), p)
        row("I2: LISTU shows the grouped phantom's parent number followed by a G, the plain phantom's without",
            lg is not None and lg.group(3) == me and lg.group(4) == "G" and lp is not None and lp.group(3) == me and lp.group(4) == "",
            repr((tag(out, "LU"), me)))
        # the session that started them has ended; the grouped one must go, the plain one stays
        gone = False
        for _ in range(40):
            seen = q3.adm(["LISTU"])
            if lu_line(seen, g) is None:
                gone = True
                break
            time.sleep(0.5)
        seen = q3.adm(["LISTU"])
        row("I3: after the parent's session ended the grouped phantom was logged out", gone, repr(seen))
        row("I3: ... and the plain phantom (the control) is still there", lu_line(seen, p) is not None, repr(seen))
        q3.adm(["LOGOUT " + p])
        out = q3.adm(["RUN bp zzgp2"])
        g2 = (tag(out, "GRP2") or ["?"])[0]
        gone2 = False
        for _ in range(60):
            seen = q3.adm(["LISTU"])
            if lu_line(seen, g2) is None:
                gone2 = True
                break
            time.sleep(0.5)
        row("I4: a parent that ended before its grouped phantom had started: the phantom goes as soon as it has", g2.isdigit() and gone2,
            repr((g2, seen)))
        q3.adm(["LOGOUT " + g2])

        say("\n--- J. @PSTAT -------------------------------------------------------------------------------------------------")
        lv = {}
        for nm in ("zzps", "zzps0", "zzps1"):
            lv[nm] = q3.Live(nm, ["RUN bp " + nm])
        users = {}
        for nm, key in (("zzps", "PS"), ("zzps0", "PS0"), ("zzps1", "PS1")):
            ok = lv[nm].wait_for(r"(?m)^%s\[\d+\]" % key, 60)
            m = re.search(r"(?m)^%s\[(\d+)\]" % key, lv[nm].text())
            users[nm] = m.group(1) if (ok and m) else None
        row("J0: the three sessions are up with their own user numbers", all(users.values()) and len(set(users.values())) == 3, repr(users))
        if all(users.values()):
            o1 = q3.adm(["PSTAT USER " + users["zzps"]])
            o0 = q3.adm(["PSTAT USER " + users["zzps0"]])
            on = q3.adm(["PSTAT USER " + users["zzps1"]])
            row("J1: PSTAT shows the text @PSTAT holds, the marks in it as spaces", has(o1, r"^\s+app status 42 of 90 then more and a field mark$"),
                repr(o1))
            row("J1: CONTROL: a process that never set @PSTAT shows no text (and PSTAT still shows its account and command)",
                not has(o0, r"app status|^\s+0$") and has(o0, r"Account:"), repr(o0))
            row("J2: @PSTAT set to a number shows the number", has(on, r"^\s+77$"), repr(on))
        for l in lv.values():
            l.kill()

        say("\n--- K. SET.QUEUE and SP.ASSIGN ---------------------------------------------------------------------------------")
        out = q3.adm(["RUN bp zzfq 0"])
        first_out = out
        row("K0: before any SP.ASSIGN print unit 0 has form queue 0 and SYSTEM(1066) is -1",
            tag(out, "U") and tag(out, "U")[0].endswith("][0][-1"), repr(out))
        out = q3.adm(["SET.QUEUE 3,80,66,3,3,3,AS formjob3", "SET.QUEUE 7,90,60,0,2,1,AS q7job,COPIES 2", "SET.QUEUE 3", "SET.QUEUE DISPLAY"])
        row("K1: SET.QUEUE with only the queue reports it: width 80, depth 66, margins 3 and 3, mode 3, the options as typed",
            has(out, r"^\s+3\s+80\s+66\s+3\s+3\s+3\s+AS formjob3$"), repr(out))
        row("K1: SET.QUEUE DISPLAY lists both queues in numeric order",
            [ln.split()[0] for ln in out if re.match(r"^\s+\d+\s+\d+\s+\d+\s+\d+\s+\d+\s+\d+\s", ln)][-2:] == ["3", "7"], repr(out))
        out = q3.adm(["SP.ASSIGN F3", "RUN bp zzfq 0", "RUN bp zzfq2 formjob3"])
        row("K2: SP.ASSIGN F3 sets print unit 0 from queue 3: mode 3, width 80, depth 66, margins 3 and 3, form queue 3 (also SYSTEM(1066))",
            tag(out, "U") == ["0][3][80][66][3][3][1][3][3"], repr(out))
        row("K2: ... and the output reaches the hold record the queue named (AS formjob3)", tag(out, "HOLD") == ["1"], repr(out))
        out = q3.adm(["SP.ASSIGN 2R4F3", "RUN bp zzfq 4", "RUN bp zzfq 0"])
        base0 = (tag(first_out, "U") or ["?"])[0]
        row("K3: SP.ASSIGN 2R4F3 sets print unit 4, with 2 copies and form queue 3, and leaves unit 0 as a new session has it "
            "(SYSTEM(1066) is the last queue given to any unit: 3)",
            len(tag(out, "U")) == 2 and tag(out, "U")[0] == "4][3][80][66][3][3][2][3][3"
            and tag(out, "U")[1] == base0[:-2] + "3", repr((out, base0)))
        out = q3.adm(["SP.ASSIGN F7", "RUN bp zzfq 0"])
        row("K4: queue 7 is mode 1 with an AS option, which is for a hold file and is left out: SETPTR takes it and unit 0 is mode 1",
            len(tag(out, "U")) == 1 and tag(out, "U")[0].startswith("0][1][90][60][0][2][2][7]"), repr(out))
        out = q3.adm(["SP.ASSIGN HSF7", "RUN bp zzfq 0", "RUN bp zzfq2 q7job"])
        row("K4: HS makes it mode 3 and then the AS option stays: the line goes to the hold record q7job",
            tag(out, "U")[:1] == ["0][3][90][60][0][2][2][7][7"] and tag(out, "HOLD") == ["1"], repr(out))
        out = q3.adm(["SP.ASSIGN"])
        row("K5: CONTROL: in a new session SP.ASSIGN with nothing says print unit 0 uses form queue 0", has(out, r"^Print unit 0 uses form queue 0$"),
            repr(out))
        out = q3.adm(["SP.ASSIGN F7", "SP.ASSIGN"])
        row("K5: after SP.ASSIGN F7, SP.ASSIGN with nothing says print unit 0 uses form queue 7, and SETPTR's report follows",
            has(out, r"^Print unit 0 uses form queue 7$") and has(out, r"^\s+0\s+90\s+60\s+0\s+2\s+1\b"), repr(out))
        bad = {"SP.ASSIGN F999": r"Form queue 999 is not defined", "SP.ASSIGN S": r"The S option of SP.ASSIGN",
               "SP.ASSIGN X": r"SP.ASSIGN option X is not understood", "SP.ASSIGN R300F3": r"Print unit 300 is not valid",
               "SET.QUEUE 1000,80,66,0,0,3": r"form queue number is a whole number from 0 to 999",
               "SET.QUEUE 8,80,66,0,0,2": r"Mode 2 is not a printing mode", "SET.QUEUE 8,0,66,0,0,3": r"Width must be a whole number from 1 to 999",
               "SET.QUEUE 8,80,66": r"^SET.QUEUE queue, width", "SET.QUEUE 9": r"Form queue 9 is not defined"}
        for cmd, pat in bad.items():
            out = q3.adm([cmd])
            row("K6: %s is refused: %s" % (cmd, pat), has(out, pat), repr(out))
        out = q3.adm(["SET.QUEUE DELETING 3", "SET.QUEUE DELETING 7", "SET.QUEUE DISPLAY", "SP.ASSIGN F3"])
        row("K7: SET.QUEUE DELETING removes a queue, DISPLAY then says none is defined and SP.ASSIGN F3 cannot find it",
            has(out, r"^Deleted form queue 3$") and has(out, r"^Deleted form queue 7$") and has(out, r"^No form queues are defined$")
            and has(out, r"Form queue 3 is not defined"), repr(out))

        say("\n--- L. FSTAT.USER ---------------------------------------------------------------------------------------------")
        q3.adm(["CREATE.FILE zzfuf DYNAMIC"])
        idle = q3.Live("zzfui", ["RUN bp zzfui"])
        ok = idle.wait_for(r"(?m)^IDLE\[\d+\]", 60)
        m = re.search(r"(?m)^IDLE\[(\d+)\]", idle.text())
        idle_no = m.group(1) if (ok and m) else None
        row("L0: the idle session is up", idle_no is not None, repr(idle.text()[-200:]))
        if idle_no:
            out = q3.adm(["RUN bp zzfu " + idle_no])

            def counts(tagname):
                d = {}
                for t in tag(out, tagname):
                    m = re.match(r"^(Opens|Reads|Writes|Deletes|Clears|Selects|Index reads|Index writes|Index deletes|Splits|Merges)\s+(\d+)$", t)
                    if m:
                        d[m.group(1)] = int(m.group(2))
                return d

            a1, a2, i1, i2 = counts("A1"), counts("A2"), counts("I1"), counts("I2")
            me = (tag(out, "ME") or ["?"])[0]
            row("L1: FSTAT.USER USER n gives all eleven counts, before and after, for this session and the idle one",
                all(len(d) == 11 for d in (a1, a2, i1, i2)), repr((a1, a2, i1, i2)))
            if all(len(d) == 11 for d in (a1, a2, i1, i2)):
                dw, dr, dd = a2["Writes"] - a1["Writes"], a2["Reads"] - a1["Reads"], a2["Deletes"] - a1["Deletes"]
                row("L2: 100 writes, 50 reads and 7 deletes between the two reports show as writes +100 (a few more for the "
                    "command stack), reads +50 or more, deletes +7", 100 <= dw <= 110 and dr >= 50 and 7 <= dd <= 12, repr((dw, dr, dd)))
                row("L2: ... and none of it is counted for the idle session (its writes, deletes and selects did not move)",
                    all(i2[k] == i1[k] for k in ("Writes", "Deletes", "Selects", "Clears")), repr((i1, i2)))
                row("L2: the counts are of this session alone: its total reads are far below what the system has seen",
                    a2["Reads"] < 100000 and a2["Opens"] >= 1, repr(a2))
            tb = [t for t in tag(out, "TB")]
            rows_ = [re.match(r"^\s*(\d+)\s+(\S+)\s+(\d+)\s+(\d+)\s+(\d+)$", t) for t in tb]
            rows_ = [m for m in rows_ if m]
            row("L3: FSTAT.USER alone lists every session with its reads, writes and deletes, in user number order, this session and the "
                "idle one among them",
                any(m.group(1) == me for m in rows_) and any(m.group(1) == idle_no for m in rows_)
                and [int(m.group(1)) for m in rows_] == sorted(int(m.group(1)) for m in rows_), repr(tb))
            tp = [re.match(r"^\s*(\d+)\s+(\S+)\s+(\d+)\s+(\d+)\s+(\d+)$", t) for t in tag(out, "TP")]
            tp = [m for m in tp if m]
            act = [int(m.group(3)) + int(m.group(4)) + int(m.group(5)) for m in tp]
            row("L4: with TOP the same sessions are in descending order of reads + writes + deletes, this one first",
                tp and tp[0].group(1) == me and act == sorted(act, reverse=True) and len(tp) == len(rows_), repr(tag(out, "TP")))
        out = q3.adm(["FSTAT.USER USER 99999", "FSTAT.USER BOGUS", "FSTAT.USER USER x"])
        row("L5: a user who is not logged in is told so; a word it does not know is refused",
            has(out, r"No file activity to show for user 99999") and has(out, r"Unexpected token \(BOGUS\)"), repr(out))
        idle.kill()
    finally:
        for lv_ in q3.lives:
            lv_.kill()
        for nm in USER_PROGS:
            for d in ("bp", "bp.out"):
                p = os.path.join(SYS, d, nm)
                if os.path.exists(p):
                    os.remove(p)

    say("\nsandbox-q4: %d passed, %d failed" % (q3.passed, q3.failed))
    if q3.passed + q3.failed == 0:
        q3.bail("no row ran - a broken test, not a pass")
    return 1 if q3.failed else 0


if __name__ == "__main__":
    sys.exit(main())
