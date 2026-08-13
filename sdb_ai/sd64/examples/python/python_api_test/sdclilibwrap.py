# sdclilibwrap.py
# wrapper for sdclilib functions
#
# Heavily dependent on qmclient.py  Release 3.4-5 found with the waybackmachine:
# https://web.archive.org/web/20160619110442/http://downloads.openqm.com/downloads/qmclient/qmclient.py
#
# Another option worth investigating is ctypesgen https://github.com/ctypesgen/ctypesgen
# "ctypesgen is a pure-python ctypes wrapper generator. It parses C header files and creates a wrapper for libraries based on what it finds."
# Problems to invstigate - Freeing returned buffers (char*)
# On the plus side it looks as though there is a lot of work put into handling string issues (byte vs unicode)
# https://realpython.com/python-encodings-guide/
# rem Latin-1 (ISO-8859-1) has all 256 characters defined
# The results of str.encode() (or Bytes(strobj,'latin-1') is a bytes object.
# Use str.decode(bytes,'latin-1') to reverse
#
#SDClient wrapper for Python 3.5
#
#Jointly developed by Ladybridge Systems and George R Smith.
#
#Use:
# import SDClient as sd to import this module into your application.
#  Then, all SDClient function  names are accessed as "sd.Name" where
#  the leading "SD" of the documented library function name is replaced
#  by 'sd.'
#  For example, SDRead becomes sd.Read
#
#
#  The status codes returned by some functions are:
#     SV_OK         0   Action successful
#     SV_ON_ERROR   1   Action took ON ERROR clause
#     SV_ELSE       2   Action took ELSE clause
#     SV_ERROR      3   Action failed. Error text available
#     SV_LOCKED     4   Action took LOCKED claus
#     SV_PROMPT     5   Server requesting input
#
#  For more details of the functions, see the QM Reference Guide. The
#  function names in the comment bars below are the names as they
#  appear in the documentation.
#

import ctypes
import os

# wrapper to the sdclilib
# 
# SDCallx
# SDClose
# SDConnect
# SDConnected
# SDDcount
# SDDebug
# SDDisconnect
# SDDisconnectAll
# SDError
# SDExecute
# SDExtract
# SDFree
# SDGetArg
# SDGetSession
# SDIns
# SDLocate
# SDOpen
# SDRead
# SDReadl
# SDReadu
# SDRecordlock
# SDRelease
# SDReplace
# SDSetSession
# SDStatus
# SDWrite
# SDWriteu

# Note: __foo: This has real meaning (double underscore). The interpreter replaces this name with
#  _classname__foo as a way to ensure that the name will not overlap with a similar name in another class.
#

__sdClilib = None

#
def sdmeInitialize():
    
    global __sdClilib

    if __sdClilib is None:
        if os.name == 'nt':
            LIBRARY_PATH = '.\\winsdclilib.dll'
        else:
            LIBRARY_PATH = os.getcwd() +"/sdclilib.so"
    __sdClilib = ctypes.cdll.LoadLibrary(LIBRARY_PATH)

def sdmeConnect(host, port, username, password, account):
    host = bytes(host,'latin-1')
    username = bytes(username,'latin-1')
    password = bytes(password,'latin-1')
    account =  bytes(account,'latin-1')
    libfunc = __sdClilib.SDConnect
    libfunc.argtypes = [ctypes.c_char_p, ctypes.c_int, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p]
    return libfunc(host, port,username, password, account) 

def sdmeConnectLocal(account):
    account =  bytes(account,'latin-1')
    libfunc = __sdClilib.SDConnectLocal
    libfunc.argtypes = [ctypes.c_char_p]
    return libfunc(account) 


def sdmeLogto(account):
    account =  bytes(account,'latin-1')
    libfunc = __sdClilib.SDLogto
    libfunc.argtypes = [ctypes.c_char_p]
    return libfunc(account)
  
def sdmeConnected():
    return __sdClilib.SDConnected()

def sdmeDisconnect():
    __sdClilib.SDDisconnect()    
 
  
def sdmeError():
    libfunc = __sdClilib.SDError
    libfunc.restype = ctypes.c_void_p
    s = libfunc()
    err = ctypes.string_at(s)
    err = str(err,'latin-1')
    return err
    
def sdmeStatus():
    libfunc = __sdClilib.SDStatus
    libfunc.restype = ctypes.c_int
    return libfunc()
 
#
def sdmeLogto(account_name):
    account_name = bytes(account_name,'latin-1')
    libfunc = __sdClilib.SDLogto
    libfunc.argtypes = [ctypes.c_char_p]
    libfunc.restype = ctypes.c_int
    return libfunc(account_name)

