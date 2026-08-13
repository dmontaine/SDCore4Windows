/* OP_SDPYOBJ.C
 *
 * python integration for SD, BASIC function SD_PYOBJ
 * Copyright (c)2025 The SD Developers, All Rights Reserved
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
 * rev 0.9-2 Apr 25 mab op_sd_pyobj
 * END-HISTORY
 *
 * START-DESCRIPTION:
 *
 * Opcodes:
 *    op_sdpyobj   SDPYOBJ   
 *    for basic function SD_PYOBJ(Function_id, ARG1, ARG2, ARG3)
 *    where:
 *    Function_Id = the integer value used to identify what c code / function is execute.
 *    Arg1,2,3     = string value passed to the c code / function. 
 *
 * END-DESCRIPTION
 *
 
 * START-CODE
 */


#include <linux/limits.h>


#include "sd.h"
#include "sdext_python_inc.h"  /* NOTE! this file is created by the install script !!! */
#include "keys.h"

/* Modified by Composer AI - 2026/06/10.
   k_error() longjmps and never returns; redeclare noreturn for analyzer. */
void k_error(char msg[], ...) __attribute__((noreturn));
/* -------------------- */

/* defined in sdext_py.c */
extern int PyDictCrte(char* dictname);
extern int PyDictClr(char* dictname );
extern int PyDictValSetS(char* dictname, char* key, char* value);
extern int PyDictValGetS(char* dictname, char* key);
extern int PyDictDel(char* dictname, char* key);
extern int PyDictKeysS(char* dictname);
extern int PyDictValuesS(char* dictname);

extern int PyStrSet(char* strname, char* strvalue );
extern int PyStrGet(char* strname );

extern int PyListGet(char* listname );
extern int PyListAppd(char* listname, char* objname);
extern int PyListClr(char* listname);

extern int PyObjLen(char* objname);
extern int PyObjType(char* objname);

extern int PyDelObj(char* objname);

Private void sdme_err_rsp(int errnbr);
Private char* getarg();
Private char* freeArg(char* Arg);

/* ======================================================================
   op_sdpyobj()   op code for BASIC function SD_PYOBJ   
 
      Stack:
        +=============================++=============================+
        +       STACK On Entry        ++       STACK On Exit         +
        +=============================++=============================+
estack> +    next available descr     ++    next available descr     +
        +=============================++=============================+
        +  descriptor w/ integer      ++  Addr to descr for RTNVAL   +
        +      key value              ++                             +
        +=============================++=============================+
        + Addr to descriptor for Arg1 ++  
        +=============================++
        + Addr to descriptor for Arg2 ++   
        +=============================++
        + Addr to descriptor for Arg3++   
        +=============================++
		
	   patterned from op_ospath() in op_dio2.c */

