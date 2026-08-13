Binary Free Install process.
    
    A binary free install process requires a process to create:
   
       Compiled bytecode objects.
       
       Dynamic files (those with file names ~0, ~1).
       
    The following 5 programs (and 2 utility programs) make up the binary free install.
    
    CREATE_INSTALL_DICT_FILE  (found in gplbld):
      Program creates the Dictionary Template Files written to directory "FILES_DICTS", utilized by WRTIE_INSTALL_DICTS at install time.
      The process copies dictionary items from system files found on an operational SD system, to directory type files. 
      File name structure: "dynamic_file_name" ^ "dictionary_record_id"
      Note: The system files processed are hardcoded in CREATE_INSTALL_DICT_FILE
      
    WRITE_INSTALL_DICTS (found in GPL.BP):
      Program writes the dictionary items found in "FILES_DICTS" to associated system files.
      Executed as part of the install script.
    
    bbcmp.py - BootStrap Basic Compiler (found in gplbld).
      Program is used to compile bytecode objects during install process.
    
    pcode_bld.py (found in gplbld)- Python script to compile the pcode file bytecode object(s).
      Note the list of programs processed is hardcoded into pcode_bld.py.
      Script is executed at install time.
      
    BBPROC - BootStrap Command Processor (found in GPL.BP).
      This program is a stripped down command processor based on VBSRVR.
      It compiles the following programs (hardcoded list) using BCOMP compiled by bbcmp.py.

        'CPROC'
        'LOGIN'
        'BASIC'
        'BCOMP'
        'PTERM'
        'CATALOG'
        'PARSER'
        'IS_GRP_MEMBER'
        'TERM'
       
	   It then creates the following dynamic files:
	   
        "ACCOUNTS"
        "$HOLD"    
        "$MAP"     
        "$IPC"     
        "DICT.DIC"  
        "DIR_DICT" 
        "VOC.DIC" 	   
      
      
    
    Utility programs:
    
    COMP_PCODE (found in gplbld):
      Program creates the pcode file via the SD  basic compiler BCOMP. It was used to create a pcode file in a known file layout (to aid in pcode_bld.py verification).
    
    INSTALL_FILE_INFO (found in gplbld):
      Program was used to retrieve file information on existing system files (to determine the parameters to pass to create.file during system install).   


    Basic setup:
    No program object in GPL.BP.OUT / BP.OUT / gcat
    No binaries in bin, including pcode file
    No object files in gplobj
    No dynamic files.
    
    In short everything is built at install time
    
    Steps:
	
    install runs bbcmp.py to create program objects for:
     BCOMP
     BBPROC
     PATHTKN
    
    install runs pcode_bld.py to build pcode file
  
    install runs sd in install mode to run the bootstrap command processor BBPROC
      sudo /usr/local/sdsys/bin/sd -start
      sudo /usr/local/sdsys/bin/sd -i
        This step runs the BBPROC command processor, currently requires a <CR> to continue
        
    install runs second compile
      sudo /usr/local/sdsys/bin/sd -asdsys -internal SECOND.COMPILE   
	  
	install runs WRITE_INSTALL_DICTS to create system dictionary items.
      sudo bin/sd RUN GPL.BP WRITE_INSTALL_DICTS NO.PAGE
 