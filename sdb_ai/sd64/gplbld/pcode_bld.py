# pcode_bld
# generate pcode file
# Note we added a new directory to sdsys called PCODE.OUT. Standard scarlet / qm saves the object in 
# GPL.BP.OUT, this just makes it easier to see what the PCODE file (stored in bin) will comprise
# And allows us to do a diff on the pcode files compiled by BCOMP (for testing, not necessary once
#  everthing checks out)

import os
import subprocess
import sys
import array
import logging
logger = logging.getLogger(__name__)

# 14 Aug 26 Windows port - the sdsys path is an argument, not a constant.
#
# It was hardcoded to '/usr/local/sdsys', which is both a Linux path and a
# single one: pre-bootstrapping the install (PROJECT_STATUS.md 5.16) means
# running this against the tree being staged, wherever that is, so a constant
# cannot work.  The old value is kept only as the fallback, so running it with
# no argument behaves as it always did.
#
#   python3 gplbld/pcode_bld.py [sysdir]

SDSYS = sys.argv[1] if len(sys.argv) > 1 else '/usr/local/sdsys'

DEBUG_DIFF = False

pcode_fs = ["_AK",
"_BINDKEY"    ,
"_BREAK"      ,
"_CCONV"      ,
"_CHAIN"      ,
"_DATA"       ,
"_DELLIST"    ,
"_EXTENDLIST" ,
"_FMTS"       ,
"_FOLD"       ,
"_FORMCSV"    ,
"_FORMLST"    ,
"_GETLIST"    ,
"_GETMSG"     ,
"_HF"         ,
"_ICONV"      ,
"_ICONVS"     ,
"_IN"         ,
"_INDICES"    ,
"_INPUT"      ,
"_INPUTAT"    ,
"_ITYPE"      ,
"_KEYCODE"    ,
"_KEYEDIT"    ,
"_MAXIMUM"    ,
"_MESSAGE"    ,
"_MINIMUM"    ,
"_MSGARGS"    ,
"_NEXTPTR"    ,
"_OCONV"      ,
"_OCONVS"     ,
"_OJOIN"      ,
"_OVERLAY"    ,
"_PCLSTART"   ,
"_PREFIX"     ,
"_PRFILE"     ,
"_READLST"    ,
"_READV"      ,
"_REPADD"     ,
"_REPCAT"     ,
"_REPDIV"     ,
"_REPMUL"     ,
"_REPSUB"     ,
"_REPSUBST"   ,
"_SAVELST"    ,
"_SSELCT"     ,
"_SUBST"      ,
"_SUBSTRN"    ,
"_SUM"        ,
"_SUMALL"     ,
"_SYSTEM"     ,
"_TCONV"      ,
"_TRANS"      ,
"_VOC_CAT"    ,
"_VOC_REF"    ,
"_WRITEV"     ]


def main():

    global pcode_fs

    # set out buffer for creating our pcode file large enough to hold everything
    # rem gets initialized to null
    pcode_file = bytearray(65534)

    print('Generate pcode file')
    logging.basicConfig(filename='pcode_bld.log', filemode='w', level=logging.INFO)
    logger.info('Started')

    # command line: bbcmp.py sdsys sfp binfp
    # eg sudo python3 bbcmp.py /usr/local/sdsys GPL.BP/BBPROC GPL.BP.OUT/BBPROC
    # note - need root privilege to 
    # sdsys - path to sdsys, most likely "/usr/local/sdsys"
    # sfp -   directory and file name of source, appended to sdsys to resolve full path
    #         ie) GPL.BP/BCOMP for BCOMP source
    # binfn - directory and file name of pcode object file, appended to sdsys to resolve full path
    #         ie) GPL.BP.OUT/BCOMP.OUT
    # If $catlog directive found in source  bbcmp will also write the pcode object file to the global catalog file
    #         ie) for BCOMP,  $catalog $BCOMP is found in source.  bbcmp will write the pcode object file to
    #         sdsys/gcat/$BCOMP
    # 14 Aug 26 Windows port - find bbcmp beside this script rather than under
    # the working directory, so pcode_bld.py can be run from anywhere.
    bbcmp = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'bbcmp.py')
    logger.info('bbcmp.py path: ' + bbcmp)
    for src in pcode_fs:
        logger.info('**********************************************************************')
        result =   subprocess.run(
            [sys.executable,bbcmp,SDSYS,'gpl.bp/'+src,'pcode.out/'+src],
             capture_output=True,
             text = True)
        logger.info(result.stdout)
        if result.returncode:
            logger.info('error on compile **********************')
            logger.info(result.stderr)

    # 
    # compare to what bcomp generated ** must run COMP_PCODE prior to test!!
    # 
    if DEBUG_DIFF:
        for src in pcode_fs:
            logger.info('**********************************************************************')
        #diff --suppress-common-lines <(xxd /usr/local/sdsys/GPL.BP.OUT/_HF) <(xxd /usr/local/sdsys/PCODE.OUT/_HF)    
            result =   subprocess.run(
                ['xxd', SDSYS + '/gpl.bp.out/'+src, 'bsrc1'])
    #             capture_output=True,
    #             text = True)
            result =   subprocess.run(
                ['xxd', SDSYS + '/pcode.out/'+src, 'bsrc2'])
    #             capture_output=True,
    #             text = True)
            
            result =   subprocess.run(
                ['diff','--suppress-common-lines', 'bsrc1', 'bsrc2'],
                capture_output=True,
                text = True)
            
            logger.info(result.stdout)
            logger.info('error on diff **********************')
            logger.info(result.stderr)     

#
#  Now build up the pcode file to be stored in bin
#  Note BCOMP rounds up the length of each individual file to a multiple of 4 bytes
#  to ensure word alignment.   We do the samething here
    filebytes = array.array('B')
    p_idx = 0     # byte index for pcode_file
    for src in pcode_fs:
        f_byte_count = 0  # count of bytes in src file
        fh = open(SDSYS + os.sep + 'pcode.out' + os.sep + src, "rb")
        filebytes = bytearray(fh.read())
        for fbyte in filebytes:
            pcode_file[p_idx] = fbyte
            p_idx +=1
            f_byte_count += 1
 # do we need to add nulls to make mult of 4 bytes?   
        bytes_to_add = f_byte_count % 4
        if bytes_to_add == 0:
            pass
        else:
            bytes_to_add = 4 - bytes_to_add
            for i  in range(bytes_to_add):
                 p_idx +=1   # pcode_file is aready initialized to nulls, just move index   

# we should now have our pcode file ready for use, save to bin                      
    # cast Bytearray code_image to bytes
    immutable_bytes = bytes(pcode_file[:p_idx])   # truncate pcode to length actaully populated
 
    # Write bytes to file
    #with open(SDSYS + os.sep + 'PCODE.OUT' + os.sep + 'pcode', "wb") as binary_file:
    with open(SDSYS + os.sep + 'bin' + os.sep + 'pcode', "wb") as binary_file:
        binary_file.write(immutable_bytes)





    logger.info('Finished')

if __name__ == '__main__':
    main()