void op_sdpyobj() {

  int16_t key;
  char* Arg1;    /* pointers to string buffers created to hold user passed data */
  char* Arg2;
  char* Arg3;

  int myResult;

  DESCRIPTOR* descr;
  
  /* set the process.status flag to  "successful"      */
  /* User can retrieve this status with the BASIC function STATUS()*/
  process.status = 0;
  myResult = 0;
  Arg1 = NULL;
  Arg2 = NULL;
  Arg3 = NULL;

  /* Get action key */
  descr = e_stack - 1;   /* e_stack - 1 points to key descriptor */
  GetInt(descr);
  key = (int16_t)(descr->data.value);
  k_pop(1);   /* after pop() e_stack - 1 points to descr which holds ARG1  */

  Arg1 = getarg(); /* get string Arg from descr and dismiss() */
  Arg2 = getarg();
  Arg3 = getarg();
  /* rem e_stack now points to descr for return value */

  if (!Py_IsInitialized()) {  /* functions only avaialble if python already initialized */
    sdme_err_rsp(SD_PyEr_NotInit);
    return;
  }


  /* look for sd_pyobj function key */
  switch (key) {

  /********************* dictionary objects **********************/   

    case SD_PyDictCrte: 
      /* Creaete new dictionary for sd */
      // Arg1 is name of dictionary to create
      myResult = PyDictCrte(Arg1);
      process.status = myResult;
      InitDescr(e_stack, INTEGER);
      (e_stack++)->data.value = (int32_t)myResult;
      break;

    case SD_PyDictClr: 
      /* Clear  dictionary Keys and Values, (Name remains in global dictionary) for sd */
      // Arg1 is name of dictionary to Clear
      myResult = PyDictClr(Arg1);
      process.status = myResult;
      InitDescr(e_stack, INTEGER);
      (e_stack++)->data.value = (int32_t)myResult;
      break;


    case SD_PyDictVset:
      /* set dictionary key : value    */
      // Arg1 is name of dictionary object
      // Arg2 is key
      // Arg3 is value to set
      myResult = PyDictValSetS(Arg1, Arg2, Arg3 );
      process.status = myResult;
      InitDescr(e_stack, INTEGER);
      (e_stack++)->data.value = (int32_t)myResult;
      break;

    case SD_PyDictVget:
      /* get value of dictionary item key   */
      // Arg1 is name of dictionary object
      // Arg2 is key
      // value will be placed in data descriptor by PyDictValGet
      /* rem value ends up as string and must be returned to sd with
         k_put_c_string(pyResult, e_stack) in PyDictValGetS;*/
      myResult = PyDictValGetS(Arg1, Arg2);    
      process.status = myResult;
      e_stack++;
      break;

    case SD_PyDictIDel:
      /* delete item (key / value) from dictionary */
      // Arg1 is name of dictionary object
      // Arg2 is key 
      // key / value is deleted from dictionary
      myResult = PyDictDel(Arg1, Arg2);  
      process.status = myResult;  
      InitDescr(e_stack, INTEGER);
      (e_stack++)->data.value = (int32_t)myResult;
      break;

    case SD_PyDictKeys:
      /* get dictionary keys as fld mrked separated string list   */
      // Arg1 is name of dictionary object
      // value will be placed in data descriptor by PyDictKeysS
      /* rem value ends up as string and must be returned to sd with
         k_put_c_string(pyResult, e_stack) in PyDictKeysS;*/
      myResult = PyDictKeysS(Arg1);    
      process.status = myResult;
      e_stack++;
      break;  

    case SD_PyDictValues:
      /* get dictionary values as fld mrked separated string list   */
      // Arg1 is name of dictionary object
      // value will be placed in data descriptor by PyDictValuesS
      /* rem value ends up as string and must be returned to sd with
         k_put_c_string(pyResult, e_stack) in PyDictValuesS;*/
      myResult = PyDictValuesS(Arg1);    
      process.status = myResult;
      e_stack++;
      break;   

    /********************* string (unicode) objects **********************/    

    case SD_PYStrSet:
      /* create and or set string */
      // Arg1 is name of string object
      // Arg2 is string value 

      myResult = PyStrSet(Arg1, Arg2);    
      process.status = myResult;
      InitDescr(e_stack, INTEGER);
      (e_stack++)->data.value = (int32_t)myResult;
      break;

    case SD_PYStrGet:
      /* get value of string   */
      // Arg1 is name of string object
      // value will be placed in data descriptor by PyStrGet
      /* rem value ends up as string and must be returned to sd with
         k_put_c_string(pyResult, e_stack) in PyStrGet;*/
      myResult = PyStrGet(Arg1);    
      process.status = myResult;
      e_stack++;
      break;  

    /********************* list objects **********************/  

    case SD_PyListGet:
      /* get list items as fld mrk separated string list   */
      // Arg1 is name of List object
      // value will be placed in data descriptor by PyListGet
      /* rem value ends up as string and must be returned to sd with
        k_put_c_string(pyResult, e_stack) in PyListGet;*/
      myResult = PyListGet(Arg1);    
      process.status = myResult;
      e_stack++;
      break;  

    case SD_PyListAppd:
      /* Append object to list */
      // Arg1 is name of list object
      // Arg2 is name of object to append

      myResult = PyListAppd(Arg1, Arg2);    
      process.status = myResult;
      InitDescr(e_stack, INTEGER);
      (e_stack++)->data.value = (int32_t)myResult;
      break;  

    case SD_PyListClr:
      /* Clear list */
      // Arg1 is name of list object
 
      myResult = PyListClr(Arg1);    
      process.status = myResult;
      InitDescr(e_stack, INTEGER);
      (e_stack++)->data.value = (int32_t)myResult;
      break;   

    /********************* other functions **********************/   
    case SD_PYDelObj:
    /* delete python object */
      // Arg1 is name object
      // What this function does is removes the object from the global dictionary.
      // This should remove all references to the object, resulting in its deletion
      // via python garbage collection
      // Using valgrind to test for memory leaks results in chunks for memory being marked as
      //   "still reachable"
      // I have not been able to determine if this is indeed a memory leak or simply something that is
      // a result of how python garbage collection works however I have read:
      //  still reachable means your program is probably ok -- it didn't free some memory it could have. 
      //  This is quite common and often reasonable.
      //  Don't use --show-reachable=yes if you don't want to see these reports.

      myResult = PyDelObj(Arg1);    
      process.status = myResult;
      InitDescr(e_stack, INTEGER);
      (e_stack++)->data.value = (int32_t)myResult;
      break;

    case SD_PyObjLen:
      /* Get object lenght (size) */
      // Arg1 is name object

      myResult = PyObjLen(Arg1);    
      process.status = myResult;
      InitDescr(e_stack, INTEGER);
      (e_stack++)->data.value = (int32_t)myResult;
      break; 

    case SD_PyObjType:
      /* Get object lenght (size) */
      // Arg1 is name object

      myResult = PyObjType(Arg1);    
      process.status = myResult;
      InitDescr(e_stack, INTEGER);
      (e_stack++)->data.value = (int32_t)myResult;
      break; 

  
    default:
      /* unknown key */
      sdme_err_rsp(SD_EXT_KEY_ERR);

  }
  
  /* release our arg Buffers  */
  Arg1 = freeArg(Arg1);
  Arg2 = freeArg(Arg2);
  Arg3 = freeArg(Arg3);

  return;
}


