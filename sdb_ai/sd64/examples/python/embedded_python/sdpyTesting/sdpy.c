/* sdpy.c testing 
 *
 * mockup main module for calling (testing) embedded python functions
 *  to use, copy current:
 *    sdext_py.c
 *    err.h
 *    keys.h
 *    sdext_python_inc.h
 *  into this directory and compile and link as below:
 *
 *
 * compile with:
 *
 *     gcc -Wall sdpy.c sdext_py.c -c -g $(python3-config --cflags)
 * 
 * 
 * link with:
 * 
 *  to use python debug build (assuming its been installed!)
 * 
 *   gcc sdpy.o sdext_py.o -L/usr/lib/python3.12/config-3.12d-x86_64-linux-gnu -lpython3.12d -ldl  -lm -g -o sdpy 
 *
 *  to use normal python build
 * 
 *     gcc sdpy.o sdext_py.o $(python3-config --ldflags --embed) -g -o sdpy
 * 
 * To test for memory leaks: 
 * 
 * PYTHONMALLOC=malloc valgrind --leak-check=full  --show-leak-kinds=all --track-origins=yes  --verbose  --suppressions=valgrind-python.supp --log-file=valgrind-out.txt  ./sdpy

 * 
 valgrind --leak-check=full \
         --show-leak-kinds=all \
         --track-origins=yes \
         --verbose \
         --log-file=valgrind-out.txt \
         ./sdext
 *
 */
#include <stdio.h>
#include <string.h>
#include <stdlib.h>


#include <linux/limits.h>
#include <libgen.h>            /* needed for basename function */ 
      

#include </usr/include/python3.12/Python.h>
#include "sd.h"
#include "keys.h"

DESCRIPTOR descs[20];
struct PROCESS process;
DESCRIPTOR* e_stack;           /* Ptr to next e-stack descriptor */


/*************************************************************   Begin actual code */
// hooks to  functions to test
extern void sdext_py(int key, char* Arg, char* Arg2, char* Arg3 );

/* defined in sdext_py.c */
extern int PyDictCrte(char* dictname);
extern int PyDictClr(char* dictname );
extern int PyDictValSetS(char* dictname, char* key, char* value);
extern int PyDictValGetS(char* dictname, char* key);
extern int PyDictDel(char* dictname, char* key);

extern int PyStrSet(char* strname, char* strvalue );
extern int PyStrGet(char* strname );

extern int PyDelObj(char* objname);

/*************************************************************   Remove Main for production! */