#
def sdmeOpen(filename):
    filename = bytes(filename,'latin-1')
    libfunc = __sdClilib.SDOpen
    libfunc.argtypes = [ctypes.c_char_p]
    return libfunc(filename)

# 
def sdmeClose(fno):
    libfunc = __sdClilib.SDClose
    libfunc.argtypes = [ctypes.c_int]
    libfunc(fno)

#
def sdmeRead(fno, id):
    id = bytes(id,'latin-1')
    libfunc = __sdClilib.SDRead
    libfunc.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_void_p]
    libfunc.restype = ctypes.c_void_p
    err = ctypes.c_int()
    data = libfunc(fno, id, ctypes.byref(err))
    rec = ctypes.string_at(data)
    rec = str(rec,'latin-1')
    __Free(data)
    return rec, err.value

# 
def sdmeWrite(fno, id, data):
    id = bytes(id,'latin-1')
    data = bytes(data,'latin-1')   
    libfunc = __sdClilib.SDWrite
    libfunc.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_char_p]
    libfunc.restype = ctypes.c_int
    return libfunc(fno, id, data)

#
def sdmeCallx(subname, argcnt,
             arg1=None, arg2=None, arg3=None, arg4=None,
             arg5=None, arg6=None, arg7=None, arg8=None,
             arg9=None,  arg10=None, arg11=None, arg12=None,
             arg13=None, arg14=None, arg15=None, arg16=None,
             arg17=None, arg18=None, arg19=None, arg20=None):
    
    if arg1:
        arg1 = bytes(arg1,'latin-1')
    if arg2:
        arg2 = bytes(arg2,'latin-1')
    if arg3:
        arg3 = bytes(arg3,'latin-1')
    if arg4:
        arg4 = bytes(arg4,'latin-1')    
                
    subname = bytes(subname,'latin-1')
    libfunc = __sdClilib.SDCallx     
    libfunc.argtypes = [ctypes.c_char_p, ctypes.c_short,
                     ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p,
                     ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p,
                     ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p,
                     ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p,
                     ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p]

    libfunc(subname, argcnt,
             arg1, arg2, arg3, arg4,
             arg5, arg6, arg7, arg8,
             arg9,  arg10, arg11, arg12,
             arg13, arg14, arg15, arg16,
             arg17, arg18, arg19, arg20)

#
def sdmeGetArg(arg_nbr):
    libfunc = __sdClilib.SDGetArg
    libfunc.argtypes = [ctypes.c_int]
    libfunc.restype = ctypes.c_void_p
    data = libfunc(arg_nbr)
    arg = ctypes.string_at(data)
    arg = str(arg,'latin-1')
    __Free(data)
    return arg         
#
def sdmeDcount(s, delim):
    s= bytes(s,'latin-1')
    delim= bytes(delim,'latin-1')
    libfunc = __sdClilib.SDDcount
    libfunc.argtypes =  [ctypes.c_char_p, ctypes.c_char_p]
    return libfunc(s, delim) 

def sdmeExecute(command):
    command = bytes(command,'latin-1')
    libfunc = __sdClilib.SDExecute
    libfunc.argtypes = [ctypes.c_char_p, ctypes.c_void_p]
    libfunc.restype = ctypes.c_void_p
    err = ctypes.c_int()
    s = libfunc(command, ctypes.byref(err))
    out_str = ctypes.string_at(s)
    out_list = str(out_str,'latin-1').split(chr(254))
    out_str = '\n'.join(out_list)
    __Free(s)
    return out_str, err.value

def sdmeExtract(in_str, f, v, sv):
    in_str = bytes(in_str,'latin-1')
    libfunc =__sdClilib.SDExtract
    libfunc.argtypes = [ctypes.c_char_p, ctypes.c_int, ctypes.c_int, ctypes.c_int]
    libfunc.restype = ctypes.c_void_p
    s = libfunc(in_str, f, v, sv)
    out_str = ctypes.string_at(s)
    out_str = str(out_str,'latin-1')
    __Free(s)
    return out_str



def sdmeField(in_str, delim, occurrence, count):
    in_str = bytes(in_str,'latin-1')
    delim = bytes(delim,'latin-1')
    libfunc = __sdClilib.SDField
    libfunc.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_int, ctypes.c_int]
    libfunc.restype = ctypes.c_void_p
    s = libfunc(in_str, delim, occurrence, count)
    out_str = ctypes.string_at(s)
    out_str = str(out_str,'latin-1')
    __Free(s)
    return out_str    
#
def __Free(p):
  __sdClilib.SDFree(ctypes.c_void_p(p))

if __name__ == '__main__':
    pass