Private char* getarg(){
/* get args from stack  */
  DESCRIPTOR* descr;
  STRING_CHUNK* str;
  int32_t myval_len;
  int32_t mybuf_sz;
  char* arg;

  arg = NULL;

  /* Get val string */
  descr = e_stack - 1;
  k_get_string(descr);
  str = descr->data.str.saddr;

  /* is there something there? */
  if (str == NULL){
	myval_len = 0;  
    mybuf_sz = 1;              /* room for string terminator */
  }else{
	myval_len =  str->string_len;
    mybuf_sz  =  myval_len+1; /* room for string terminator */
  }
  
  /* allocate space for arg val string */
  arg = malloc(mybuf_sz * sizeof(char));
  if (arg == NULL){
    /* so here is a question, what to do if we cannot allocate memory?
	 We will end execution of program and attempt to report error  */
    k_error(sysmsg(10005));   /* Insufficient memory for buffer allocation */
	/* We never come back from k_error */
  }

  /* move the passed argument string to our buffer */
  if (myval_len == 0){
    arg[0] = '\0';
  } else {
   /* rem string length returned by k_get_c_string excludes terminator in count!*/ 
    myval_len = k_get_c_string(descr, arg, myval_len);
  }
  
  k_dismiss();   /* done with passed arg  descriptor */
                 /* Things to note                   */  
                 /* we use dismiss() instead of pop() because this is a string */ 
                 /* which may be made up of a linked list of string blocks     */
                 /* Using pop would not free the sting blocks                  */
                 /* After dismiss() e_stack  points to next descr on stack,    */
                 /* either the descr for next Arg or the one to receive RTNVAL */
  return arg;
}

Private char* freeArg(char* Arg){
    if (Arg != NULL){
        free(Arg);    
    } 
    return NULL;
  }

/* generic error return with null response, setting process.status */
Private void sdme_err_rsp(int errNbr){
  char EmptyResp[1] = {'\0'}; /*  empty return message  */
  k_put_c_string(EmptyResp, e_stack); /* sets descr as type string, empty */
  e_stack++;
  process.status = errNbr;

}