int main(void)
{
 
  e_stack = descs;

  int myResult;

  char* Arg;
  char* Arg2;
  char* Arg3;

  char hello[] = "print(\"Hello World\")";
  char val[]   = "val = \"This is my string\"";

  char dict_test[] = "TD={}\nTD[\"k1\"] = \"Value 1\"\nTD[\"k2\"] = \"Value 2\"\nprint(TD)";
  char dict_FM[] = "TD[\"fm\"] = b\"FLD1\\xfeFLD2\\xfeFLD3\"";    /* rem  we are passing '\xfe' to python to do encoding hence \\ */

  Arg = NULL;
  Arg2 = NULL;
  Arg3 = NULL;
 
    printf("This is a embedded python test...\n");
    printf("size of descriptor %ld\n",sizeof(DESCRIPTOR));
    printf("Init Python.\n");
    sdext_py(SD_PyInit, Arg, Arg2, Arg3 );
    e_stack--;/* rem to keep e_stack from going out of range*/
    printf("TEST Result Process.status: %d estack %ld\n",process.status,e_stack-descs);

    printf("Run hello.\n");
    sdext_py(SD_PyRunStr, hello, Arg2, Arg3 );
    e_stack--;
    printf("TEST Result Process.status: %d estack %ld\n",process.status,e_stack-descs);

    printf("Run val.\n");
    sdext_py(SD_PyRunStr, val, Arg2, Arg3 );
    e_stack--;/* rem to keep e_stack from going out of range*/
    printf("TEST Result Process.status: %d estack %ld\n",process.status,e_stack-descs);

    printf("Get val.\n");
    sdext_py(SD_PyGetAtt, "val", Arg2, Arg3 );
    e_stack--;/* rem to keep e_stack from going out of range*/
    printf("TEST Result Process.status: %d estack %ld\n",process.status,e_stack-descs);

    printf("Run dict_test\n");
    sdext_py(SD_PyRunStr, dict_test, Arg2, Arg3 );
    e_stack--;/* rem to keep e_stack from going out of range*/
    printf("TEST Result Process.status: %d estack %ld\n",process.status,e_stack-descs);

    printf("Get TD\n");
    sdext_py(SD_PyGetAtt, "TD", Arg2, Arg3 );
    e_stack--;/* rem to keep e_stack from going out of range*/
    printf("TEST Result Process.status: %d estack %ld\n",process.status,e_stack-descs);

    printf("Get TD[k1] via PyDictValGetS\n");
    myResult = PyDictValGetS("TD", "k1" );
    printf("TEST Result status: %d \n",myResult);

    printf("Run dict_FM\n");
    sdext_py(SD_PyRunStr, dict_FM, Arg2, Arg3 );
    e_stack--;/* rem to keep e_stack from going out of range*/
    printf("TEST Result Process.status: %d estack %ld\n",process.status,e_stack-descs);  

    printf("Get TD[fm] via PyDictValGetS\n");
    myResult = PyDictValGetS("TD", "fm");
    printf("TEST Result status: %d \n",myResult);

    printf("set TD[k3] via PyDictValSetS\n");
    myResult = PyDictValSetS("TD", "k3", "the k3 value string" );
    printf("TEST Result status: %d \n",myResult);
    sdext_py(SD_PyRunStr, "print(TD)", Arg2, Arg3 );
    e_stack--;/* rem to keep e_stack from going out of range*/
    printf("TEST Result Process.status: %d estack %ld\n",process.status,e_stack-descs);  

    printf("Get TDx[k3] via PyDictValGetS\n");
    myResult = PyDictValGetS( "TDx", "k3");
    printf("TEST Result status: %d \n",myResult);

    printf("Get TD[kxx] via PyDictValGetS\n");
    myResult = PyDictValGetS( "TD", "kxx");
    printf("TEST Result status: %d \n",myResult);

    printf("Create dict TD test \n");
    myResult = PyDictCrte("TD");
    printf("TEST Result status: %d \n",myResult);

    printf("set TD[k3] via PyDictValSetS\n");
    myResult = PyDictValSetS( "TD", "k3", "the new k3 value string" );
    printf("TEST Result status: %d \n",myResult);
    sdext_py(SD_PyRunStr, "print(TD)", Arg2, Arg3 );
    e_stack--;/* rem to keep e_stack from going out of range*/
    printf("TEST Result Process.status: %d estack %ld\n",process.status,e_stack-descs);  

    printf("Clear dict TD test \n");
    myResult = PyDictClr("TD");
    printf("TEST Result status: %d \n",myResult);

    sdext_py(SD_PyRunStr, "print(TD)", Arg2, Arg3 );
    e_stack--;/* rem to keep e_stack from going out of range*/
    printf("TEST Result Process.status: %d estack %ld\n",process.status,e_stack-descs);  
  
    printf("Finalize\n");
    sdext_py(SD_PyFinal, "notshutdown", Arg2, Arg3 );
    e_stack--;/* rem to keep e_stack from going out of range*/
    printf("TEST Result Process.status: %d estack %ld\n",process.status,e_stack-descs);



  printf("Test complete\n");
  return 0;
}


/* proto functions for testing use only */
void k_put_c_string(char * str, DESCRIPTOR * descr){
// just output the string 
  if (strlen(str) == 0) {
    printf("Returned Empty String\n");
  } else {
    printf("Returned Str:  %s\n", str);
  }

  return;

}


